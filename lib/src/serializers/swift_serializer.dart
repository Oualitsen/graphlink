import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';

class SwiftSerializer extends GLSerializer {
  final codeGenUtils = SwiftCodeGenUtils();

  @override
  Map<String, String> get defaultTypeMap => const {
        'ID': 'String',
        'String': 'String',
        'Float': 'Double',
        'Int': 'Int',
        'Boolean': 'Bool',
        'Null': 'NSNull',
        'gqlMapStrObj': '[String: Any?]',
        'dynamicValue': 'Any',
        'void': 'Void',
      };

  /// `let` vs `var` for every generated struct's stored properties — a
  /// single flag covering both types and inputs, since Swift structs (unlike
  /// Kotlin's data-class/open-class duality) have no other axis that would
  /// need a second flag. Mirrors `SwiftClientConfig.immutableTypeFields`.
  final bool immutableTypeFields;

  SwiftSerializer(
    super.grammar, {
    this.immutableTypeFields = true,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  });

  @override
  String serializeType(GLType def) {
    if (def is GLVoidType) {
      return 'Void';
    }
    String type;
    if (def is GLMapType) {
      type = '[${serializeType(def.keyType)}: ${serializeType(def.valueType)}]';
    } else if (def is GLListType) {
      type = '[${serializeType(def.inlineType)}]';
    } else {
      final token = def.token;
      type = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
    }
    final wrapper = def.wrapper;
    if (wrapper != null) {
      type = '$wrapper<$type>';
    }
    return def.nullable ? '$type?' : type;
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField, {bool isOverride = false}) {
    final type = serializeType(def.type);
    final keyword = immutable ? 'let' : 'var';
    final deprecation = serializeFieldDeprecation(def);
    final name = def.codeName;
    final line = def.type.nullable ? 'public $keyword $name: $type = nil' : 'public $keyword $name: $type';
    return '$deprecation$line';
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    return '${_deprecatedAttribute(field.deprecationReason)}\n';
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    return _deprecatedAttribute(value.deprecationReason);
  }

  String _deprecatedAttribute(String? reason) {
    final escaped = (reason ?? 'No longer supported')
        .escapeForStringLiteral()
        .replaceAll('\r', '')
        .replaceAll('\n', r'\n');
    return '@available(*, deprecated, message: "$escaped")';
  }

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final cases = def.values.map(doSerializeEnumValue).toList();

    final toJson = 'public ${codeGenUtils.method(
      returnType: 'String',
      methodName: 'toJson',
      statements: ['return rawValue'],
    )}';
    final fromJson = 'public static ${codeGenUtils.createMethod(
      returnType: def.codeName,
      methodName: 'fromJson',
      arguments: ['_ value: String'],
      statements: ['return ${def.codeName}(rawValue: value)!'],
    )}';

    return codeGenUtils.enumDecl(
      name: def.codeName,
      cases: cases,
      extraBody: [toJson, fromJson],
    );
  }

  /// Every case gets an explicit `= "wireToken"` raw value — always correct
  /// regardless of whether [GLEnumValue.codeName] happens to equal the wire
  /// token (a reserved-word collision resolves via the same
  /// [swiftReservedWords]-driven `codeName` rename every other target
  /// language uses — e.g. `default` → `default_` — so relying on Swift's
  /// implicit-rawValue-from-case-name convention would silently pick up the
  /// renamed value instead of the real wire string).
  @override
  String doSerializeEnumValue(GLEnumValue value) {
    final deprecation = serializeEnumValueDeprecation(value);
    final prefix = deprecation.isEmpty ? '' : '$deprecation\n';
    return '${prefix}case ${value.codeName} = "${value.value.token}"';
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);

    final storedFields = fields.map((f) => _storedFieldDecl(f, immutableTypeFields)).toList();
    final initParams = fields.map(_initParam).toList();
    final initAssignments = fields.map((f) {
      final name = f.codeName;
      return 'self.$name = $name';
    }).toList();

    final extraBody = [
      'public ${_generateToJson(fields, def)}',
      'public static ${_generateFromJson(fields, def.codeName, def)}',
      // @glMapsTo: toXxx()/fromXxx() slot into the same struct body flatly —
      // unlike Kotlin, Swift has no separate companion-object namespace to
      // route the static fromXxx() into, so both go straight into extraBody.
      ...generateMappingMethods(def),
    ];

    return codeGenUtils.structDecl(
      name: def.codeName,
      fields: storedFields,
      initDecl: codeGenUtils.initDecl(params: initParams, assignments: initAssignments),
      extraBody: extraBody,
      conformances: const ['Sendable'],
    );
  }

  /// `name: Type = default` for a stored-property initializer parameter.
  /// Explicit GraphQL defaults take priority over the plain `= nil` a
  /// nullable field would otherwise get.
  String _initParam(GLField f) {
    final type = serializeType(f.type);
    final name = f.codeName;
    if (f.initialValue != null) {
      return '$name: $type = ${serializeDefaultLiteral(f.type, f.initialValue)}';
    }
    if (f.type.nullable) {
      return '$name: $type = nil';
    }
    return '$name: $type';
  }

  /// Bare `public let/var name: Type` stored-property declaration — no
  /// inline default. Every generated struct has an explicit `init` (Swift
  /// never auto-synthesizes a `public` memberwise one), and Swift rejects a
  /// stored property that's both given an inline default *and* assigned in
  /// an `init` ("immutable value may only be initialized once"). The
  /// default, if any, belongs solely on the `init` parameter — see
  /// [_initParam] — never here. This is deliberately not [doSerializeField]:
  /// that method mirrors Kotlin's primary-constructor-parameter-as-property
  /// shape (declaration, default, and init parameter all merged into one
  /// line), which is exactly the shape Swift's separate
  /// property-declaration/init-parameter split doesn't allow.
  String _storedFieldDecl(GLField f, bool immutable) {
    final type = serializeType(f.type);
    final keyword = immutable ? 'let' : 'var';
    final deprecation = serializeFieldDeprecation(f);
    final name = f.codeName;
    return '${deprecation}public $keyword $name: $type';
  }

  // ── Type definition ─────────────────────────────────────────────────────────

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      return _serializeInterface(def);
    }
    return _serializeStruct(def);
  }

  /// A field named `id` of type `ID!` gets `Identifiable` for free — a
  /// small but high-value SwiftUI ergonomics win (`List(users) { ... }`
  /// works with no boilerplate), since `Identifiable` needs nothing beyond
  /// the `id` property already being generated.
  bool _isIdentifiable(GLTypeDefinition def) => def.getSerializableFields(grammar.mode).any(
      (f) => f.name.token == 'id' && !f.type.nullable && f.type.token == 'ID');

  String _serializeStruct(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);

    // Protocol conformance is structural in Swift — no `override` keyword
    // needed on a stored property that satisfies a protocol requirement,
    // unlike Kotlin's `override val`.
    final storedFields = fields.map((f) => _storedFieldDecl(f, immutableTypeFields)).toList();
    final initParams = fields.map(_initParam).toList();
    final initAssignments = fields.map((f) {
      final name = f.codeName;
      return 'self.$name = $name';
    }).toList();

    final extraBody = <String>[];
    if (!shouldSkipJsonMethods(def)) {
      extraBody.add('public ${_generateToJson(fields, def)}');
      extraBody.add('public static ${_generateFromJson(fields, def.codeName, def)}');
    }

    // Deduplicate by name to avoid "redundant conformance" compile errors.
    final ifaces = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet().toList();
    final conformances = [
      'Sendable',
      if (_isIdentifiable(def)) 'Identifiable',
      ...ifaces,
    ];

    return codeGenUtils.structDecl(
      name: def.codeName,
      fields: storedFields,
      initDecl: codeGenUtils.initDecl(params: initParams, assignments: initAssignments),
      extraBody: extraBody,
      conformances: conformances,
    );
  }

  String _serializeInterface(GLInterfaceDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final skipJson = shouldSkipJsonMethods(def);
    final isInternal = def.hasDirective(glInternal);

    final requirements = [
      ...fields.map((f) => 'var ${f.codeName}: ${serializeType(f.type)} { get }'),
      if (!skipJson && !isInternal) 'func toJson() -> [String: Any?]',
    ];

    final superIfaces = def.interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList();
    final protocol = codeGenUtils.protocolDecl(
      name: def.codeName,
      requirements: requirements,
      conformances: ['Sendable', ...superIfaces],
    );

    final subTypes = def.getSerializableImplementations(mode);
    if (skipJson || subTypes.isEmpty) return protocol;

    return '$protocol\n\n${_dispatchFactory(def.codeName, subTypes)}';
  }

  /// `<Interface>Json.fromJson(_:)` — the static `__typename`-dispatch
  /// factory a `protocol` can't host itself (dispatch on "which concrete
  /// type does this JSON represent" needs the untyped map, before any
  /// concrete conforming type is known — not expressible as a protocol
  /// requirement). Mirrors `KotlinSerializer._serializeFromJsonForInterface`'s
  /// `when`-based dispatch.
  String _dispatchFactory(String token, Set<GLTypeDefinition> subTypes) {
    final cases = subTypes.map((st) {
      final typeName = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      return SwiftCaseBranch(caseValue: '"$typeName"', statement: 'return ${st.codeName}.fromJson(map)');
    }).toList();
    final dispatch = codeGenUtils.switchStatement(
      expression: 'map["__typename"] as? String',
      cases: cases,
      defaultStatements: ['fatalError("Unknown $token __typename: " + (map["__typename"] as? String ?? "nil"))'],
    );
    final fromJson = 'public static ${codeGenUtils.method(
      returnType: 'any $token',
      methodName: 'fromJson',
      arguments: ['_ map: [String: Any?]'],
      statements: [dispatch],
    )}';
    return codeGenUtils.enumNamespace(name: '${token}Json', body: [fromJson]);
  }

  // ── toJson ──────────────────────────────────────────────────────────────────

  String _generateToJson(List<GLField> fields, GLToken context) {
    final typeName = context is GLTypeDefinition ? context.jsonTypeName : null;
    final entries = [
      if (typeName != null) '"__typename": "$typeName"',
      ...fields.map((f) => '"${f.name}": ${_fieldToJsonExpr(f.type, f.codeName, 0)}'),
    ].join(',\n').ident();
    return codeGenUtils.method(
      returnType: '[String: Any?]',
      methodName: 'toJson',
      statements: ['return [\n$entries,\n]'],
    );
  }

  String _fieldToJsonExpr(GLType type, String variable, int depth) {
    if (type is GLListType) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _fieldToJsonExpr(inner, varName, depth + 1);
      if (varName == innerExpr) return variable;
      return SwiftCodeGenUtils.mapCall(
          receiver: variable, param: varName, body: innerExpr, chainThroughOptional: type.nullable);
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return SwiftCodeGenUtils.safeCall(variable, 'toJson()', type.nullable);
    }
    return variable;
  }

  // ── fromJson ────────────────────────────────────────────────────────────────

  String _generateFromJson(List<GLField> fields, String token, GLToken context) {
    final args = fields
        .map((f) => '${f.codeName}: ${_fromJsonExpr(f.type, 'map', 0, field: f)}')
        .join(',\n')
        .ident();
    return codeGenUtils.createMethod(
      returnType: token,
      methodName: 'fromJson',
      arguments: ['_ map: [String: Any?]'],
      statements: ['return $token(\n$args\n)'],
    );
  }

  String _fromJsonExpr(GLType type, String mapVar, int depth, {required GLField field}) {
    final key = depth == 0 ? '["${field.name}"]' : '';
    final access = '$mapVar$key';

    if (type is GLListType) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _fromJsonExpr(inner, varName, depth + 1, field: field);
      final castedList = type.nullable ? '($access as? [Any?])' : '($access as! [Any?])';
      if (varName == innerExpr) return castedList;
      return SwiftCodeGenUtils.mapCall(
          receiver: castedList, param: varName, body: innerExpr, chainThroughOptional: type.nullable);
    }

    final wireToken = type.token;
    if (grammar.isNonProjectableType(wireToken) && !grammar.isEnum(wireToken) && !grammar.isInput(wireToken)) {
      final mappedToken = getTypeNameFromGQExternal(wireToken) ?? wireToken;
      return type.nullable ? '$access as? $mappedToken' : '$access as! $mappedToken';
    }
    final codeName = resolveCodeName(wireToken);
    if (grammar.isEnum(wireToken)) {
      if (type.nullable) {
        return SwiftCodeGenUtils.mapCall(receiver: '($access as? String)', body: '$codeName.fromJson(\$0)');
      }
      return '$codeName.fromJson($access as! String)';
    }
    // Projectable type, input, or interface/union. Interfaces don't carry
    // their own `fromJson` (a protocol can't declare "construct one of my
    // conformers" as a static requirement) — dispatch instead goes through
    // the paired `<Interface>Json.fromJson` namespace `_serializeInterface`
    // generates alongside the protocol (see `_dispatchFactory`).
    final isInterface = grammar.interfaces.containsKey(wireToken) || grammar.projectedInterfaces.containsKey(wireToken);
    final fromJsonTarget = isInterface ? '${codeName}Json' : codeName;
    if (type.nullable) {
      return SwiftCodeGenUtils.mapCall(receiver: '($access as? [String: Any?])', body: '$fromJsonTarget.fromJson(\$0)');
    }
    return '$fromJsonTarget.fromJson($access as! [String: Any?])';
  }

  // ── @glMapsTo ────────────────────────────────────────────────────────────────

  /// `public func to<Target>(...) -> Target` — an instance method on the
  /// input struct. Unlike [generateFromMethod], this stays an *instance*
  /// method (called as `input.toUser()`), matching the plan's own example.
  @override
  String generateToMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${serializeType(f.targetField.type)}',
      ),
      ...plan.defaultParams.map(
        (f) => 'default${f.targetField.codeName.firstUp}: ${serializeType(f.targetField.type)}',
      ),
    ];

    final targetDef = grammar.types[targetType];
    final targetFields = targetDef?.getSerializableFields(grammar.mode) ?? [];
    final autoByTarget = {for (final f in plan.autoMapped) f.targetField.name.token: f};
    final defaultByTarget = {for (final f in plan.defaultParams) f.targetField.name.token: f};
    final requiredByTarget = {for (final f in plan.requiredParams) f.targetField.name.token: f};

    final args = <String>[];
    for (final tf in targetFields) {
      final key = tf.name.token;
      final name = tf.codeName;
      if (autoByTarget.containsKey(key)) {
        final f = autoByTarget[key]!;
        final getter = f.sourceField!.codeName;
        args.add('$name: ${_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0)}');
      } else if (defaultByTarget.containsKey(key)) {
        final f = defaultByTarget[key]!;
        final getter = f.sourceField!.codeName;
        // Nil-coalescing directly expresses "use the value if present,
        // otherwise the caller-supplied default" — no if/else needed the
        // way Kotlin's `if (x != null) x else default` spells it out.
        args.add('$name: $getter ?? default${f.targetField.codeName.firstUp}');
      } else if (requiredByTarget.containsKey(key)) {
        args.add('$name: $name');
      }
    }

    final argsStr = args.join(',\n').ident();
    return 'public ${codeGenUtils.method(
      returnType: targetType,
      methodName: 'to${targetType.firstUp}',
      arguments: params,
      statements: ['return $targetType(\n$argsStr\n)'],
    )}';
  }

  /// `public static func from<Target>(_ target: Target, ...) -> Self` — a
  /// static factory (called as `CreateUserInput.fromUser(user)`), mirroring
  /// how `fromJson` is static too. The first parameter is unlabeled (`_`),
  /// matching every other generated `fromXxx`-shaped factory.
  @override
  String generateFromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    // Unlike every other identifier in this file, `targetVar` isn't a
    // `codeName` — it's synthesized here from the target type name
    // (`Person` -> `person`), so it never passes through the
    // swiftReservedWords-driven codeName rename and needs its own guard
    // against colliding with a Swift keyword (e.g. a type named `Self`).
    final lowered = targetType.firstLow;
    final targetVar = swiftReservedWords.contains(lowered) ? '${lowered}_' : lowered;

    final promotedParams = plan.promoted.map(
      (f) => '${f.sourceField!.codeName}: ${serializeType(f.sourceField!.type)}',
    );
    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${f.codeName}: ${serializeType(f.type)}',
    );
    final nullableListDefaultParams = plan.nullableListDefaults.map(
      (f) => 'default${f.sourceField!.codeName.firstUp}: ${serializeType(f.sourceField!.type)}',
    );

    final autoBySource = {for (final f in plan.autoMapped) f.sourceField!.name.token: f};
    final nullableListBySource = {for (final f in plan.nullableListDefaults) f.sourceField!.name.token: f};
    final promotedNames = {for (final f in plan.promoted) f.sourceField!.name.token};
    final inputOnlyNames = {for (final f in plan.inputOnly) f.name.token};

    final fields = def.getSerializableFields(grammar.mode);
    final args = <String>[];
    for (final field in fields) {
      final key = field.name.token;
      final name = field.codeName;
      if (autoBySource.containsKey(key)) {
        final f = autoBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        args.add('$name: ${_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0)}');
      } else if (nullableListBySource.containsKey(key)) {
        final f = nullableListBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0);
        args.add('$name: $expr ?? default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(key) || inputOnlyNames.contains(key)) {
        args.add('$name: $name');
      }
    }

    final allParams = [
      '_ $targetVar: $targetType',
      ...nullableListDefaultParams,
      ...promotedParams,
      ...inputOnlyParams,
    ];

    final argsStr = args.join(',\n').ident();
    return 'public static ${codeGenUtils.method(
      returnType: def.codeName,
      methodName: 'from${targetType.firstUp}',
      arguments: allParams,
      statements: ['return ${def.codeName}(\n$argsStr\n)'],
    )}';
  }

  /// Source (input) → target (type) conversion expression for one field
  /// during `toXxx()`. List nullability uses [SwiftCodeGenUtils.mapCall]'s
  /// `chainThroughOptional` (see its doc — iterating a nullable list's
  /// elements needs `?.map`, not `Optional.map`). The nested-mapped-input
  /// case (`variable.toPeriod()` / `variable?.toPeriod()`) is a plain method
  /// call, not `.map` at all, so it has no such ambiguity — `.toPeriod()` is
  /// not a `Sequence` member, so optional chaining is unambiguous here.
  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1);
      return SwiftCodeGenUtils.mapCall(
          receiver: variable, param: varName, body: inner, chainThroughOptional: sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      final targetCodeName = resolveCodeName(targetType.token);
      return SwiftCodeGenUtils.safeCall(variable, 'to${targetCodeName.firstUp}()', sourceType.nullable);
    }
    return variable;
  }

  /// Target (type) → source (input) reverse-conversion expression during
  /// `fromXxx()`. The nested-mapped-input case calls a *static* factory
  /// (`PeriodInput.fromPeriod(value)`) rather than an instance method, so —
  /// same reasoning as the enum/projectable branches of [_fromJsonExpr] —
  /// it needs `Optional.map` (plain `.map`, never `?.map`) to transform the
  /// whole optional value via a closure, not optional-chaining into some
  /// member of the wrapped value itself.
  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index) {
    if (targetType is GLListType) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1);
      return SwiftCodeGenUtils.mapCall(
          receiver: variable, param: varName, body: inner, chainThroughOptional: targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return SwiftCodeGenUtils.mapCall(
            receiver: variable, body: '$sourceCodeName.from${targetCodeName.firstUp}(\$0)');
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}($variable)';
    }
    return variable;
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'nil';
    if (value is int) {
      final swiftType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      if (swiftType == 'Double' || swiftType == 'Float') {
        return _serializeFloatingLiteral(value.toDouble(), swiftType);
      }
      return '$value';
    }
    if (value is double) {
      final swiftType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      return _serializeFloatingLiteral(value, swiftType);
    }
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return '[$items]';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key: ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '${resolveCodeName(type.token)}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      final content = value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
      return '"$content"';
    }
    return '"$value"';
  }

  // Swift has no bare NaN/Infinity literal — those come from the type's own
  // static members, same reasoning as KotlinSerializer's equivalent helper.
  String _serializeFloatingLiteral(double value, String swiftType) {
    if (value.isNaN) return '$swiftType.nan';
    if (value.isInfinite) return value.isNegative ? '-$swiftType.infinity' : '$swiftType.infinity';
    return '$value';
  }

  // ── File naming & imports ────────────────────────────────────────────────────

  @override
  String getFileNameFor(GLToken token) => '${resolveCodeName(token.token)}.swift';

  /// Always empty: unlike Kotlin/Java/TypeScript, referencing another
  /// generated type needs no import statement — every generated file lands
  /// in the same Swift module/target (the plan's "drop these files into an
  /// existing target" model), and same-module symbols are visible with no
  /// declaration at all. [serializeGlClass] still renders genuine free-form
  /// imports (e.g. `Foundation` for a custom scalar) added via
  /// [GLToken.addImport] — only cross-*generated-type* imports collapse to
  /// nothing.
  @override
  String serializeImportToken(GLToken token) => '';

  /// On Darwin, `Foundation` re-exports networking types (`URLSession`,
  /// `URLSessionWebSocketTask`, …) directly. On Linux, swift-corelibs-
  /// foundation splits those into a separate `FoundationNetworking` module
  /// that isn't implicitly pulled in — the generated `Default*Adapter`
  /// files use `URLSession` and fail to compile there without this. Every
  /// other `Foundation`-only file pays nothing for the extra `#if`.
  @override
  String serializeImport(String import) {
    if (import == 'Foundation') {
      return 'import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif';
    }
    return 'import $import';
  }

  @override
  String serializeGlClass(GLClassModel theClass, {bool withImports = true}) {
    if (!withImports || (theClass.importDepencies.isEmpty && theClass.imports.isEmpty)) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies
        .map(serializeImportToken)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports = theClass.imports.map(serializeImport).where((l) => l.isNotEmpty).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports);
  }
}
