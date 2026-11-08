import 'package:graphlink/src/serializers/gl_mapping_serializer.dart';
import 'package:graphlink/src/model/scalar_codec.dart';
import 'package:graphlink/src/graphql_string_literal.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_maps_to_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/json_expressions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_imports.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_mapping_serializer.dart';

const _mapType = 'Map<String, Any?>';
const _anyListType = 'List<*>';

String _listOf(String inner) => 'List<$inner>';

const _kotlinExactNumberCasts = <String, String>{
  'Int': 'intValueExact()',
  'Long': 'longValueExact()',
};

const _kotlinNumberCasts = <String, String>{
  'Int': 'toInt()',
  'Long': 'toLong()',
  'Double': 'toDouble()',
  'Float': 'toFloat()',
};

const _kotlinNumbers = {'Int', 'Long', 'Double', 'Float'};

class KotlinSerializer extends GLSerializer with JsonExpressions {
  @override
  late final GLMappingSerializer mapping = KotlinMappingSerializer(this);

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
    final type = serializeType(def.type);
    final keyword = _keyword(immutable);
    final nullable = def.type.nullable;
    final deprecation = serializeFieldDeprecation(def);
    final line = nullable
        ? '$keyword ${def.codeName}: $type = null'
        : '$keyword ${def.codeName}: $type';
    return '$deprecation$line';
  }

  // ── Enum ────────────────────────────────────────────────────────────────────

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    final values = def.allValues.map(doSerializeEnumValue).toList();
    final unknown = def.unknownValue;
    final body = <String>[];

    final whenToJson = codeGenUtils.switchStatement(
      expression: 'this',
      cases: [
        ...def.values.map((v) => KotlinWhenBranch(
          caseValue: v.codeName,
          statement: '"${v.value.token}"',
        )),
        if (unknown != null)
          KotlinWhenBranch(
            caseValue: unknown.codeName,
            statement: 'throw IllegalArgumentException("${def.codeName}.${unknown.codeName} cannot be serialized")',
          ),
      ],
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
          statement: unknown != null
              ? '${def.codeName}.${unknown.codeName}'
              : 'throw IllegalArgumentException("Invalid ${def.codeName}: \$value")',
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
      return stringLiteral(decodeGraphqlString(value));
    }
    return '"$value"';
  }

  // Dart's double.toString() can emit "NaN"/"Infinity"/"-Infinity", none of
  // which are valid Kotlin literals — those need the Double/Float companion
  // constants instead. A Kotlin Float literal also needs an explicit `f`
  // suffix, since a bare decimal literal defaults to Double.
  @override
  String stringLiteral(String decoded) =>
      '"${escapeStringBody(decoded, quote: '"', dollar: true, control: (unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')}"';

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
      return serializeInterface(def,
          skipJsonConversionMethods: shouldSkipJsonMethods(def),
          fieldsAsFunctions: def.fieldAsMethods);
    }
    return _serializeClass(def);
  }

  String _serializeClass(GLTypeDefinition def) {
    final fields = def.getSerializableFields(grammar.mode);

    final params = fields.map((f) {
      final type = serializeType(f.type);
      final keyword = _keyword(typesAsDataClass);
      final overrides = def.isOverride(f);
      final prefix = overrides ? 'override $keyword' : keyword;
      final deprecation = serializeFieldDeprecation(f);
      if (f.type.nullable) {
        return '${deprecation}$prefix ${f.codeName}: $type = null';
      }
      return '${deprecation}$prefix ${f.codeName}: $type';
    }).toList();

    final instanceMethods = <String>[];
    final companionMethods = <String>[];

    final implementsNonInternalInterface = def.interfaces
        .any((i) => !i.hasDirective(glInternal));

    if (!shouldSkipJsonMethods(def)) {
      final toJsonPrefix = implementsNonInternalInterface ? 'override ' : '';
      instanceMethods.add('${toJsonPrefix}${_generateToJson(fields, def)}');
      companionMethods.add(_generateFromJson(fields, def.codeName, def));
    }

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

  String serializeInterface(GLInterfaceDefinition def,
      {bool skipJsonConversionMethods = false,
      bool fieldsAsFunctions = false,
      bool suspendFunctions = false}) {
    final fields = def.getSerializableFields(grammar.mode);
    final fieldDecls = fields.map((f) {
      final type = serializeType(f.type);
      if (fieldsAsFunctions) {
        // Subscription methods return a cold `Flow<T>` and are never `suspend`.
        final isFlow = f.type.wrapper == 'Flow';
        final override = def.isOverride(f) ? 'override ' : '';
        final suspend = suspendFunctions && !isFlow ? 'suspend ' : '';
        final args = f.arguments
            .map((a) => '${a.codeName}: ${serializeType(a.type)}')
            .join(', ');
        return '$override${suspend}fun ${f.codeName}($args): $type';
      }
      final prefix = def.isOverride(f) ? 'override val' : 'val';
      return '$prefix ${f.codeName}: $type';
    }).toList();

    final companionMethods = <String>[];
    final subTypes = def.getSerializableImplementations(mode);
    if (!skipJsonConversionMethods && subTypes.isNotEmpty) {
      companionMethods.add(def.syntheticImplementation != null
          ? serializeSyntheticInterfaceFromJson(def)
          : _serializeFromJsonForInterface(def.codeName, subTypes));
    }

    final isInternal = def.hasDirective(glInternal);
    final toJsonOverridesSuperInterface = def.interfaces.any((iname) {
      final iface = grammar.interfaces[iname.tokenInfo.token];
      return iface != null && !iface.hasDirective(glInternal);
    });
    final toJsonPrefix = toJsonOverridesSuperInterface ? 'override fun' : 'fun';

    final body = <String>[
      ...fieldDecls.map((d) => d),
      if (!skipJsonConversionMethods && !isInternal)
        '$toJsonPrefix toJson(): $_mapType',
      if (companionMethods.isNotEmpty) ...[
        '',
        codeGenUtils.companionObject(companionMethods),
      ],
    ];

    final superIfaces = def.interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList();
    return codeGenUtils.kotlinInterface(
        name: def.codeName, body: body, superInterfaces: superIfaces.isEmpty ? null : superIfaces);
  }

  String _discriminatedFromJson(String token, Set<GLTypeDefinition> subTypes, GLRestDiscriminator discriminator) {
    String typeName(GLTypeDefinition t) => t.derivedFromType?.tokenInfo.token ?? t.tokenInfo.token;
    final byTypename = codeGenUtils.switchStatement(
      expression: 'map["__typename"]',
      cases: [
        for (final t in subTypes)
          KotlinWhenBranch(caseValue: '"${typeName(t)}"', statement: 'return ${t.codeName}.fromJson(map)'),
        KotlinWhenBranch(caseValue: 'else', statement: 'Unit'),
      ],
    );
    final byValue = codeGenUtils.switchStatement(
      expression: 'discriminator',
      cases: [
        for (final t in subTypes)
          KotlinWhenBranch(
              caseValue: '"${discriminator.valueByType[typeName(t)] ?? typeName(t)}"',
              statement: 'return ${t.codeName}.fromJson(map)'),
        KotlinWhenBranch(
          caseValue: 'else',
          statement:
              'throw IllegalArgumentException("Cannot decode $token: unknown or missing \\"${discriminator.field}\\" value (\$discriminator)")',
        ),
      ],
    );
    return 'fun fromJson(map: $_mapType): $token ${codeGenUtils.block([
      byTypename,
      'val discriminator = map["${discriminator.field}"]',
      byValue,
    ])}';
  }

  @override
  String serializeSyntheticInterfaceFromJson(GLInterfaceDefinition interface) =>
      'fun fromJson(map: $_mapType): ${interface.codeName} = ${interface.syntheticImplementation!.codeName}.fromJson(map)';

  String _serializeFromJsonForInterface(String token, Set<GLTypeDefinition> subTypes) {
    final discriminator = grammar.restDiscriminators[token];
    if (discriminator != null) return _discriminatedFromJson(token, subTypes, discriminator);
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
    final typeName = context is GLTypeDefinition ? context.jsonTypeName : null;
    final entries = [
      if (typeName != null) '"__typename" to "$typeName"',
      ...fields.map((f) => '"${f.name}" to ${toJsonExpr(f.type, f.codeName)}'),
    ];
    final omitNulls = context is GLInputDefinition && context.isOneOf;
    return 'fun toJson(): $_mapType = ${codeGenUtils.constructorCall('mapOf', entries)}${omitNulls ? '.filterValues { it != null }' : ''}';
  }

  @override
  String listToJson(GLType list, String value, String element, String body, GLImportSink? context) =>
      element == body ? value : KotlinCodeGenUtils.mapCall(receiver: value, param: element, body: body, nullable: list.nullable);

  @override
  String listFromJson(GLType list, String json, String element, String body, GLImportSink? context) {
    final casted = list.nullable ? '($json as $_anyListType?)' : '($json as $_anyListType)';
    return element == body ? casted : KotlinCodeGenUtils.mapCall(receiver: casted, param: element, body: body, nullable: list.nullable);
  }

  @override
  String modelToJson(GLType type, String value) => KotlinCodeGenUtils.safeCall(value, 'toJson()', type.nullable);

  @override
  String enumFromJson(GLType type, String json) {
    final codeName = resolveCodeName(type.token);
    if (type.nullable) return KotlinCodeGenUtils.letCall(receiver: '($json as String?)', body: '$codeName.fromJson(it)');
    return '$codeName.fromJson($json as String)!!';
  }

  @override
  String modelFromJson(GLType type, String json) {
    final codeName = resolveCodeName(type.token);
    if (type.nullable) {
      return KotlinCodeGenUtils.letCall(receiver: '($json as Map<*, *>?)', body: '$codeName.fromJson(it as $_mapType)');
    }
    return '$codeName.fromJson($json as $_mapType)';
  }

  @override
  String plainFromJson(GLType type, String json) =>
      _scalarCast(json, getTypeNameFromGQExternal(type.token) ?? type.token, type.nullable);

  @override
  String scalarFromJson(GLScalarCodec codec, String json, {required bool nullable}) =>
      nullable ? KotlinCodeGenUtils.letCall(receiver: json, body: codec.decode('it')) : codec.decode(json);

  @override
  String scalarToJson(GLScalarCodec codec, String value, {required bool nullable}) =>
      nullable ? KotlinCodeGenUtils.letCall(receiver: value, body: codec.encode('it')) : codec.encode(value);

  // ── fromJson ─────────────────────────────────────────────────────────────────

  String _generateFromJson(List<GLField> fields, String token, GLToken context) {
    final assignments = fields
        .map((f) => '${f.codeName} = ${fromJsonExpr(f.type, 'map["${f.name}"]')}')
        .toList();
    final checks = _requiredFieldChecks(fields, context);
    final constructed = codeGenUtils.constructorCall(token, assignments);
    if (checks.isEmpty) {
      return '@Suppress("UNCHECKED_CAST")\nfun fromJson(map: $_mapType): $token = $constructed';
    }
    return '@Suppress("UNCHECKED_CAST")\nfun fromJson(map: $_mapType): $token ${codeGenUtils.block([...checks, 'return $constructed'])}';
  }

  List<String> _requiredFieldChecks(List<GLField> fields, GLToken context) {
    final token = context.token;
    if (!grammar.restReachableTypeNames.contains(token)) return const [];
    return [
      for (final field in fields)
        if (!field.type.nullable && field.initialValue == null)
          codeGenUtils.ifStatement(
            condition: 'map["${field.name}"] == null',
            ifBlockStatements: ['throw IllegalArgumentException("$token.${field.name} is missing or null in the response")'],
          ),
    ];
  }

  String _scalarCast(String access, String token, bool nullable) {
    final exact = _kotlinExactNumberCasts[token];
    if (exact != null) {
      final convert = 'java.math.BigDecimal(it.toString()).$exact';
      if (nullable) return '($access as Number?)?.let { $convert }';
      return '($access as Number).let { $convert }';
    }
    if (_kotlinNumbers.contains(token)) {
      final method = _kotlinNumberCasts[token]!;
      if (nullable) return '($access as Number?)?.$method';
      return '($access as Number).$method';
    }
    if (nullable) return '$access as $token?';
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
        codeGenUtils.ifStatement(condition: 'other !is $token', ifBlockStatements: ['return false']),
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
    return [mapping.toMethod(def, targetName, plan)];
  }

  List<String> _generateFromMappingMethods(GLInputDefinition def) {
    final fromPlan = grammar.resolveFromMappingPlan(def, mode);
    if (fromPlan == null || !fromPlan.derivesAnythingFromTarget) return [];
    final targetWireName = def.mapsToType!;
    final targetName = grammar.types[targetWireName]?.codeName ?? targetWireName;
    return [mapping.fromMethod(def, targetName, fromPlan)];
  }

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
