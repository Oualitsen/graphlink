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
import 'package:graphlink/src/model/gl_token_with_fields.dart';
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
  final bool generateJsonMethods;

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
      };

  KotlinSerializer(
    super.grammar, {
    this.inputsAsDataClass = true,
    this.typesAsDataClass = true,
    this.generateJsonMethods = false,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  });

  static String _keyword(bool immutable) => immutable ? 'val' : 'var';

  // ── Type serialization ──────────────────────────────────────────────────────

  @override
  String serializeType(GLType def, bool forceNullable) {
    if (def is GLListType) {
      final inner = serializeType(def.inlineType, false);
      final type = _listOf(inner);
      return (def.nullable || forceNullable) ? '$type?' : type;
    }
    final token = def.token;
    final mapped = getTypeNameFromGQExternal(token) ?? token;
    return (def.nullable || forceNullable) ? '$mapped?' : mapped;
  }

  // ── Field serialization ─────────────────────────────────────────────────────

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField) {
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives);
    final type = serializeType(def.type, forceNullable);
    final keyword = _keyword(immutable);
    final nullable = def.type.nullable || forceNullable;
    if (nullable) {
      return '$keyword ${def.codeName}: $type = null';
    }
    return '$keyword ${def.codeName}: $type';
  }

  // ── Enum ────────────────────────────────────────────────────────────────────

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final values = def.values.map(doSerializeEnumValue).toList();
    final body = <String>[];

    // When a constant was renamed for keyword safety, `name` / `valueOf` would
    // expose the sanitized identifier on the wire. Emit an explicit mapping so
    // the wire string stays the original GraphQL value.
    final sanitized = def.values.any((v) => v.codeName != v.value.token);

    if (generateJsonMethods) {
      if (sanitized) {
        final toCases =
            def.values.map((v) => '${v.codeName} -> "${v.value.token}"');
        final fromCases =
            def.values.map((v) => '"${v.value.token}" -> ${v.codeName}');
        body.add('fun toJson(): String = when (this) {');
        body.add(toCases.map((c) => '    $c').join('\n'));
        body.add('}');
        body.add('');
        body.add(codeGenUtils.companionObject([
          'fun fromJson(value: String?): ${def.token}? = when (value) {',
          fromCases.map((c) => '    $c').join('\n'),
          '    else -> null',
          '}',
        ]));
      } else {
        body.add(codeGenUtils.companionObject([
          'fun fromJson(value: String?): ${def.token}? = value?.let { valueOf(it) }',
        ]));
        body.add('');
        body.add('fun toJson(): String = name');
      }
    }

    return codeGenUtils.enumClass(name: def.token, values: values, body: body.isEmpty ? null : body);
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) => value.codeName;

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final params = fields.map((f) => _inputParam(f)).toList();

    final instanceMethods = <String>[];
    final companionMethods = <String>[];

    if (generateJsonMethods) {
      instanceMethods.add(_generateToJson(fields, def));
      companionMethods.add(_generateFromJson(fields, def.token, def));
    }

    // @glMapsTo instance methods (toXxx) and companion methods (fromXxx)
    final toMethods = _generateToMappingMethods(def);
    final fromMethods = _generateFromMappingMethods(def);
    instanceMethods.addAll(toMethods);
    companionMethods.addAll(fromMethods);

    if (!inputsAsDataClass) {
      instanceMethods.addAll(_generateEqualsHashCode(def.token, fields, def));
    }

    final body = <String>[
      if (instanceMethods.isNotEmpty) ...[...instanceMethods],
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    if (inputsAsDataClass) {
      return codeGenUtils.dataClass(name: def.token, params: params, body: body.isEmpty ? null : body);
    }
    return codeGenUtils.openClass(name: def.token, params: params, body: body.isEmpty ? null : body);
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) return '$value';
    if (value is double) return '$value';
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return 'listOf($items)';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token];
      final args = value.entries.map((e) {
        final fieldType = inputDef?.fields.firstWhere((f) => f.name.token == e.key).type ?? type;
        return '${e.key} = ${serializeDefaultLiteral(fieldType, e.value)}';
      }).join(', ');
      return '${type.token}($args)';
    }
    if (value is String) {
      if (grammar.enums.containsKey(type.token)) {
        return '${type.token}.${grammar.enumConstantName(type.token, value)}';
      }
      final content = value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;
      return '"$content"';
    }
    return '"$value"';
  }

  String _inputParam(GLField f) {
    final type = serializeType(f.type, false);
    final keyword = _keyword(inputsAsDataClass);
    if (f.initialValue != null) {
      return '$keyword ${f.codeName}: $type = ${serializeDefaultLiteral(f.type, f.initialValue)}';
    }
    if (f.type.nullable) {
      return '$keyword ${f.codeName}: $type = null';
    }
    return '$keyword ${f.codeName}: $type';
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
      final type = serializeType(f.type, forceNullable);
      final keyword = _keyword(typesAsDataClass);
      final overrides = _fieldImplementsInterface(f, def);
      final prefix = overrides ? 'override $keyword' : keyword;
      if (f.type.nullable || forceNullable) {
        return '$prefix ${f.codeName}: $type = null';
      }
      return '$prefix ${f.codeName}: $type';
    }).toList();

    final instanceMethods = <String>[];
    final companionMethods = <String>[];

    final implementsNonInternalInterface = def.interfaces
        .any((i) => !i.hasDirective(glInternal));

    if (generateJsonMethods) {
      final toJsonPrefix = implementsNonInternalInterface ? 'override ' : '';
      instanceMethods.add('${toJsonPrefix}${_generateToJson(fields, def)}');
      companionMethods.add(_generateFromJson(fields, def.token, def));
    }

    if (!typesAsDataClass) {
      instanceMethods.addAll(_generateEqualsHashCode(def.token, fields, def));
    }

    final body = <String>[
      if (instanceMethods.isNotEmpty) ...[...instanceMethods],
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    // Deduplicate by name to avoid "A supertype appears twice" compile errors.
    final ifaces = def.interfaceNames.map((e) => e.token).toSet().toList();

    if (typesAsDataClass) {
      return codeGenUtils.dataClass(
          name: def.token, params: params, body: body.isEmpty ? null : body, interfaces: ifaces.isEmpty ? null : ifaces);
    }
    return codeGenUtils.openClass(
        name: def.token, params: params, body: body.isEmpty ? null : body, interfaces: ifaces.isEmpty ? null : ifaces);
  }

  bool _fieldImplementsInterface(GLField f, GLTypeDefinition def) {
    for (final iname in def.interfaceNames) {
      final iface = grammar.interfaces[iname.token];
      if (iface == null) continue;
      if (iface.fields.any((fi) => fi.name.token == f.name.token)) return true;
    }
    return false;
  }

  String serializeInterface(GLInterfaceDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);
    final fieldDecls = fields.map((f) {
      final forceNullable = f.hasInculeOrSkipDiretives;
      return 'val ${f.codeName}: ${serializeType(f.type, forceNullable)}';
    }).toList();

    final companionMethods = <String>[];
    if (generateJsonMethods) {
      final subTypes = def.getSerializableImplementations(mode);
      if (subTypes.isNotEmpty) {
        companionMethods.add(_serializeFromJsonForInterface(def.token, subTypes));
      }
    }

    final isInternal = def.hasDirective(glInternal);

    final body = <String>[
      ...fieldDecls.map((d) => d),
      if (!isInternal && generateJsonMethods) 'fun toJson(): $_mapType',
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    final superIfaces = def.interfaces.map((e) => e.tokenInfo.token).toList();
    return codeGenUtils.kotlinInterface(
        name: def.token, body: body, superInterfaces: superIfaces.isEmpty ? null : superIfaces);
  }

  String _serializeFromJsonForInterface(String token, Set<GLTypeDefinition> subTypes) {
    final cases = [
      ...subTypes.map((st) {
        final typeName = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
        final current = st.tokenInfo.token;
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
    return 'fun fromJson(map: $_mapType): $token = $token(\n$assignments\n)';
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

    final token = type.token;
    if (grammar.isNonProjectableType(token) && !grammar.isEnum(token) && !grammar.isInput(token)) {
      final mappedToken = getTypeNameFromGQExternal(token) ?? token;
      return _scalarCast(access, mappedToken, type.nullable, depth);
    }
    if (grammar.isEnum(token)) {
      if (type.nullable) {
        return KotlinCodeGenUtils.letCall(receiver: '($access as? String)', body: '$token.fromJson(it)');
      }
      return '$token.valueOf($access as String)';
    }
    // projectable type or input
    if (type.nullable) {
      return KotlinCodeGenUtils.letCall(receiver: '($access as? Map<*, *>)', body: '$token.fromJson(it as $_mapType)');
    }
    return '$token.fromJson($access as $_mapType)';
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
    final targetName = def.mapsToType!;
    return [generateToMethod(def, targetName, plan)];
  }

  List<String> _generateFromMappingMethods(GLInputDefinition def) {
    final fromPlan = grammar.resolveFromMappingPlan(def, mode);
    if (fromPlan == null || !fromPlan.derivesAnythingFromTarget) return [];
    final targetName = def.mapsToType!;
    return [generateFromMethod(def, targetName, fromPlan)];
  }

  @override
  String generateToMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    final params = [
      ...plan.requiredParams.map(
        (f) => '${f.targetField.codeName}: ${serializeType(f.targetField.type, false)}',
      ),
      ...plan.defaultParams.map(
        (f) => 'default${f.targetField.name.token.firstUp}: ${serializeType(f.targetField.type, false)}',
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
        args.add('$name = if ($getter != null) $getter else default${f.targetField.name.token.firstUp}');
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
      (f) => '${f.sourceField!.codeName}: ${serializeType(f.sourceField!.type, false)}',
    );
    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${f.codeName}: ${serializeType(f.type, false)}',
    );
    final nullableListDefaultParams = plan.nullableListDefaults.map(
      (f) => 'default${f.sourceField!.name.token.firstUp}: ${serializeType(f.sourceField!.type, false)}',
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
        args.add('$name = $expr ?: default${f.sourceField!.name.token.firstUp}');
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
    return 'fun from${targetType.firstUp}($allParams): ${def.token} = ${def.token}(\n$argsStr\n)';
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
      if (sourceType.nullable) return '$variable?.to${targetType.token.firstUp}()';
      return '$variable.to${targetType.token.firstUp}()';
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
      if (targetType.nullable) {
        return KotlinCodeGenUtils.letCall(receiver: variable, body: '$sourceElemToken.from${targetType.token.firstUp}(it)');
      }
      return '$sourceElemToken.from${targetType.token.firstUp}($variable)';
    }
    return variable;
  }

  // ── File naming & imports ────────────────────────────────────────────────────

  @override
  String getFileNameFor(GLToken token) => '${token.token}.kt';

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
    return 'import $importPrefix.$subpkg.${token.token}';
  }

  @override
  String serializeImport(String import) {
    // importList (_list) is a marker for List<T> — built-in in Kotlin, no import needed
    if (import == importList) return '';
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
