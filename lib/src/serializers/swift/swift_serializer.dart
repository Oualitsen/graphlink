import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_recursion_extension.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/swift_code_gen_utils.dart';
import 'package:graphlink/src/serializers/swift/swift_mapping_serializer.dart';

class SwiftSerializer extends GLSerializer with JsonExpressions {
  @override
  late final GLMappingSerializer mapping = SwiftMappingSerializer(this);

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

  String _deprecatedAttribute(String? reason) =>
      '@available(*, deprecated, message: ${stringLiteral(reason ?? 'No longer supported')})';

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final cases = def.allValues.map(doSerializeEnumValue).toList();
    final unknown = def.unknownValue;

    final toJson = 'public ${codeGenUtils.method(
      returnType: 'String',
      methodName: 'toJson',
      statements: ['return rawValue'],
    )}';
    final fromJson = 'public static ${codeGenUtils.createMethod(
      returnType: def.codeName,
      methodName: 'fromJson',
      arguments: ['_ value: String'],
      statements: [
        unknown != null
            ? 'return ${def.codeName}(rawValue: value) ?? .${unknown.codeName}'
            : 'return ${def.codeName}(rawValue: value)!',
      ],
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

    final storedFields = fields.map((f) => _storedFieldDecl(def, f, immutableTypeFields)).toList();
    final initParams = fields.map(_initParam).toList();
    final initAssignments = fields.map((f) => _initAssignment(def, f)).toList();

    final extraBody = [
      'public ${_generateToJson(fields, def)}',
      'public static ${_generateFromJson(fields, def.codeName, def)}',
      // @glMapsTo: toXxx()/fromXxx() slot into the same struct body flatly —
      // unlike Kotlin, Swift has no separate companion-object namespace to
      // route the static fromXxx() into, so both go straight into extraBody.
      ...generateMappingMethods(def),
    ];

    final decl = codeGenUtils.structDecl(
      name: def.codeName,
      fields: storedFields,
      initDecl: codeGenUtils.initDecl(params: initParams, assignments: initAssignments),
      extraBody: extraBody,
      conformances: const ['Sendable'],
    );
    return fields.any((f) => grammar.isRecursiveField(def, f)) ? '$decl\n\n$_indirectBox' : decl;
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
  String _storedFieldDecl(GLTokenWithFields owner, GLField f, bool immutable) {
    final type = serializeType(f.type);
    final keyword = immutable ? 'let' : 'var';
    final deprecation = serializeFieldDeprecation(f);
    final name = f.codeName;
    if (!grammar.isRecursiveField(owner, f)) return '${deprecation}public $keyword $name: $type';
    final nullable = f.type.nullable;
    final boxed = nullable ? 'GLIndirect<${type.substring(0, type.length - 1)}>?' : 'GLIndirect<$type>';
    final read = nullable ? '_$name?.value' : '_$name.value';
    final write = nullable ? 'newValue.map(GLIndirect.init)' : 'GLIndirect(newValue)';
    return [
      'private var _$name: $boxed',
      if (immutable)
        '${deprecation}public var $name: $type { $read }'
      else
        '${deprecation}public var $name: $type {\n   get { $read }\n   set { _$name = $write }\n}',
    ].join('\n').replaceFirst('private var _$name', immutable ? 'private let _$name' : 'private var _$name');
  }

  String _initAssignment(GLTokenWithFields owner, GLField f) {
    final name = f.codeName;
    if (!grammar.isRecursiveField(owner, f)) return 'self.$name = $name';
    return f.type.nullable ? 'self._$name = $name.map(GLIndirect.init)' : 'self._$name = GLIndirect($name)';
  }

  static const _indirectBox =
      'private final class GLIndirect<T>: @unchecked Sendable {\n   let value: T\n   init(_ value: T) { self.value = value }\n}';

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
    final storedFields = fields.map((f) => _storedFieldDecl(def, f, immutableTypeFields)).toList();
    final initParams = fields.map(_initParam).toList();
    final initAssignments = fields.map((f) => _initAssignment(def, f)).toList();

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

    final decl = codeGenUtils.structDecl(
      name: def.codeName,
      fields: storedFields,
      initDecl: codeGenUtils.initDecl(params: initParams, assignments: initAssignments),
      extraBody: extraBody,
      conformances: conformances,
    );
    return fields.any((f) => grammar.isRecursiveField(def, f)) ? '$decl\n\n$_indirectBox' : decl;
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

    if (def.syntheticImplementation != null) {
      return '$protocol\n\n${serializeSyntheticInterfaceFromJson(def)}';
    }
    return '$protocol\n\n${_dispatchFactory(def.codeName, subTypes, wireToken: def.token)}';
  }

  /// `<Interface>Json.fromJson(_:)` — the static `__typename`-dispatch
  /// factory a `protocol` can't host itself (dispatch on "which concrete
  /// type does this JSON represent" needs the untyped map, before any
  /// concrete conforming type is known — not expressible as a protocol
  /// requirement). Mirrors `KotlinSerializer._serializeFromJsonForInterface`'s
  /// `when`-based dispatch.
  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) {
    final fromJson = 'public static ${codeGenUtils.method(
      returnType: 'any ${interface.codeName}',
      methodName: 'fromJson',
      arguments: ['_ map: [String: Any?]'],
      statements: ['return ${interface.syntheticImplementation!.codeName}.fromJson(map)'],
    )}';
    return codeGenUtils.enumNamespace(name: '${interface.codeName}Json', body: [fromJson]);
  }

  String _dispatchFactory(String token, Set<GLTypeDefinition> subTypes, {String? wireToken}) {
    final discriminator = wireToken == null ? null : grammar.restDiscriminators[wireToken];
    final cases = subTypes.map((st) {
      final typeName = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      return SwiftCaseBranch(caseValue: '"$typeName"', statement: 'return ${st.codeName}.fromJson(map)');
    }).toList();
    final byTypename = codeGenUtils.switchStatement(
      expression: 'map["__typename"] as? String',
      cases: cases,
      defaultStatements: [
        discriminator == null
            ? 'fatalError("Unknown $token __typename: " + (map["__typename"] as? String ?? "nil"))'
            : 'break',
      ],
    );
    final dispatch = discriminator == null ? byTypename : _discriminated(token, subTypes, discriminator, byTypename);
    final fromJson = 'public static ${codeGenUtils.method(
      returnType: 'any $token',
      methodName: 'fromJson',
      arguments: ['_ map: [String: Any?]'],
      statements: [dispatch],
    )}';
    return codeGenUtils.enumNamespace(name: '${token}Json', body: [fromJson]);
  }

  String _discriminated(String token, Set<GLTypeDefinition> subTypes, GLRestDiscriminator discriminator, String byTypename) {
    String typeName(GLTypeDefinition t) => t.derivedFromType?.tokenInfo.token ?? t.tokenInfo.token;
    final byValue = codeGenUtils.switchStatement(
      expression: 'discriminator',
      cases: [
        for (final t in subTypes)
          SwiftCaseBranch(
              caseValue: '"${discriminator.valueByType[typeName(t)] ?? typeName(t)}"',
              statement: 'return ${t.codeName}.fromJson(map)'),
      ],
      defaultStatements: [
        'fatalError("Cannot decode $token: unknown or missing \\"${discriminator.field}\\" value (\\(discriminator ?? "nil"))")',
      ],
    );
    return [
      byTypename,
      'let discriminator = (map["${discriminator.field}"] ?? nil).map { String(describing: \$0) }',
      byValue,
    ].join('\n');
  }

  // ── toJson ──────────────────────────────────────────────────────────────────

  String _generateToJson(List<GLField> fields, GLToken context) {
    final typeName = context is GLTypeDefinition ? context.jsonTypeName : null;
    final entries = [
      if (typeName != null) '"__typename": "$typeName"',
      ...fields.map((f) => '"${f.name}": ${toJsonExpr(f.type, f.codeName)}'),
    ].join(',\n').ident();
    return codeGenUtils.method(
      returnType: '[String: Any?]',
      methodName: 'toJson',
      statements: ['return [\n$entries,\n]${context is GLInputDefinition && context.isOneOf ? '.filter { \$0.value != nil }' : ''}'],
    );
  }

  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) {
    // `map { $0 as Any? }` so the result is always `[Any?]` whatever the source element
    // type, matching the `as? [Any?]` cast of GraphLinkJson.normalize.
    if (element == body) return SwiftCodeGenUtils.safeCall(value, 'map { \$0 as Any? }', list.nullable);
    return SwiftCodeGenUtils.mapCall(receiver: value, param: element, body: body, chainThroughOptional: list.nullable);
  }

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) {
    final casted = list.nullable ? '($json as? [Any?])' : '($json as! [Any?])';
    if (element == body) return casted;
    return SwiftCodeGenUtils.mapCall(receiver: casted, param: element, body: body, chainThroughOptional: list.nullable);
  }

  @override
  String modelToJson(GLType type, String value) => SwiftCodeGenUtils.safeCall(value, 'toJson()', type.nullable);

  @override
  String enumFromJson(GLType type, String json) {
    final codeName = resolveCodeName(type.token);
    if (type.nullable) return SwiftCodeGenUtils.mapCall(receiver: '($json as? String)', body: '$codeName.fromJson(\$0)');
    return '$codeName.fromJson($json as! String)';
  }

  // Interfaces don't carry their own `fromJson` (a protocol can't declare "construct one of
  // my conformers" as a static requirement): dispatch goes through the paired
  // `<Interface>Json.fromJson` namespace `_serializeInterface` generates (see `_dispatchFactory`).
  @override
  String modelFromJson(GLType type, String json) {
    final codeName = resolveCodeName(type.token);
    final isInterface = grammar.interfaces.containsKey(type.token) || grammar.projectedInterfaces.containsKey(type.token);
    final target = isInterface ? '${codeName}Json' : codeName;
    if (type.nullable) {
      return SwiftCodeGenUtils.mapCall(receiver: '($json as? [String: Any?])', body: '$target.fromJson(\$0)');
    }
    return '$target.fromJson($json as! [String: Any?])';
  }

  @override
  String plainFromJson(GLType type, String json) {
    final mapped = getTypeNameFromGQExternal(type.token) ?? type.token;
    return type.nullable ? '$json as? $mapped' : '$json as! $mapped';
  }

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) {
    if (!nullable) return codec.decode(json);
    final present = '($json ?? nil).flatMap { \$0 is NSNull ? nil : \$0 }';
    return SwiftCodeGenUtils.mapCall(receiver: present, body: codec.decode('\$0'));
  }

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      nullable ? SwiftCodeGenUtils.mapCall(receiver: value, body: codec.encode('\$0')) : codec.encode(value);

  // ── fromJson ────────────────────────────────────────────────────────────────

  String _generateFromJson(List<GLField> fields, String token, GLToken context) {
    final args = fields
        .map((f) => '${f.codeName}: ${fromJsonExpr(f.type, 'map["${f.name}"]')}')
        .join(',\n')
        .ident();
    return codeGenUtils.createMethod(
      returnType: token,
      methodName: 'fromJson',
      arguments: ['_ map: [String: Any?]'],
      statements: ['return $token(\n$args\n)'],
    );
  }

  // ── @glMapsTo ────────────────────────────────────────────────────────────────

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
      return stringLiteral(decodeGraphqlString(value));
    }
    return '"$value"';
  }

  // Swift has no bare NaN/Infinity literal — those come from the type's own
  // static members, same reasoning as KotlinSerializer's equivalent helper.
  @override
  String stringLiteral(String decoded) =>
      '"${escapeStringBody(decoded, quote: '"', control: (unit) => '\\u{${unit.toRadixString(16)}}')}"';

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
  String serializeImports(GLToken token) {
    final imports = super.serializeImports(token);
    final usesCodec = token is GLTokenWithFields && token.fields.any((f) => fromJsonCodecOf(f.type) != null);
    if (!usesCodec || imports.contains('Foundation')) return imports;
    return '${serializeImport('Foundation')}\n$imports';
  }

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
