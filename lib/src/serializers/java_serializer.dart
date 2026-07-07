import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_input_mapping.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/utils.dart';

const _list = "List";
const _map = "Map";
const _javaNumbers = {"Byte", "Short", "Integer", "Long", "Float", "Double", "byte", "short", "int", "long", "float", "double"};

const _javaNumberMethods = {
  "Byte": "byteValue()",
  "Short": "shortValue()",
  "Integer": "intValue()",
  "Long": "longValue()",
  "Float": "floatValue()",
  "Double": "doubleValue()",
  "byte": "byteValue()",
  "short": "shortValue()",
  "int": "intValue()",
  "long": "longValue()",
  "float": "floatValue()",
  "double": "doubleValue()"
};

const Set<String> _javaPrimitives = {
  'boolean',
  'byte',
  'short',
  'int',
  'long',
  'float',
  'double',
  'char',
};

String _listOf(String type) {
  return '${_list}<${type}>';
}

String _mapOf(String key, String type) {
  return '${_map}<${key}, ${type}>';
}

class JavaSerializer extends GLSerializer {
  final bool inputsAsRecords;
  final bool typesAsRecords;
  final bool typesCheckForNulls;
  final bool inputsCheckForNulls;
  final bool immutableInputFields;
  final bool immutableTypeFields;
  final bool jspecify;
  final codeGenUtils = JavaCodeGenUtils();

  @override
  Map<String, String> get defaultTypeMap => const {
        "ID": "String",
        "String": "String",
        "Float": "Double",
        "Int": "Integer",
        "Boolean": "Boolean",
        "Long": "Long",
        "Null": "null",
        "gqlMapStrObj": "Map<String, Object>",
        "dynamicValue": "Object",
        "void": "void",
      };

  JavaSerializer(
    super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false,
    this.typesCheckForNulls = true,
    this.inputsCheckForNulls = true,
    this.immutableInputFields = true,
    this.immutableTypeFields = false,
    this.jspecify = false,
    super.typeMapOverrides = const {},
    required super.importPrefix,
  }) {
    _initAnnotations();
    if (jspecify) grammar.applyJspecifyAnnotations(isPrimitive: _isPrimitiveType);
  }

  @override
  String serializeDefaultLiteral(GLType type, Object? value, {bool needsConst = false}) {
    if (value == null) return 'null';
    if (value is int) {
      // A GraphQL Float default without a decimal point (e.g. `min: Float = 0`)
      // parses as a Dart int, but boxed Double/Float fields don't accept an
      // Int literal in a field initializer (e.g. `private Double min = 0;`
      // fails to compile) — emit a floating literal instead.
      final javaType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      if (javaType == 'Double' || javaType == 'Float') {
        return _serializeFloatingLiteral(value.toDouble(), javaType);
      }
      return '$value';
    }
    if (value is double) {
      final javaType = getTypeNameFromGQExternal(type.token) ?? resolveCodeName(type.token);
      return _serializeFloatingLiteral(value, javaType);
    }
    if (value is bool) return '$value';
    if (value is List) {
      final innerType = type.inlineType;
      final items = value.map((e) => serializeDefaultLiteral(innerType, e)).join(', ');
      return 'Arrays.asList($items)';
    }
    if (value is Map) {
      final inputDef = grammar.inputs[type.token]!;
      final args = inputDef.fields.map((f) {
        return serializeDefaultLiteral(f.type, value[f.name.token]);
      }).join(', ');
      return 'new ${resolveCodeName(type.token)}($args)';
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

  // Dart's double.toString() can emit "NaN"/"Infinity"/"-Infinity", none of
  // which are valid Java literals — those need the Double/Float constants
  // instead. A Java float literal also needs an explicit `f` suffix, since a
  // bare decimal literal defaults to double.
  String _serializeFloatingLiteral(double value, String javaType) {
    final isFloat = javaType == 'Float';
    if (value.isNaN) return isFloat ? 'Float.NaN' : 'Double.NaN';
    if (value.isInfinite) {
      final sign = value.isNegative ? 'NEGATIVE' : 'POSITIVE';
      return isFloat ? 'Float.${sign}_INFINITY' : 'Double.${sign}_INFINITY';
    }
    return isFloat ? '${value}f' : '$value';
  }

  void _initAnnotations() {
    grammar.handleAnnotations((val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  String serializeAnnotation(GLDirectiveValue value) {
    return AnnotationSerializer.serializeAnnotation(value, multiLineString: false);
  }

  @override
  String doSerializeEnumDefinition(GLEnumDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    var toJson = serializeToJsonForEnum(def);
    var fromJson = serializeFromJsonForEnum(def);
    var enum_ = codeGenUtils.createEnum(
        enumName: def.codeName,
        enumValues: def.values.map((e) => doSerializeEnumValue(e)).toList(),
        methods: [if (fromJson.isNotEmpty) fromJson, if (toJson.isNotEmpty) toJson]);
    buffer.writeln(enum_);
    return buffer.toString();
  }

  String serializeToJsonForEnum(GLEnumDefinition def) {
    return codeGenUtils.createMethod(
      returnType: "public String",
      methodName: "toJson",
      statements: [
        codeGenUtils.switchStatement(
          expression: "this",
          cases: [...def.values.map((v) => JavaCaseStatement(caseValue: v.codeName, statement: 'return "${v.value.token}";'))],
          defaultStatements: ['throw new IllegalArgumentException("Invalid ${def.codeName}: " + this);'],
        )
      ],
    );
  }

  String serializeFromJsonForEnum(GLEnumDefinition def) {
    return codeGenUtils.createMethod(
      returnType: "public static ${def.codeName}",
      methodName: "fromJson",
      arguments: ["String value"],
      statements: [
        "if (value == null) return null;",
        codeGenUtils.switchStatement(
          expression: "value",
          cases: [...def.values.map((v) => JavaCaseStatement(caseValue: '"${v.value.token}"', statement: 'return ${v.codeName};'))],
          defaultStatements: ['throw new IllegalArgumentException("Invalid ${def.codeName}: " + value);'],
        )
      ],
    );
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    var deprecation = serializeEnumValueDeprecation(value);
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (deprecation.isEmpty && decorators.isEmpty) {
      return value.codeName;
    } else {
      return [deprecation, decorators, value.codeName].where((s) => s.isNotEmpty).join(" ");
    }
  }

  @override
  String serializeFieldDeprecation(GLField field) {
    if (!field.isDeprecated) return '';
    final reason = field.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */\n@Deprecated\n";
  }

  @override
  String serializeEnumValueDeprecation(GLEnumValue value) {
    if (!value.isDeprecated) return '';
    final reason = value.deprecationReason ?? 'No longer supported';
    final safeReason = reason.replaceAll('*/', '*\\/').replaceAll(RegExp(r'[\r\n]+'), ' ');
    return "/** @deprecated $safeReason */ @Deprecated";
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField, {bool isOverride = false}) {
    final type = def.type;
    final name = def.codeName;
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives(), joiner: "\n");
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("private ");
    if (immutable) {
      buffer.write("final ");
    }
    buffer.write('${serializeType(type)} $name');
    // Only emit field initializer for non-final fields — final fields
    // receive their default in the constructor body instead.
    if (!immutable && !isTypeField && def.initialValue != null) {
      buffer.write(' = ${serializeDefaultLiteral(type, def.initialValue)}');
    }
    buffer.write(';');
    return buffer.toString();
  }

  String serializeArgument(GLArgumentDefinition arg) {
    var type = arg.type;
    var name = arg.codeName;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "${serializeType(type)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators$result";
    }
    return result;
  }

  String serializeArgumentField(GLField def, {bool withDecorators = false, String decoratorJoiner = "\n", bool isTypeField = false}) {
    final type = def.type;
    final name = def.codeName;
    final buffer = StringBuffer();
    if (withDecorators) {
      var decorators = serializeDecorators(def.getDirectives(), joiner: decoratorJoiner);
      if (decorators.trim().isNotEmpty) {
        buffer.write(decorators.trim());
        buffer.write(decoratorJoiner);
      }
    }
    buffer.write(serializeType(type));
    buffer.write(" ");
    buffer.write(name);
    return buffer.toString();
  }

  bool _isPrimitiveType(GLType type) {
    var serialized = serializeType(type);
    return _javaPrimitives.contains(serialized);
  }

  @override
  String serializeType(GLType def) {
    final String type;
    if (def is GLVoidType) {
      type = 'void';
    } else if (def is GLMapType) {
      type = _mapOf(serializeType(def.keyType).toBoxedType, serializeType(def.valueType).toBoxedType);
    } else if (def is GLListType) {
      type = JavaCodeGenUtils.listOf(grammar, serializeType(def.inlineType));
    } else {
      final token = def.token;
      var baseType = getTypeNameFromGQExternal(token) ?? resolveCodeName(token);
      if (typeIsJavaPrimitive(baseType) && def.nullable) {
        baseType = baseType.toBoxedType;
      }
      type = baseType;
    }
    final wrapper = def.wrapper;
    if (wrapper == null) return type;
    final wrapperImport = def.wrapperImport;
    if (wrapperImport != null) {
      (grammar.types[def.token] ?? grammar.interfaces[def.token])
          ?.addImport(wrapperImport);
    }
    return '$wrapper<${type.toBoxedType}>';
  }

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (inputsAsRecords) {
      buffer.writeln(serializeRecord(def.codeName, def.fields, {}, def, extraStatements: generateMappingMethods(def)));
      return buffer.toString();
    }
    var class_ = codeGenUtils.createClass(className: def.codeName, statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e, immutableInputFields, false)),
      "",
      if (!immutableInputFields) generateContructor(def.codeName, [], "public", def, checkForNulls: inputsCheckForNulls),
      "",
      generateContructor(def.codeName, def.getSerializableFields(grammar.mode), immutableInputFields ? "public" : "private", def,
          checkForNulls: inputsCheckForNulls),
      generateBuilder(def.codeName, def.getSerializableFields(grammar.mode), true),
      ...def.getSerializableFields(grammar.mode).map((e) => serializeGetter(e, def, checkForNulls: inputsCheckForNulls)),
      ...def.getSerializableFields(grammar.mode).where((field) {
        //check for the next directive here
        return !immutableInputFields;
      }).map((e) => serializeSetter(e, def, checkForNulls: inputsCheckForNulls)),
      generateToJson(def.getSerializableFields(grammar.mode), def),
      generateFromJson(def.getSerializableFields(mode), def.codeName, def),
      ...generateMappingMethods(def),
    ]);
    buffer.write(class_);
    return buffer.toString();
  }

  bool _isNumber(GLType type) {
    if (type.isList) {
      return _isNumber(type.inlineType);
    }
    var serializedType = serializeType(type);
    return _javaNumbers.contains(serializedType);
  }

  String _numberValueMethod(GLType type) {
    if (type.isList) {
      return _numberValueMethod(type.inlineType);
    }
    return _javaNumberMethods[serializeType(type)]!;
  }

  String getFromJsonCall(GLField field, String varName, int depth, GLToken context, [GLType? type]) {
    type ??= field.type;
    String callMapDotGet = depth == 0 ? '.get("${field.name.token}")' : '';
    String nullCheckStatement = type.nullable ? '${varName}${callMapDotGet} == null ? null :' : '';

    if (type.isList) {
      var newVarName = '${varName}${depth}';
      var inlineType = type.inlineType;
      String targetCast;
      if (grammar.isNonProjectableType(inlineType.token) && !grammar.isEnum(inlineType.token) && !grammar.isInput(inlineType.token)) {
        targetCast = "(${_listOf('Object')})";
      } else if (grammar.isEnum(type.token)) {
        targetCast = "(${_listOf('Object')})";
      } else {
        targetCast = "(${_listOf('Object')})";
      }
      String mapFunction = 'map(${newVarName} -> ${getFromJsonCall(field, newVarName, depth + 1, context, type.inlineType)})';
      var finalResult = '$nullCheckStatement (${targetCast}${varName}${callMapDotGet}).stream().${mapFunction}.${javaCollectorsToList}';
      context.addImport(JavaImports.collectors);
      return finalResult;
    }
    String result;
    if (grammar.isNonProjectableType(type.token) && !grammar.isEnum(type.token) && !grammar.isInput(type.token)) {
      if (_isNumber(type)) {
        result = '((Number)${varName}${callMapDotGet}).${_numberValueMethod(type)}';
      } else {
        result = '(${serializeType(type)})${varName}${callMapDotGet}';
      }
    } else if (grammar.isEnum(type.token)) {
      result = '${resolveCodeName(type.token)}.fromJson((String)${varName}${callMapDotGet})';
    } else {
      result = '${resolveCodeName(type.token)}.fromJson((${_mapOf('String', 'Object')})${varName}${callMapDotGet})';
    }
    return nullCheckStatement.isEmpty ? result : '$nullCheckStatement $result';
  }

  String generateFromJson(List<GLField> fields, String token, GLToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.suppressWarnings);

    buffer.writeln('@SuppressWarnings("unchecked")');
    buffer.writeln(
      codeGenUtils.createMethod(returnType: "public static ${token}", methodName: "fromJson", arguments: [
        '${_mapOf('String', 'Object')} json'
      ], statements: [
        "return new ${token}(",
        ...fields.map((field) {
          var statement = getFromJsonCall(field, 'json', 0, context);
          if (field != fields.last) {
            return "${statement},";
          }
          return statement;
        }),
        ");"
      ]),
    );
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Mapping methods (@glMapsTo)
  // ---------------------------------------------------------------------------

  @override
  String generateToMethod(GLInputDefinition def, String targetType, ToMappingPlan plan) {
    // Whether the source input and target type are records (affects accessor style).
    final targetIsRecord = typesAsRecords;

    final params = [
      ...plan.requiredParams.map(
        (f) => '${serializeType(f.targetField.type)} ${f.targetField.codeName}',
      ),
      ...plan.defaultParams.map(
        (f) => '${serializeType(f.targetField.type)} default${f.targetField.codeName.firstUp}',
      ),
    ];

    if ([...plan.requiredParams, ...plan.defaultParams].any((f) => f.targetField.type.isList)) {
      def.addImport(JavaImports.list);
    }

    if (targetIsRecord) {
      // Build positional constructor args in the target type's field declaration order.
      final targetDef = grammar.types[targetType];
      final targetFields = targetDef?.getSerializableFields(grammar.mode) ?? [];

      // Index mappings by target field name for quick lookup.
      final autoByTarget = {for (final f in plan.autoMapped) f.targetField.name.token: f};
      final defaultByTarget = {for (final f in plan.defaultParams) f.targetField.name.token: f};
      final requiredByTarget = {for (final f in plan.requiredParams) f.targetField.name.token: f};

      final constructorArgs = <String>[];
      for (final tf in targetFields) {
        final name = tf.name.token;
        if (autoByTarget.containsKey(name)) {
          final f = autoByTarget[name]!;
          final getter = _getterFieldName(def, f.sourceField!, true);
          constructorArgs.add(_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def));
        } else if (defaultByTarget.containsKey(name)) {
          final f = defaultByTarget[name]!;
          final getter = _getterFieldName(def, f.sourceField!, true);
          constructorArgs.add('$getter != null ? $getter : default${f.targetField.codeName.firstUp}');
        } else if (requiredByTarget.containsKey(name)) {
          constructorArgs.add(tf.codeName);
        }
      }

      final lastIdx = constructorArgs.length - 1;
      return codeGenUtils.createMethod(
        returnType: 'public $targetType',
        methodName: 'to${targetType.firstUp}',
        arguments: params,
        statements: [
          'return new $targetType(',
          ...constructorArgs.asMap().entries.map(
                (e) => e.key < lastIdx ? '${e.value},' : e.value,
              ),
          ');',
        ],
      );
    }

    // Class-style target: builder chain.
    final builderCalls = [
      ...plan.autoMapped.map((f) {
        final getter = _getterFieldName(def, f.sourceField!, true);
        final expr = _toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def);
        return '.${f.targetField.codeName}($expr)';
      }),
      ...plan.defaultParams.map((f) {
        final getter = _getterFieldName(def, f.sourceField!, true);
        return '.${f.targetField.codeName}($getter != null ? $getter : default${f.targetField.codeName.firstUp})';
      }),
      ...plan.requiredParams.map(
        (f) => '.${f.targetField.codeName}(${f.targetField.codeName})',
      ),
    ];

    return codeGenUtils.createMethod(
      returnType: 'public $targetType',
      methodName: 'to${targetType.firstUp}',
      arguments: params,
      statements: [
        'return $targetType.builder()',
        ...builderCalls,
        '.build();',
      ],
    );
  }

  @override
  String generateFromMethod(GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;
    final targetDef = grammar.types[targetType]!;

    final nullableListDefaultParams =
        plan.nullableListDefaults.map((f) => '${serializeType(f.sourceField!.type)} default${f.sourceField!.codeName.firstUp}');

    final promotedParams = plan.promoted.map(
      (f) => '${serializeType(f.sourceField!.type)} ${f.sourceField!.codeName}',
    );

    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${serializeType(f.type)} ${f.codeName}',
    );

    if (plan.promoted.any((f) => f.sourceField!.type.isList) || plan.inputOnly.any((f) => f.type.isList) || plan.nullableListDefaults.isNotEmpty) {
      def.addImport(JavaImports.list);
    }

    final autoBySource = {for (final f in plan.autoMapped) f.sourceField!.name.token: f};
    final nullableListBySource = {for (final f in plan.nullableListDefaults) f.sourceField!.name.token: f};
    final promotedNames = {for (final f in plan.promoted) f.sourceField!.name.token};
    final inputOnlyNames = {for (final f in plan.inputOnly) f.name.token};

    final fields = def.getSerializableFields(grammar.mode);
    final constructorArgs = <String>[];
    for (final field in fields) {
      final fieldName = field.name.token;
      if (autoBySource.containsKey(fieldName)) {
        final f = autoBySource[fieldName]!;
        final sourceExpr = '${targetVar}.${_getterFieldName(targetDef, f.targetField, false)}';
        constructorArgs.add(_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def));
      } else if (nullableListBySource.containsKey(fieldName)) {
        final f = nullableListBySource[fieldName]!;
        final sourceExpr = '${targetVar}.${_getterFieldName(targetDef, f.targetField, false)}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        constructorArgs.add('$expr != null ? $expr : default${f.sourceField!.codeName.firstUp}');
      } else if (promotedNames.contains(fieldName) || inputOnlyNames.contains(fieldName)) {
        constructorArgs.add(field.codeName);
      }
    }

    return codeGenUtils.createMethod(
      returnType: 'public static ${def.codeName}',
      methodName: 'from${targetType.firstUp}',
      arguments: [
        '$targetType $targetVar',
        ...nullableListDefaultParams,
        ...promotedParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return new ${def.codeName}(',
        ...constructorArgs.asMap().entries.map(
              (e) => e.key < constructorArgs.length - 1 ? '${e.value},' : e.value,
            ),
        ');',
      ],
    );
  }

  /// Returns the Java expression for a toXxx() field assignment.
  /// Uses builder-chain suffix via stream().map().collect() for lists.
  String _toMappingExpr(String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _toMappingExpr(varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return JavaCodeGenUtils.safeCall(variable, 'to${resolveCodeName(targetType.token).firstUp}()', sourceType.nullable);
    }
    return variable; // same type — direct copy
  }

  /// Returns the Java expression for a fromXxx() field assignment.
  String _fromMappingExpr(String variable, String sourceElemToken, GLType targetType, int index, GLToken context) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _fromMappingExpr(varName, sourceElemToken, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      final sourceCodeName = resolveCodeName(sourceElemToken);
      final targetCodeName = resolveCodeName(targetType.token);
      return JavaCodeGenUtils.nullSafeExpr(variable, '$sourceCodeName.from${targetCodeName.firstUp}($variable)', targetType.nullable);
    }
    return variable; // same type — direct copy
  }

  String generateToJson(List<GLField> fields, GLToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);

    buffer.writeln(
      codeGenUtils.createMethod(returnType: "public ${_mapOf('String', 'Object')}", methodName: "toJson", statements: [
        "${_mapOf('String', 'Object')} map = new HashMap<>();",
        ...fields.map((field) => 'map.put("${field.name}", ${_fieldToJson(field, context)});'),
        'return map;'
      ]),
    );

    return buffer.toString();
  }

  String _fieldToJson(GLField field, GLToken context) {
    var buffer = StringBuffer();
    var toJosnCall = callToJson(field, field.type, field.codeName, 0, context);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String callToJson(GLField field, GLType type, String variableName, int index, GLToken context) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson = callToJson(field, inlineType, varName, index + 1, context);
      context.addImport(JavaImports.collectors);
      if (varName == inlineCallToJson) {
        return JavaCodeGenUtils.streamMapCollect(receiver: variableName, nullable: type.nullable);
      }
      return JavaCodeGenUtils.streamMapCollect(receiver: variableName, param: varName, body: inlineCallToJson, nullable: type.nullable);
    } else if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return JavaCodeGenUtils.safeCall(variableName, "toJson()", type.nullable);
    }
    return variableName;
  }

  String generateContructor(String name, List<GLField> fields, String? modifier, GLToken context,
      {bool checkForNulls = false, bool isTypeField = false}) {
    String nullCheck = "";
    if (checkForNulls) {
      var checkingFields = fields
          .where((e) => !e.type.nullable && e.initialValue == null && !_isPrimitiveType(e.type))
          .map((e) => "Objects.requireNonNull(${e.codeName});")
          .toList();

      if (checkingFields.isNotEmpty) {
        nullCheck = serializeListText(checkingFields, join: "\n", withParenthesis: false);
        context.addImport(JavaImports.objects);
      }
    }

    final buffer = StringBuffer();
    if (modifier != null) {
      buffer.write("$modifier ");
    }
    buffer.writeln(
        "$name(${serializeListText(fields.map((e) => serializeArgumentField(e, isTypeField: isTypeField)).toList(), join: ", ", withParenthesis: false)}) {");
    if (nullCheck.isNotEmpty) {
      buffer.writeln(nullCheck.ident());
    }
    if (fields.isNotEmpty) {
      // Add Arrays import if any field has a list-type default value.
      final hasListDefault = fields.any((e) => !isTypeField && e.initialValue != null && e.type.isList);
      if (hasListDefault) {
        context.addImport(JavaImports.arrays);
      }
      buffer.writeln(serializeListText(
              fields.map((e) {
                if (!isTypeField && e.initialValue != null) {
                  final lit = serializeDefaultLiteral(e.type, e.initialValue);
                  return "this.${e.codeName} = ${e.codeName} != null ? ${e.codeName} : $lit;";
                }
                return "this.${e.codeName} = ${e.codeName};";
              }).toList(),
              join: "\n",
              withParenthesis: false)
          .ident());
    }
    buffer.writeln("}");
    return buffer.toString();
  }

  String generateBuilder(String name, List<GLField> fields, bool forInput) {
    if (fields.isEmpty) {
      return "";
    }

    var buffer = StringBuffer();
    buffer.writeln(codeGenUtils.createMethod(
      returnType: "public static Builder",
      methodName: "builder",
      statements: ['return new Builder();'],
    ));

    buffer.writeln();
    buffer.writeln(codeGenUtils.createClass(staticClass: true, className: 'Builder', statements: [
      ...fields.map((field) {
        final annotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
        final copy = GLField(name: field.name, type: field.type, arguments: field.arguments, directives: [])..codeName = field.codeName;
        final serialized = serializeField(copy, false, !forInput);
        return annotation != null ? '$annotation\n$serialized' : serialized;
      }),
      "",
      ...fields.map((e) {
        final annotation = _isPrimitiveType(e.type) ? null : getJSpecifyAnnoation(e);
        return codeGenUtils.createMethod(
            returnType: 'public Builder',
            methodName: e.codeName,
            arguments: ['${annotation != null ? "$annotation " : ""}${serializeArgumentField(e)}'],
            statements: ['this.${e.codeName} = ${e.codeName};', 'return this;']);
      }),
      "",
      codeGenUtils.createMethod(
          returnType: 'public $name', methodName: 'build', statements: ['return new $name(${fields.map((e) => e.codeName).join(", ")});']),
    ]));

    return buffer.toString();
  }

  String serializeGetter(GLField field, GLTokenWithFields context, {bool checkForNulls = false, bool isTypeField = false, bool isOverride = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    var returnType = serializeType(field.type);
    // Java's override rules require a primitive return type to match the
    // superinterface's exactly — a non-null `Boolean!` narrowing a nullable
    // `Boolean` produces a primitive `boolean` getter that neither compiles
    // against nor satisfies a `Boolean`-returning interface method (and would
    // wrongly rename to `isAlive`). Reference-type narrowing (including list
    // element types, e.g. `[Lion!]!` narrowing `[Animal!]!`) is legal Java
    // covariance and must NOT be rewritten here — for lists that covariance is
    // made to type-check by widening the *interface's own* declaration to
    // `List<? extends X>` (see _wildcardListReturnType), not by changing the
    // implementer's getter.
    final interfaceField = isOverride && context is GLTypeDefinition ? context.getInterfaceField(field) : null;
    if (interfaceField != null && !interfaceField.type.isList) {
      final interfaceType = serializeType(interfaceField.type);
      if (_javaPrimitives.contains(returnType) && !_javaPrimitives.contains(interfaceType)) {
        returnType = interfaceType;
      }
    }
    var jspecifyAnnotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
    var result = codeGenUtils.createMethod(
        returnType: "public ${returnType}",
        methodName: getterName(context, field.name.token),
        statements: [
          if (checkForNulls && !field.type.nullable && !_isPrimitiveType(field.type)) 'Objects.requireNonNull(${field.codeName});',
          'return ${field.codeName};'
        ]);
    var buffer = StringBuffer();
    if (isOverride) {
      buffer.writeln("@Override");
    }
    if (jspecifyAnnotation != null) {
      buffer.writeln(jspecifyAnnotation);
    }
    buffer.write(result);
    return buffer.toString();
  }

  String? getJSpecifyAnnoation(GLField field) {
    var decorators = field.getDirectives(skipGenerated: false).where((e) => e.token == glDecorators).toList();
    if (decorators.isEmpty) {
      return null;
    }
    final directive = decorators.first;
    var value = directive.getArgValue("value");
    if (value is List<String>) {
      for (var v in value) {
        var vv = v.substring(1, v.length - 1);
        if (vv == jspecifyNonNull || vv == jspecifyNullable) {
          return vv;
        }
      }
    }
    return null;
  }

  String serializeMethod(GLField field, {String? modifier}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives()).trim();
    var args = serializeListText(field.arguments.map(serializeArgument).toList(), withParenthesis: false, join: ", ");
    var result = "${serializeType(field.type)} ${field.codeName}($args)";
    if (modifier != null) {
      result = "$modifier $result";
    }
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.write(result);
    return buffer.toString();
  }

  String serializeRecord(
    String recordName,
    List<GLField> fields,
    Set<String> interfaceNames,
    GLToken context, {
    List<String> extraStatements = const [],
  }) {
    return codeGenUtils.createRecord(
        recordName: recordName,
        components: fields.map((f) {
          final annotation = _isPrimitiveType(f.type) ? null : getJSpecifyAnnoation(f);
          final component = serializeArgumentField(f, withDecorators: true, decoratorJoiner: " ");
          // withDecorators already emits jspecify for type fields; only prepend for input fields
          if (annotation == null || component.startsWith(annotation)) return component;
          return '$annotation $component';
        }).toList(),
        interfaces: interfaceNames.toList(),
        statements: [
          generateToJson(fields, context),
          generateFromJson(fields, recordName, context),
          ...extraStatements,
        ]);
  }

  /// Recursively wildcards every `List<...>` nesting level (e.g.
  /// `List<? extends List<? extends Node>>`) so a narrowed override like
  /// `List<List<Alpha>>` type-checks against `List<List<Node>>` — Java
  /// generics are invariant, so covariance must be threaded through every
  /// nested list layer, not just the outermost one.
  String _wildcardListReturnType(GLType type) {
    if (type is GLListType) {
      final inner = _wildcardListReturnType(type.inlineType);
      return 'List<? extends $inner>';
    }
    return serializeType(type);
  }

  String serializeGetterDeclaration(GLField field,
      {bool skipModifier = false, bool asProperty = false, GLInterfaceDefinition? owner}) {
    var returnType = serializeType(field.type);
    final type = field.type;
    if (type is GLListType) {
      // Java generics are invariant: List<Alpha> is not a subtype of
      // List<Node> even when Alpha implements Node. A covariant override
      // only type-checks if the interface declares `List<? extends Node>`.
      // Only emit the wildcard when some implementer actually narrows this
      // field — otherwise keep the plain `List<Node>` return type, which is
      // the ergonomic default for callers.
      final needsWildcard = owner != null && _isFieldNarrowedInImplementers(owner, field);
      returnType = needsWildcard ? _wildcardListReturnType(type) : JavaCodeGenUtils.listOf(grammar, serializeType(type.inlineType));
    }
    var result = returnType;
    if (asProperty) {
      result = "$result ${field.codeName}";
    } else {
      final name = owner != null
          ? getterName(owner, field.name.token)
          : (returnType == "boolean" ? "is${field.codeName.firstUp}" : "get${field.codeName.firstUp}");
      result = "$result $name";
    }
    result = "$result()";
    if (skipModifier) {
      return result;
    }
    return "public $result";
  }

  String getterName(GLTokenWithFields owner, String fieldName) {
    final field = owner.getFieldByName(fieldName);
    if (field == null) {
      throw ArgumentError("No field named '$fieldName' on ${owner.tokenInfo}");
    }
    // An implementer's override must keep the interface's accessor name even
    // when it narrows nullability — narrowing `Boolean` to `Boolean!` would
    // otherwise flip the accessor from `getX` to `isX` and break the override.
    final interfaceField = owner is GLTypeDefinition ? owner.getInterfaceField(field) : null;
    final isBoolean = serializeType(interfaceField?.type ?? field.type) == "boolean";
    final prefix = isBoolean ? "is" : "get";
    return "$prefix${field.codeName.firstUp}";
  }

  String _setterName(String propertyName) {
    return _accessorName(propertyName, true, false);
  }

  String _getterFieldName(GLTokenWithFields owner, GLField field, bool forInput) {
    final isRecord = forInput && inputsAsRecords || !forInput && typesAsRecords;
    if (isRecord) return "${field.codeName}()";
    return "${getterName(owner, field.name.token)}()";
  }

  String _accessorName(String name, bool setter, bool isBoolean) => JavaSerializer.accessorName(name, setter: setter, isBoolean: isBoolean);

  /// Java accessor name: `get`/`is`/`set` + capitalised property. Public &
  /// static so client serializers can build input-object getter access without a
  /// [JavaSerializer] instance.
  static String accessorName(String name, {bool setter = false, bool isBoolean = false}) {
    final prefix = setter ? "set" : (isBoolean ? "is" : "get");
    return "$prefix${name.firstUp}";
  }

  /// The getter call for [field] on a generated input/type. Records expose the
  /// bare component accessor (`name()`); otherwise it is `getName()` / `isFlag()`.
  /// [isRecord] and [isBoolean] are passed in because they depend on config and
  /// type resolution the caller already knows.
  static String getterCall(GLField field, {required bool isRecord, required bool isBoolean}) {
    if (isRecord) return "${field.codeName}()";
    return "${accessorName(field.name.token, isBoolean: isBoolean)}()";
  }

  String serializeSetter(GLField field, GLToken context, {bool checkForNulls = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    final annotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
    return codeGenUtils.createMethod(returnType: 'public void', methodName: _setterName(field.codeName), arguments: [
      '${annotation != null ? "$annotation " : ""}${serializeArgumentField(field)}'
    ], statements: [
      if (checkForNulls && !field.type.nullable && !_isPrimitiveType(field.type)) 'Objects.requireNonNull(${field.codeName});',
      "this.${field.codeName} = ${field.codeName};"
    ]);
  }

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      // Internal interfaces always use JavaBean getter style regardless of typesAsRecords,
      // because their implementations are always classes (never records).
      final isInternal = def.getDirectiveByName(glInternal) != null;
      return serializeInterface(def, getters: def.getDirectiveByName(glInterfaceFieldAsProperties) == null, forceClassGetters: isInternal);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GLTypeDefinition def) {
    final codeName = def.codeName;
    final interfaceNames = def.interfaceNames.map((e) => resolveCodeName(e.token)).toSet();

    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (typesAsRecords && def.getDirectiveByName(glInternal) == null) {
      buffer.writeln(serializeRecord(codeName, def.fields, interfaceNames, def));
      return buffer.toString();
    }
    buffer.writeln(codeGenUtils.createClass(className: codeName, interfaceNames: interfaceNames.toList(), statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e, immutableTypeFields, true)),
      "",
      if (!immutableTypeFields) generateContructor(codeName, [], "public", def, checkForNulls: typesCheckForNulls, isTypeField: true),
      "",
      generateContructor(codeName, def.getSerializableFields(grammar.mode), immutableTypeFields ? "public" : "private", def, isTypeField: true),
      "",
      generateBuilder(codeName, def.getSerializableFields(grammar.mode), false),
      "",
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeGetter(e, def, checkForNulls: typesCheckForNulls, isTypeField: true, isOverride: def.isOverride(e))),
      "",
      ...def.getSerializableFields(grammar.mode).where((field) {
        // @TODO check for mutable directive
        return !immutableTypeFields;
      }).map((e) => serializeSetter(e, def, checkForNulls: typesCheckForNulls)),
      generateEqualsAndHashCode(def),
      generateFromJson(def.getSerializableFields(grammar.mode), codeName, def),
      generateToJson(def.getSerializableFields(grammar.mode), def),
    ]));
    return buffer.toString();
  }

  String generateEqualsAndHashCode(GLTypeDefinition def) {
    var fieldsToInclude = def.getIdentityFields(grammar);
    if (fieldsToInclude.isNotEmpty) {
      return equalsHascodeCode(def, fieldsToInclude);
    }
    return "";
  }

  String equalsHascodeCode(GLTypeDefinition def, Set<String> fields) {
    final token = def.codeName;
    def.addImport("java.util.Objects");
    var buffer = StringBuffer();
    buffer.writeln('@Override');
    buffer.writeln(codeGenUtils.createMethod(returnType: "public boolean", methodName: "equals", arguments: [
      'Object o'
    ], statements: [
      codeGenUtils.ifStatement(condition: '!(o instanceof $token)', ifBlockStatements: ['return false;']),
      '$token o2 = ($token) o;',
      'return ${fields.map((e) => "Objects.equals($e, o2.$e);").join(" && ")}'
    ]));

    buffer.writeln();
    buffer.writeln('@Override');

    buffer.writeln(
      codeGenUtils.createMethod(returnType: 'public int', methodName: 'hashCode', statements: ['return Objects.hash(${fields.join(", ")});']),
    );

    return buffer.toString();
  }

  /// Whether some serializable implementer of [owner] narrows [field]
  /// (a list field) to a different element type than [owner] declares —
  /// e.g. `interface Base { nodeList: [Node!]! }` with
  /// `type Dog implements Base { nodeList: [Alpha!]! }`. Java generics are
  /// invariant, so such an override only compiles if the interface getter
  /// returns `List<? extends Node>` instead of `List<Node>`.
  bool _isFieldNarrowedInImplementers(GLInterfaceDefinition owner, GLField field) {
    if (!field.type.isList) return false;
    final declaredToken = field.type.inlineType.firstType.token;
    for (final impl in owner.getSerializableImplementations(mode)) {
      final implField = impl.getFieldByName(field.name.token);
      if (implField == null || !implField.type.isList) continue;
      if (implField.type.inlineType.firstType.token != declaredToken) return true;
    }
    return false;
  }

  String _serializeInterfaceField(GLField f, bool getters, GLInterfaceDefinition owner, {bool forceClassGetters = false}) {
    var buffer = StringBuffer();
    if (getters) {
      var fieldDecorators = serializeDecorators(f.getDirectives(), joiner: "\n");
      if (fieldDecorators.isNotEmpty) {
        buffer.writeln(fieldDecorators.trim().ident());
      }
      if (typesAsRecords && !forceClassGetters) {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, asProperty: true, owner: owner).ident());
      } else {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, owner: owner).ident());
      }
    } else {
      // serializeMethod already emits the field's decorators.
      buffer.write(serializeMethod(f).ident());
    }
    buffer.write(";");
    return buffer.toString();
  }

  String serializeInterface(GLInterfaceDefinition interface,
      {required bool getters, bool forceClassGetters = false, bool skipJsonConversionMethods = false}) {
    final codeName = interface.codeName;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var decorators = serializeDecorators(interface.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    bool generateJsonConverstionMethods = !skipJsonConversionMethods && interface.getDirectiveByName(glInterfaceFieldAsProperties) == null;
    if (generateJsonConverstionMethods) {
      interface.addImport(JavaImports.map);
    }
    buffer.writeln(codeGenUtils
        .createInterface(interfaceName: codeName, interfaceNames: interfaces.map((e) => resolveCodeName(e.tokenInfo.token)).toList(), statements: [
      ...fields.map((f) => _serializeInterfaceField(f, getters, interface, forceClassGetters: forceClassGetters)),
      if (generateJsonConverstionMethods && interface.getSerializableImplementations(mode).isNotEmpty) ...[
        "",
        "Map<String, Object> toJson();",
        _serializeFromJsonForInterface(codeName, interface.getSerializableImplementations(mode))
      ]
    ]));
    return buffer.toString();
  }

  String _serializeFromJsonForInterface(String token, Set<GLTypeDefinition> subTypes) {
    if (subTypes.isEmpty) {
      return "";
    }
    var buffer = StringBuffer("static ${token} fromJson(${_mapOf("String", "Object")} json) {");
    buffer.writeln();

    buffer.writeln('String typename = (String)json.get("__typename");'.ident());
    buffer.writeln("switch(typename) {".ident());
    for (var st in subTypes) {
      String typeNameValue = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      String currentCodeName = st.codeName;
      buffer.writeln('case "${typeNameValue}": return ${currentCodeName}.fromJson(json);'.ident(2));
    }
    buffer.writeln(
        'default: throw new RuntimeException(String.format("Invalid type %s. %s does not implement $token or not defined", typename, typename));'
            .ident(2));
    buffer.writeln("}".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  @override
  String getFileNameFor(GLToken token) {
    return "${resolveCodeName(token.token)}.java";
  }

  @override
  String serializeImportToken(GLToken token) {
    String? path;
    final codeName = resolveCodeName(token.token);

    if (grammar.enums.containsKey(token.token)) {
      path = "enums.$codeName";
    } else if (grammar.interfaces.containsKey(token.token) || grammar.projectedInterfaces.containsKey(token.token)) {
      path = "interfaces.$codeName";
    } else if (grammar.types.containsKey(token.token) || grammar.projectedTypes.containsKey(token.token)) {
      path = "types.$codeName";
    } else if (grammar.inputs.containsKey(token.token)) {
      path = "inputs.$codeName";
    } else if (grammar.services.containsKey(token.token)) {
      path = "services.$codeName";
    } else if (grammar.controllers.containsKey(token.token)) {
      path = "controllers.$codeName";
    }
    return "import ${importPrefix}.${path};";
  }

  @override
  String serializeImport(String import) {
    return 'import ${import};';
  }

  @override
  String serializeGlClass(GLClassModel theClass, {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies.map((dep) => serializeImportToken(dep)).where((l) => l.trim().isNotEmpty).toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports);
  }
}
