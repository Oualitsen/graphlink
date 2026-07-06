import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/kotlin_imports.dart';

const _mapType = 'Map<String, Any?>';
const _anyListType = 'List<*>';

String _listOf(String inner) => 'List<$inner>';

const _kotlinNumberCasts = <String, String>{
  'Int': 'toInt()',
  'Long': 'toLong()',
  'Double': 'toDouble()',
  'Float': 'toFloat()',
};

const _kotlinNumbers = {'Int', 'Long', 'Double', 'Float'};

class KotlinSerializer extends GLSerializer {
  final bool inputsAsDataClass;
  final bool typesAsDataClass;
  final codeGenUtils = KotlinCodeGenUtils();

  @override
  Map<String, String> get defaultTypeMap => const {
        'ID': 'String',
        'String': 'String',
        'Float': 'Double',
        'Int': 'Int',
        'Boolean': 'Boolean',
        'Long': 'Long',
        'Null': 'null',
        'gqlMapStrObj': 'Map<String, Any?>',
        'dynamicValue': 'Any',
        'void': 'Unit',
      };

  KotlinSerializer(
    super.grammar, {
    this.inputsAsDataClass = true,
    this.typesAsDataClass = true,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  });

  static String _keyword(bool immutable) => immutable ? 'val' : 'var';

  // ── Type serialization ──────────────────────────────────────────────────────

  @override
  String serializeType(GLType def) {
    if (def is GLVoidType) {
      return 'Unit';
    }
    String type;
    if (def is GLMapType) {
      // kotlin.collections.Map is part of Kotlin's implicit default imports
      // (same as List/Set) — no addImport call needed, unlike Java's java.util.Map.
      type = 'Map<${serializeType(def.keyType)}, ${serializeType(def.valueType)}>';
    } else if (def is GLListType) {
      final inner = serializeType(def.inlineType);
      type = _listOf(inner);
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

  // ── Field serialization ─────────────────────────────────────────────────────

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField,
      {bool isOverride = false}) {
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives);
    final type = serializeType(def.type);
    final keyword = _keyword(immutable);
    final nullable = def.type.nullable || forceNullable;
    final deprecation = serializeFieldDeprecation(def);
    final line = nullable
        ? '$keyword ${def.codeName}: $type = null'
        : '$keyword ${def.codeName}: $type';
    return '$deprecation$line';
  }

  // ── Enum ────────────────────────────────────────────────────────────────────

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final values = def.values.map(doSerializeEnumValue).toList();
    final body = <String>[];

    final whenToJson = codeGenUtils.switchStatement(
      expression: 'this',
      cases: def.values.map((v) => KotlinWhenBranch(
        caseValue: v.codeName,
        statement: '"${v.value.token}"',
      )).toList(),
    );
    final whenFromJson = codeGenUtils.switchStatement(
      expression: 'value',
      cases: [
        ...def.values.map((v) => KotlinWhenBranch(
          caseValue: '"${v.value.token}"',
          statement: '${def.codeName}.${v.codeName}',
        )),
        KotlinWhenBranch(
          caseValue: 'else',
          statement: 'throw IllegalArgumentException("Invalid ${def.codeName}: \$value")',
        ),
      ],
    );
    body.add('fun toJson(): String = $whenToJson');
    body.add('');
    body.add(codeGenUtils.companionObject([
      'fun fromJson(value: String): ${def.codeName} = $whenFromJson',
    ]));

    return codeGenUtils.enumClass(name: def.codeName, values: values, body: body.isEmpty ? null : body);
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    final deprecation = serializeEnumValueDeprecation(value);
    if (deprecation.isEmpty) return value.codeName;
    return '$deprecation ${value.codeName}';
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final escaped = reason.escapeForStringLiteral().replaceAll('\r', '').replaceAll('\n', r'\n');
    return '@Deprecated("$escaped")\n';
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final escaped = reason.escapeForStringLiteral().replaceAll('\r', '').replaceAll('\n', r'\n');
    return '@Deprecated("$escaped")';
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final params = fields.map((f) => _inputParam(f)).toList();

    final instanceMethods = <String>[];
    final companionMethods = <String>[];

    instanceMethods.add(_generateToJson(fields, def));
    companionMethods.add(_generateFromJson(fields, def.codeName, def));

    // @glMapsTo instance methods (toXxx) and companion methods (fromXxx)
    final toMethods = _generateToMappingMethods(def);
    final fromMethods = _generateFromMappingMethods(def);
    instanceMethods.addAll(toMethods);
    companionMethods.addAll(fromMethods);

    if (!inputsAsDataClass) {
      instanceMethods.addAll(_generateEqualsHashCode(def.codeName, fields, def));
    }

    final body = <String>[
      if (instanceMethods.isNotEmpty) ...[...instanceMethods],
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    if (inputsAsDataClass) {
      return codeGenUtils.dataClass(name: def.codeName, params: params, body: body.isEmpty ? null : body);
    }
    return codeGenUtils.openClass(name: def.codeName, params: params, body: body.isEmpty ? null : body);
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) {
      // A GraphQL Float default without a decimal point (e.g. `min: Float = 0`)
      // parses as a Dart int, but Kotlin's Double/Float types don't accept an
      // Int literal in a default-value position — emit a floating literal.
      final kotlinType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      if (kotlinType == 'Double' || kotlinType == 'Float') {
        return _serializeFloatingLiteral(value.toDouble(), kotlinType);
      }
      return '$value';
    }
    if (value is double) {
      final kotlinType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      return _serializeFloatingLiteral(value, kotlinType);
    }
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return 'listOf($items)';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final field = inputDef?.fields.firstWhere((f) => f.name.token == e.key);
        final fieldType = field?.type ?? type;
        final key = field?.codeName ?? e.key;
        return '$key = ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '${resolveCodeName(type.token)}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${resolveCodeName(type.token)}.${grammar.enumConstantName(type.token, value)}';
      }
      final content = value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
      return '"$content"';
    }
    return '"$value"';
  }

  // Dart's double.toString() can emit "NaN"/"Infinity"/"-Infinity", none of
  // which are valid Kotlin literals — those need the Double/Float companion
  // constants instead. A Kotlin Float literal also needs an explicit `f`
  // suffix, since a bare decimal literal defaults to Double.
  String _serializeFloatingLiteral(double value, String kotlinType) {
    final isFloat = kotlinType == 'Float';
    if (value.isNaN) return isFloat ? 'Float.NaN' : 'Double.NaN';
    if (value.isInfinite) {
      final sign = value.isNegative ? 'NEGATIVE' : 'POSITIVE';
      return isFloat ? 'Float.${sign}_INFINITY' : 'Double.${sign}_INFINITY';
    }
    return isFloat ? '${value}f' : '$value';
  }

  String _inputParam(GLField f) {
    final type = serializeType(f.type);
    final keyword = _keyword(inputsAsDataClass);
    final deprecation = serializeFieldDeprecation(f);
    if (f.initialValue != null) {
      return '${deprecation}$keyword ${f.codeName}: $type = ${serializeDefaultLiteral(f.type, f.initialValue)}';
    }
    if (f.type.nullable) {
      return '${deprecation}$keyword ${f.codeName}: $type = null';
    }
    return '${deprecation}$keyword ${f.codeName}: $type';
  }

  // ── Type definition ─────────────────────────────────────────────────────────

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      return serializeInterface(def);
    }
    return _serializeClass(def);
  }

  String _serializeClass(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);

    final params = fields.map((f) {
      final forceNullable = f.hasInculeOrSkipDiretives;
      final type = serializeType(f.type);
      final keyword = _keyword(typesAsDataClass);
      final overrides = def.isOverride(f);
      final prefix = overrides ? 'override $keyword' : keyword;
      final deprecation = serializeFieldDeprecation(f);
      if (f.type.nullable || forceNullable) {
        return '${deprecation}$prefix ${f.codeName}: $type = null';
      }
      return '${deprecation}$prefix ${f.codeName}: $type';
    }).toList();

    final instanceMethods = <String>[];
    final companionMethods = <String>[];

    final implementsNonInternalInterface = def.interfaces
        .any((i) => !i.hasDirective(glInternal));

    final toJsonPrefix = implementsNonInternalInterface ? 'override ' : '';
    instanceMethods.add('${toJsonPrefix}${_generateToJson(fields, def)}');
    companionMethods.add(_generateFromJson(fields, def.codeName, def));

    if (!typesAsDataClass) {
      instanceMethods.addAll(_generateEqualsHashCode(def.codeName, fields, def));
    }

    final body = <String>[
      if (instanceMethods.isNotEmpty) ...[...instanceMethods],
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    // Deduplicate by name to avoid "A supertype appears twice" compile errors.
    final ifaces = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet().toList();

    if (typesAsDataClass) {
      return codeGenUtils.dataClass(
          name: def.codeName, params: params, body: body.isEmpty ? null : body, interfaces: ifaces.isEmpty ? null : ifaces);
    }
    return codeGenUtils.openClass(
        name: def.codeName, params: params, body: body.isEmpty ? null : body, interfaces: ifaces.isEmpty ? null : ifaces);
  }

  String serializeInterface(GLInterfaceDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final fieldDecls = fields.map((f) {
      final type = serializeType(f.type);
      final prefix = def.isOverride(f) ? 'override val' : 'val';
      return '$prefix ${f.codeName}: $type';
    }).toList();

    final companionMethods = <String>[];
    final subTypes = def.getSerializableImplementations(mode);
    if (subTypes.isNotEmpty) {
      companionMethods.add(_serializeFromJsonForInterface(def.codeName, subTypes));
    }

    final isInternal = def.hasDirective(glInternal);
    final toJsonOverridesSuperInterface = def.interfaces.any((iname) {
      final iface = grammar.interfaces[iname.tokenInfo.token];
      return iface != null && !iface.hasDirective(glInternal);
    });
    final toJsonPrefix = toJsonOverridesSuperInterface ? 'override fun' : 'fun';

    final body = <String>[
      ...fieldDecls.map((d) => d),
      if (!isInternal) '$toJsonPrefix toJson(): $_mapType',
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    final superIfaces = def.interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList();
    return codeGenUtils.kotlinInterface(
        name: def.codeName, body: body, superInterfaces: superIfaces.isEmpty ? null : superIfaces);
  }

  String _serializeFromJsonForInterface(String token, Set<GLTypeDefinition> subTypes) {
    final cases = [
      ...subTypes.map((st) {
        final typeName = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
        final current = st.codeName;
        return KotlinWhenBranch(caseValue: '"$typeName"', statement: '$current.fromJson(map)');
      }),
      KotlinWhenBranch(
        caseValue: 'else',
        statement: 'throw IllegalArgumentException("Unknown __typename: " + map["__typename"])',
      ),
    ];
    final whenExpr = codeGenUtils.switchStatement(
      expression: 'map["__typename"] as String',
      cases: cases,
    );
    return 'fun fromJson(map: $_mapType): $token = $whenExpr';
  }

  // ── toJson ──────────────────────────────────────────────────────────────────

  String _generateToJson(List<GLField> fields, GLToken context) {
    final entries = fields.map((f) {
      return '"${f.name}" to ${_fieldToJsonExpr(f, f.type, f.codeName, 0)}';
    }).join(',\n        ');
    return 'fun toJson(): $_mapType = mapOf(\n        $entries,\n    )';
  }

  String _fieldToJsonExpr(GLField field, GLType type, String variable, int depth) {
    if (type is GLListType) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _fieldToJsonExpr(field, inner, varName, depth + 1);
      if (varName == innerExpr) return variable;
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: innerExpr, nullable: type.nullable);
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return KotlinCodeGenUtils.safeCall(variable, 'toJson()', type.nullable);
    }
    return variable;
  }

  // ── fromJson ─────────────────────────────────────────────────────────────────

  String _generateFromJson(List<GLField> fields, String token, GLToken context) {
    final assignments = fields.map((f) {
      return '    ${f.codeName} = ${_fromJsonExpr(f, f.type, 'map', 0, context)},';
    }).join('\n');
    return '@Suppress("UNCHECKED_CAST")\nfun fromJson(map: $_mapType): $token = $token(\n$assignments\n)';
  }

  String _fromJsonExpr(GLField field, GLType type, String mapVar, int depth, GLToken context) {
    final key = depth == 0 ? '["${field.name}"]' : '';
    final access = '$mapVar$key';

    if (type is GLListType) {
      final inner = type.inlineType;
      final varName = 'e$depth';
      final innerExpr = _fromJsonExpr(field, inner, varName, depth + 1, context);
      final castedList = type.nullable ? '($access as? $_anyListType)' : '($access as $_anyListType)';
      if (varName == innerExpr) return castedList;
      return KotlinCodeGenUtils.mapCall(receiver: castedList, param: varName, body: innerExpr, nullable: type.nullable);
    }

    final wireToken = type.token;
    if (grammar.isNonProjectableType(wireToken) && !grammar.isEnum(wireToken) && !grammar.isInput(wireToken)) {
      final mappedToken = getTypeNameFromGQExternal(wireToken) ?? wireToken;
      return _scalarCast(access, mappedToken, type.nullable, depth);
    }
    final codeName = resolveCodeName(wireToken);
    if (grammar.isEnum(wireToken)) {
      if (type.nullable) {
        return KotlinCodeGenUtils.letCall(receiver: '($access as? String)', body: '$codeName.fromJson(it)');
      }
      return '$codeName.fromJson($access as String)!!';
    }
    // projectable type or input
    if (type.nullable) {
      return KotlinCodeGenUtils.letCall(receiver: '($access as? Map<*, *>)', body: '$codeName.fromJson(it as $_mapType)');
    }
    return '$codeName.fromJson($access as $_mapType)';
  }

  String _scalarCast(String access, String token, bool nullable, int depth) {
    if (_kotlinNumbers.contains(token)) {
      final method = _kotlinNumberCasts[token]!;
      if (nullable) return '($access as? Number)?.$method';
      return '($access as Number).$method';
    }
    if (nullable) return '$access as? $token';
    return '$access as $token';
  }

  // ── equals / hashCode (open class only) ─────────────────────────────────────

  List<String> _generateEqualsHashCode(String token, List<GLField> fields, GLToken context) {
    if (fields.isEmpty) return [];
    context.addImport(KotlinImports.objects);

    final conditions = fields.map((f) => '${f.codeName} == other.${f.codeName}').join(' && ');
    final hashArgs = fields.map((f) => f.codeName).join(', ');

    final equalsMethod = codeGenUtils.method(
      returnType: 'Boolean',
      methodName: 'equals',
      arguments: ['other: Any?'],
      statements: [
        'if (other !is $token) return false',
        'return $conditions',
      ],
    );

    return [
      'override $equalsMethod',
      'override fun hashCode(): Int = Objects.hash($hashArgs)',
    ];
  }

  // ── @glMapsTo ────────────────────────────────────────────────────────────────

  List<String> _generateToMappingMethods(GLInputDefinition def) {
    final plan = grammar.resolveToMappingPlan(def, mode);
    if (plan == null || !plan.derivesAnythingFromSource) return [];
    final targetWireName = def.mapsToType!;
    final targetName = grammar.types[targetWireName]?.codeName ?? targetWireName;
    return [generateToMethod(def, targetName, plan)];
  }

  List<String> _generateFromMappingMethods(GLInputDefinition def) {
    final fromPlan = grammar.resolveFromMappingPlan(def, mode);
    if (fromPlan == null || !fromPlan.derivesAnythingFromTarget) return [];
    final targetWireName = def.mapsToType!;
    final targetName = grammar.types[targetWireName]?.codeName ?? targetWireName;
    return [generateFromMethod(def, targetName, fromPlan)];
  }

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
        args.add('$name = ${_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def)}');
      } else if (defaultByTarget.containsKey(key)) {
        final f = defaultByTarget[key]!;
        final getter = f.sourceField!.codeName;
        args.add('$name = if ($getter != null) $getter else default${f.targetField.codeName.firstUp}');
      } else if (requiredByTarget.containsKey(key)) {
        args.add('$name = $name');
      }
    }

    final argsStr = args.map((a) => '    $a,').join('\n');
    final paramsStr = params.isEmpty ? '' : params.join(', ');
    return 'fun to${targetType.firstUp}($paramsStr): $targetType = $targetType(\n$argsStr\n)';
  }

  @override
  String generateFromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;

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
        args.add('$name = ${_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def)}');
      } else if (nullableListBySource.containsKey(key)) {
        final f = nullableListBySource[key]!;
        final sourceExpr = '$targetVar.${f.targetField.codeName}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        args.add('$name = $expr ?: default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(key) || inputOnlyNames.contains(key)) {
        args.add('$name = $name');
      }
    }

    final allParams = [
      '$targetVar: $targetType',
      ...nullableListDefaultParams,
      ...promotedParams,
      ...inputOnlyParams,
    ].join(', ');

    final argsStr = args.map((a) => '    $a,').join('\n');
    return 'fun from${targetType.firstUp}($allParams): ${def.codeName} = ${def.codeName}(\n$argsStr\n)';
  }

  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType is GLListType) {
      if (sourceType.firstType.token == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      if (sourceType.nullable) return '$variable?.to${resolveCodeName(targetType.token).firstUp}()';
      return '$variable.to${resolveCodeName(targetType.token).firstUp}()';
    }
    return variable;
  }

  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index, GLToken context) {
    if (targetType is GLListType) {
      if (sourceElemToken == targetType.firstType.token) return variable;
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1, context);
      return KotlinCodeGenUtils.mapCall(receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      if (targetType.nullable) {
        return KotlinCodeGenUtils.letCall(receiver: variable, body: '$sourceCodeName.from${targetCodeName.firstUp}(it)');
      }
      return '$sourceCodeName.from${targetCodeName.firstUp}($variable)';
    }
    return variable;
  }

  // ── File naming & imports ────────────────────────────────────────────────────

  @override
  String getFileNameFor(GLToken token) => '${resolveCodeName(token.token)}.kt';

  @override
  String serializeImportToken(GLToken token) {
    String? subpkg;
    if (grammar.enums.containsKey(token.token)) {
      subpkg = 'enums';
    } else if (grammar.interfaces.containsKey(token.token) ||
        grammar.projectedInterfaces.containsKey(token.token)) {
      subpkg = 'interfaces';
    } else if (grammar.types.containsKey(token.token) ||
        grammar.projectedTypes.containsKey(token.token)) {
      subpkg = 'types';
    } else if (grammar.inputs.containsKey(token.token)) {
      subpkg = 'inputs';
    } else if (grammar.services.containsKey(token.token)) {
      subpkg = 'services';
    } else if (grammar.controllers.containsKey(token.token)) {
      subpkg = 'controllers';
    }
    if (subpkg == null) return '';
    return 'import $importPrefix.$subpkg.${resolveCodeName(token.token)}';
  }

  @override
  String serializeImport(String import) {
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
