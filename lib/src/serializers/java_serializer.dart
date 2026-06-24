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
const _javaNumbers = {
  "Byte",
  "Short",
  "Integer",
  "Long",
  "Float",
  "Double",
  "byte",
  "short",
  "int",
  "long",
  "float",
  "double"
};

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
  final bool generateJsonMethods;

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
  };

  JavaSerializer(
    super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false,
    this.generateJsonMethods = false,
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
    if (value is int) return '$value';
    if (value is double) return '$value';
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
      return 'new ${type.token}($args)';
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

  void _initAnnotations() {
    grammar.handleAnnotations((val) =>
        AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  String serializeAnnotation(GLDirectiveValue value) {
    return AnnotationSerializer.serializeAnnotation(value,
        multiLineString: false);
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
        enumName: def.token,
        enumValues: def.values.map((e) => doSerializeEnumValue(e)).toList(),
        methods: [
          if (fromJson.isNotEmpty) fromJson,
          if (toJson.isNotEmpty) toJson
        ]);
    buffer.writeln(enum_);
    return buffer.toString();
  }

  /// True when any constant was renamed for keyword safety. In that case
  /// `name()` / `valueOf()` would leak the sanitized identifier onto the wire,
  /// so toJson/fromJson must map explicitly to the original GraphQL value.
  bool _enumSanitized(GLEnumDefinition def) =>
      def.values.any((v) => v.codeName != v.value.token);

  String serializeToJsonForEnum(GLEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    if (!_enumSanitized(def)) {
      return codeGenUtils.createMethod(
        returnType: "public String",
        methodName: "toJson",
        statements: ["return name();"],
      );
    }
    return codeGenUtils.createMethod(
      returnType: "public String",
      methodName: "toJson",
      statements: [
        codeGenUtils.switchStatement(
          expression: "this",
          cases: [
            ...def.values.map((v) => JavaCaseStatement(
                caseValue: v.codeName, statement: 'return "${v.value.token}";'))
          ],
          defaultStatements: [
            'throw new IllegalArgumentException("Invalid ${def.token}: " + this);'
          ],
        )
      ],
    );
  }

  String serializeFromJsonForEnum(GLEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    if (!_enumSanitized(def)) {
      def.addImport(JavaImports.optional);
      return codeGenUtils.createMethod(
        returnType: "public static ${def.token}",
        methodName: "fromJson",
        arguments: ["String value"],
        statements: [
          "return Optional.ofNullable(value).map(${def.token}::valueOf).orElse(null);"
        ],
      );
    }
    return codeGenUtils.createMethod(
      returnType: "public static ${def.token}",
      methodName: "fromJson",
      arguments: ["String value"],
      statements: [
        "if (value == null) return null;",
        codeGenUtils.switchStatement(
          expression: "value",
          cases: [
            ...def.values.map((v) => JavaCaseStatement(
                caseValue: '"${v.value.token}"',
                statement: 'return ${v.codeName};'))
          ],
          defaultStatements: [
            'throw new IllegalArgumentException("Invalid ${def.token}: " + value);'
          ],
        )
      ],
    );
  }

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.codeName;
    } else {
      return "$decorators ${value.codeName}";
    }
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField) {
    final type = def.type;
    final name = def.codeName;
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives);
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives(), joiner: "\n");
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("private ");
    if (immutable) {
      buffer.write("final ");
    }
    buffer.write('${serializeType(type, forceNullable)} $name');
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
    var name = arg.tokenInfo;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "${serializeType(type, false)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators$result";
    }
    return result;
  }

  String serializeArgumentField(GLField def,
      {bool withDecorators = false, String decoratorJoiner = "\n", bool isTypeField = false}) {
    final type = def.type;
    final name = def.codeName;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    final forceNullable = isTypeField
        ? (hasInculeOrSkipDiretives)
        : hasInculeOrSkipDiretives;
    final buffer = StringBuffer();
    if (withDecorators) {
      var decorators =
          serializeDecorators(def.getDirectives(), joiner: decoratorJoiner);
      if (decorators.trim().isNotEmpty) {
        buffer.write(decorators.trim());
        buffer.write(decoratorJoiner);
      }
    }
    buffer.write(serializeType(type, forceNullable));
    buffer.write(" ");
    buffer.write(name);
    return buffer.toString();
  }

  bool _isPrimitiveType(GLType type) {
    var serialized = serializeType(type, false);
    return _javaPrimitives.contains(serialized);
  }

  String serializeTypeReactive({
    required GLType glType,
    bool forceNullable = false,
    bool reactive = false,
    required GLToken? context,
  }) {
    if (glType is GLListType) {
      if (reactive) {
        context?.addImport(JavaImports.flux);
        final inlineType = glType.inlineType;
        return JavaCodeGenUtils.fluxOf(
            grammar, serializeTypeReactive(glType: inlineType, context: context));
      }
      context?.addImport(importList);
      return JavaCodeGenUtils.listOf(grammar, serializeType(glType.inlineType, false));
    }
    final token = glType.token;

    var type = getTypeNameFromGQExternal(token) ?? token;
    if (reactive) {
      context?.addImport(JavaImports.mono);
      return JavaCodeGenUtils.monoOf(grammar, type);
    }
    if (typeIsJavaPrimitive(type) && (glType.nullable || forceNullable)) {
      return convertPrimitiveToBoxed(type);
    }
    return type;
  }

  @override
  String serializeType(GLType def, bool forceNullable) {
    var token = def.token;
    var context = grammar.getTokenByKey(token);
    return serializeTypeReactive(
      context: context,
      glType: def,
      forceNullable: forceNullable,
      reactive: false,
    );
  }

  @override
  String doSerializeInputDefinition(GLInputDefinition def) {
    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (inputsAsRecords) {
      buffer.writeln(serializeRecord(def.token, def.fields, {}, def,
          extraStatements: generateMappingMethods(def)));
      return buffer.toString();
    }
    var class_ =
        codeGenUtils.createClass(className: def.tokenInfo.token, statements: [
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeField(e, immutableInputFields, false)),
      "",
      if (!immutableInputFields)
        generateContructor(def.token, [], "public", def,
            checkForNulls: inputsCheckForNulls),
      "",
      generateContructor(def.token, def.getSerializableFields(grammar.mode),
          immutableInputFields ? "public" : "private", def,
          checkForNulls: inputsCheckForNulls),
      generateBuilder(def.token, def.getSerializableFields(grammar.mode), true),
      ...def.getSerializableFields(grammar.mode).map(
          (e) => serializeGetter(e, def, checkForNulls: inputsCheckForNulls)),
      ...def.getSerializableFields(grammar.mode).where((field) {
        //check for the next directive here
        return !immutableInputFields;
      }).map(
          (e) => serializeSetter(e, def, checkForNulls: inputsCheckForNulls)),
      if (generateJsonMethods) ...[
        generateToJson(def.getSerializableFields(grammar.mode), def),
        generateFromJson(def.getSerializableFields(mode), def.token, def)
      ],
      ...generateMappingMethods(def),
    ]);
    buffer.write(class_);
    return buffer.toString();
  }

  bool _isNumber(GLType type) {
    if (type.isList) {
      return _isNumber(type.inlineType);
    }
    var serializedType = serializeType(type, false);
    return _javaNumbers.contains(serializedType);
  }

  String _numberValueMethod(GLType type) {
    if (type.isList) {
      return _numberValueMethod(type.inlineType);
    }
    return _javaNumberMethods[serializeType(type, false)]!;
  }

  String getFromJsonCall(
      GLField field, String varName, int depth, GLToken context,
      [GLType? type]) {
    type ??= field.type;
    String callMapDotGet = depth == 0 ? '.get("${field.name.token}")' : '';
    String nullCheckStatement =
        type.nullable ? '${varName}${callMapDotGet} == null ? null :' : '';

    if (type.isList) {
      var newVarName = '${varName}${depth}';
      var inlineType = type.inlineType;
      String targetCast;
      if (grammar.isNonProjectableType(inlineType.token) &&
          !grammar.isEnum(inlineType.token) &&
          !grammar.isInput(inlineType.token)) {
        targetCast = "(${_listOf('Object')})";
      } else if (grammar.isEnum(type.token)) {
        targetCast = "(${_listOf('Object')})";
      } else {
        targetCast = "(${_listOf('Object')})";
      }
      String mapFunction =
          'map(${newVarName} -> ${getFromJsonCall(field, newVarName, depth + 1, context, type.inlineType)})';
      var finalResult =
          '$nullCheckStatement (${targetCast}${varName}${callMapDotGet}).stream().${mapFunction}.${javaCollectorsToList}';
      context.addImport(JavaImports.collectors);
      return finalResult;
    }
    String result;
    if (grammar.isNonProjectableType(type.token) &&
        !grammar.isEnum(type.token) &&
        !grammar.isInput(type.token)) {
      if (_isNumber(type)) {
        result =
            '((Number)${varName}${callMapDotGet}).${_numberValueMethod(type)}';
      } else {
        result = '(${serializeType(type, false)})${varName}${callMapDotGet}';
      }
    } else if (grammar.isEnum(type.token)) {
      result = '${type.token}.fromJson((String)${varName}${callMapDotGet})';
    } else {
      result =
          '${type.token}.fromJson((${_mapOf('String', 'Object')})${varName}${callMapDotGet})';
    }
    return nullCheckStatement.isEmpty ? result : '$nullCheckStatement $result';
  }

  String generateFromJson(List<GLField> fields, String token, GLToken context) {
    var buffer = StringBuffer();

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: "public static ${token}",
          methodName: "fromJson",
          arguments: [
            '${_mapOf('String', 'Object')} json'
          ],
          statements: [
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
  String generateToMethod(
      GLInputDefinition def, String targetType, ToMappingPlan plan) {
    // Whether the source input and target type are records (affects accessor style).
    final targetIsRecord = typesAsRecords;

    final params = [
      ...plan.requiredParams.map(
        (f) => '${serializeType(f.targetField.type, false)} ${f.targetField.codeName}',
      ),
      ...plan.defaultParams.map(
        (f) => '${serializeType(f.targetField.type, false)} default${f.targetField.name.token.firstUp}',
      ),
    ];

    if ([...plan.requiredParams, ...plan.defaultParams].any((f) => f.targetField.type.isList)) {
      def.addImport(importList);
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
          final getter = _getterFieldName(f.sourceField!, true);
          constructorArgs.add(_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def));
        } else if (defaultByTarget.containsKey(name)) {
          final f = defaultByTarget[name]!;
          final getter = _getterFieldName(f.sourceField!, true);
          constructorArgs.add('$getter != null ? $getter : default${f.targetField.name.token.firstUp}');
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
        final getter = _getterFieldName(f.sourceField!, true);
        final expr = _toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def);
        return '.${f.targetField.codeName}($expr)';
      }),
      ...plan.defaultParams.map((f) {
        final getter = _getterFieldName(f.sourceField!, true);
        return '.${f.targetField.codeName}($getter != null ? $getter : default${f.targetField.name.token.firstUp})';
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
  String generateFromMethod(
      GLInputDefinition def, String targetType, FromMappingPlan plan) {
    final targetVar = targetType.firstLow;

    final nullableListDefaultParams = plan.nullableListDefaults.map((f) =>
        '${serializeType(f.sourceField!.type, false)} default${f.sourceField!.name.token.firstUp}');

    final promotedParams = plan.promoted.map(
      (f) => '${serializeType(f.sourceField!.type, false)} ${f.sourceField!.codeName}',
    );

    final inputOnlyParams = plan.inputOnly.map(
      (f) => '${serializeType(f.type, false)} ${f.codeName}',
    );

    if (plan.promoted.any((f) => f.sourceField!.type.isList) ||
        plan.inputOnly.any((f) => f.type.isList) ||
        plan.nullableListDefaults.isNotEmpty) {
      def.addImport(importList);
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
        final sourceExpr = '${targetVar}.${_getterFieldName(f.targetField, false)}';
        constructorArgs.add(_fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def));
      } else if (nullableListBySource.containsKey(fieldName)) {
        final f = nullableListBySource[fieldName]!;
        final sourceExpr = '${targetVar}.${_getterFieldName(f.targetField, false)}';
        final expr = _fromMappingExpr(sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        constructorArgs.add('$expr != null ? $expr : default${f.sourceField!.name.token.firstUp}');
      } else if (promotedNames.contains(fieldName) || inputOnlyNames.contains(fieldName)) {
        constructorArgs.add(field.codeName);
      }
    }

    return codeGenUtils.createMethod(
      returnType: 'public static ${def.token}',
      methodName: 'from${targetType.firstUp}',
      arguments: [
        '$targetType $targetVar',
        ...nullableListDefaultParams,
        ...promotedParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return new ${def.token}(',
        ...constructorArgs.asMap().entries.map(
              (e) => e.key < constructorArgs.length - 1 ? '${e.value},' : e.value,
            ),
        ');',
      ],
    );
  }

  /// Returns the Java expression for a toXxx() field assignment.
  /// Uses builder-chain suffix via stream().map().collect() for lists.
  String _toMappingExpr(
      String variable, GLType sourceType, GLType targetType, int index, GLToken context) {
    if (sourceType.isList) {
      if (sourceType.firstType.token == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _toMappingExpr(
          varName, sourceType.inlineType, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(
          receiver: variable, param: varName, body: inner, nullable: sourceType.nullable);
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      return JavaCodeGenUtils.safeCall(variable, 'to${targetType.token.firstUp}()', sourceType.nullable);
    }
    return variable; // same type — direct copy
  }

  /// Returns the Java expression for a fromXxx() field assignment.
  String _fromMappingExpr(
      String variable, String sourceElemToken, GLType targetType, int index, GLToken context) {
    if (targetType.isList) {
      if (sourceElemToken == targetType.firstType.token) {
        return variable; // same element type — pass directly
      }
      final varName = 'e$index';
      final inner = _fromMappingExpr(
          varName, sourceElemToken, targetType.inlineType, index + 1, context);
      context.addImport(JavaImports.collectors);
      return JavaCodeGenUtils.streamMapCollect(
          receiver: variable, param: varName, body: inner, nullable: targetType.nullable);
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      return JavaCodeGenUtils.nullSafeExpr(
          variable, '$sourceElemToken.from${targetType.token.firstUp}($variable)', targetType.nullable);
    }
    return variable; // same type — direct copy
  }


  String generateToJson(List<GLField> fields, GLToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: "public ${_mapOf('String', 'Object')}",
          methodName: "toJson",
          statements: [
            "${_mapOf('String', 'Object')} map = new HashMap<>();",
            ...fields.map((field) =>
                'map.put("${field.name}", ${_fieldToJson(field, context)});'),
            'return map;'
          ]),
    );

    return buffer.toString();
  }

  String _fieldToJson(GLField field, GLToken context) {
    var buffer = StringBuffer();
    var toJosnCall =
        callToJson(field, field.type, field.codeName, 0, context);
    buffer.write(toJosnCall);
    return buffer.toString();
  }



  String callToJson(GLField field, GLType type, String variableName, int index,
      GLToken context) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson =
          callToJson(field, inlineType, varName, index + 1, context);
      context.addImport(JavaImports.collectors);
      if (varName == inlineCallToJson) {
        return JavaCodeGenUtils.streamMapCollect(receiver: variableName, nullable: type.nullable);
      }
      return JavaCodeGenUtils.streamMapCollect(
          receiver: variableName, param: varName, body: inlineCallToJson, nullable: type.nullable);
    } else  if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return JavaCodeGenUtils.safeCall(variableName, "toJson()", type.nullable);
    }
    return variableName;
  }

  String generateContructor(
      String name, List<GLField> fields, String? modifier, GLToken context,
      {bool checkForNulls = false, bool isTypeField = false}) {
    String nullCheck = "";
    if (checkForNulls) {
      var checkingFields = fields
          .where((e) => !e.type.nullable && e.initialValue == null && !_isPrimitiveType(e.type))
          .map((e) => "Objects.requireNonNull(${e.codeName});")
          .toList();

      if (checkingFields.isNotEmpty) {
        nullCheck = serializeListText(checkingFields,
            join: "\n", withParenthesis: false);
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
      final hasListDefault = fields.any((e) =>
          !isTypeField && e.initialValue != null && e.type.isList);
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
    buffer.writeln(codeGenUtils
        .createClass(staticClass: true, className: 'Builder', statements: [
      ...fields.map((field) {
        final annotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
        final copy = GLField(name: field.name, type: field.type, arguments: field.arguments, directives: [])
          ..codeName = field.codeName;
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
          returnType: 'public $name',
          methodName: 'build',
          statements: [
            'return new $name(${fields.map((e) => e.codeName).join(", ")});'
          ]),
    ]));

    return buffer.toString();
  }

  String serializeGetter(GLField field, GLToken context,
      {bool checkForNulls = false, bool isTypeField = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    final forceNullable = isTypeField && (field.hasInculeOrSkipDiretives);
    var returnType = serializeType(field.type, forceNullable);
    var jspecifyAnnotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
    var result = codeGenUtils.createMethod(
        returnType: "public ${returnType}",
        methodName: _getterName(field.name.token, returnType == "boolean"),
        statements: [
          if (checkForNulls &&
              !field.type.nullable &&
              !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.codeName});',
          'return ${field.codeName};'
        ]);
        if(jspecifyAnnotation == null) {
          return result;
        }
        var buffer = StringBuffer();
        buffer.writeln(jspecifyAnnotation);
        buffer.write(result);
        return buffer.toString();
  }

  String? getJSpecifyAnnoation(GLField field) {
    var decorators = field.getDirectives(skipGenerated: false).where((e) => e.token == glDecorators).toList();
    if(decorators.isEmpty) {
      return null;
    }
    final directive = decorators.first;
    var value = directive.getArgValue("value");
    if(value is List<String>) {
      for(var v in value) {
        var vv = v.substring(1, v.length - 1);
        if(vv == jspecifyNonNull || vv == jspecifyNullable) {
          return vv;
        }
      }
    }
    return null;
  }

  String serializeMethod(GLField field, {String? modifier, bool forceNullable = false}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives());
    var args = serializeListText(
        field.arguments.map(serializeArgument).toList(),
        withParenthesis: false,
        join: ", ");
    var result =
        "${serializeType(field.type, forceNullable)} ${field.codeName}($args)";
    if (modifier != null) {
      result = "$modifier $result";
    }
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln(result);
    return result;
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
          if (generateJsonMethods) ...[
            generateToJson(fields, context),
            generateFromJson(fields, recordName, context)
          ],
          ...extraStatements,
        ]);
  }

  String serializeGetterDeclaration(GLField field,
      {bool skipModifier = false, bool asProperty = false, bool forceNullable = false}) {
    var returnType = serializeType(field.type, forceNullable);
    final type = field.type;
    if (type is GLListType) {
      returnType =
          JavaCodeGenUtils.listOf(grammar, serializeType(type.inlineType, false));
    }
    var result = returnType;
    if (asProperty) {
      result = "$result ${field.codeName}";
    } else {
      result =
          "$result ${_getterName(field.name.token, returnType == "boolean")}";
    }
    result = "$result()";
    if (skipModifier) {
      return result;
    }
    return "public $result";
  }

  String _setterName(String propertyName) {
    return _accessorName(propertyName, true, false);
  }

  String _getterName(String propertyName, bool isBoolean) {
    return _accessorName(propertyName, false, isBoolean);
  }

  String _getterFieldName(GLField field, bool forInput) {
     final name = field.name.token;
     bool isRecord = forInput && inputsAsRecords || !forInput && typesAsRecords;
     if(isRecord) {
      // Record accessor is the bare component name, so it must be the safe id.
      return "${field.codeName}()";
     }
    return '${_getterName(name, serializeType(field.type, !forInput) == "boolean")}()';

  }

  String _accessorName(String name, bool setter, bool isBoolean) {
    String prefix;
    if (setter) {
      prefix = "set";
    } else {
      if (isBoolean) {
        prefix = "is";
      } else {
        prefix = "get";
      }
    }
    return "$prefix${name.firstUp}";
  }

  String serializeSetter(GLField field, GLToken context,
      {bool checkForNulls = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    final annotation = _isPrimitiveType(field.type) ? null : getJSpecifyAnnoation(field);
    return codeGenUtils.createMethod(
        returnType: 'public void',
        methodName: _setterName(field.name.token),
        arguments: [
          '${annotation != null ? "$annotation " : ""}${serializeArgumentField(field)}'
        ],
        statements: [
          if (checkForNulls &&
              !field.type.nullable &&
              !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.codeName});',
          "this.${field.codeName} = ${field.codeName};"
        ]);
  }

  @override
  String doSerializeTypeDefinition(GLTypeDefinition def) {
    if (def is GLInterfaceDefinition) {
      // Internal interfaces always use JavaBean getter style regardless of typesAsRecords,
      // because their implementations are always classes (never records).
      final isInternal = def.getDirectiveByName(glInternal) != null;
      return serializeInterface(def,
          getters: def.getDirectiveByName(glInterfaceFieldAsProperties) == null,
          forceClassGetters: isInternal);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GLTypeDefinition def) {
    final token = def.tokenInfo;
    final interfaceNames = def.interfaceNames.map((e) => e.token).toSet();

    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (typesAsRecords && def.getDirectiveByName(glInternal) == null) {
      buffer
          .writeln(serializeRecord(def.token, def.fields, interfaceNames, def));
      return buffer.toString();
    }
    buffer.writeln(codeGenUtils.createClass(
        className: token.token,
        interfaceNames: interfaceNames.toList(),
        statements: [
          ...def
              .getSerializableFields(grammar.mode)
              .map((e) => serializeField(e, immutableTypeFields, true)),
          "",
          if (!immutableTypeFields)
            generateContructor(def.token, [], "public", def,
                checkForNulls: typesCheckForNulls, isTypeField: true),
          "",
          generateContructor(def.token, def.getSerializableFields(grammar.mode),
              immutableTypeFields ? "public" : "private", def, isTypeField: true),
          "",
          generateBuilder(
              def.token, def.getSerializableFields(grammar.mode), false),
          "",
          ...def.getSerializableFields(grammar.mode).map((e) =>
              serializeGetter(e, def, checkForNulls: typesCheckForNulls, isTypeField: true)),
          "",
          ...def.getSerializableFields(grammar.mode).where((field) {
            // @TODO check for mutable directive
            return !immutableTypeFields;
          }).map((e) =>
              serializeSetter(e, def, checkForNulls: typesCheckForNulls)),
          generateEqualsAndHashCode(def),
          if (generateJsonMethods) ...[
            generateFromJson(
                def.getSerializableFields(grammar.mode), def.token, def),
            generateToJson(def.getSerializableFields(grammar.mode), def)
          ]
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
    final token = def.tokenInfo;
    def.addImport("java.util.Objects");
    var buffer = StringBuffer();
    buffer.writeln('@Override');
    buffer.writeln(codeGenUtils.createMethod(
        returnType: "public boolean",
        methodName: "equals",
        arguments: [
          'Object o'
        ],
        statements: [
          codeGenUtils.ifStatement(
              condition: '!(o instanceof $token)',
              ifBlockStatements: ['return false;']),
          '$token o2 = ($token) o;',
          'return ${fields.map((e) => "Objects.equals($e, o2.$e);").join(" && ")}'
        ]));

    buffer.writeln();
    buffer.writeln('@Override');

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: 'public int',
          methodName: 'hashCode',
          statements: ['return Objects.hash(${fields.join(", ")});']),
    );

    return buffer.toString();
  }

  String _serializeInterfaceField(GLField f, bool getters,
      {bool forceClassGetters = false}) {
    var buffer = StringBuffer();
    var fieldDecorators = serializeDecorators(f.getDirectives(), joiner: "\n");
    if (fieldDecorators.isNotEmpty) {
      buffer.writeln(fieldDecorators.trim().ident());
    }
    final fieldForceNullable = f.hasInculeOrSkipDiretives;
    if (getters) {
      if (typesAsRecords && !forceClassGetters) {
        buffer.write(
            serializeGetterDeclaration(f, skipModifier: true, asProperty: true, forceNullable: fieldForceNullable)
                .ident());
      } else {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, forceNullable: fieldForceNullable).ident());
      }
    } else {
      buffer.write(serializeMethod(f, forceNullable: fieldForceNullable).ident());
    }
    buffer.write(";");
    return buffer.toString();
  }

  String serializeInterface(GLInterfaceDefinition interface,
      {required bool getters, bool forceClassGetters = false}) {
    final token = interface.tokenInfo;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var decorators = serializeDecorators(interface.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    bool generateJsonConverstionMethods = generateJsonMethods &&
        interface.getDirectiveByName(glInterfaceFieldAsProperties) == null;
    if (generateJsonConverstionMethods) {
      interface.addImport(JavaImports.map);
    }
    buffer.writeln(codeGenUtils.createInterface(
        interfaceName: token.token,
        interfaceNames: interfaces.map((e) => e.tokenInfo.token).toList(),
        statements: [
          ...fields.map((f) => _serializeInterfaceField(f, getters, forceClassGetters: forceClassGetters)),
          if (generateJsonConverstionMethods && interface.getSerializableImplementations(mode).isNotEmpty) ...[
            "",
            "Map<String, Object> toJson();",
            _serializeFromJsonForInterface(
                interface.token, interface.getSerializableImplementations(mode))
          ]
        ]));
    return buffer.toString();
  }

  String _serializeFromJsonForInterface(
      String token, Set<GLTypeDefinition> subTypes) {
    if (subTypes.isEmpty || !generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer(
        "static ${token} fromJson(${_mapOf("String", "Object")} json) {");
    buffer.writeln();

    buffer.writeln('String typename = (String)json.get("__typename");'.ident());
    buffer.writeln("switch(typename) {".ident());
    for (var st in subTypes) {
      String typeNameValue =
          st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      String currentToken = st.tokenInfo.token;
      buffer.writeln(
          'case "${typeNameValue}": return ${currentToken}.fromJson(json);'
              .ident(2));
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
    return "${token.token}.java";
  }

  @override
  String serializeImportToken(GLToken token) {
    String? path;

    if (grammar.enums.containsKey(token.token)) {
      path = "enums.${token.token}";
    } else if (grammar.interfaces.containsKey(token.token) ||
        grammar.projectedInterfaces.containsKey(token.token)) {
      path = "interfaces.${token.token}";
    } else if (grammar.types.containsKey(token.token) ||
        grammar.projectedTypes.containsKey(token.token)) {
      path = "types.${token.token}";
    } else if (grammar.inputs.containsKey(token.token)) {
      path = "inputs.${token.token}";
    } else if (grammar.services.containsKey(token.token)) {
      path = "services.${token.token}";
    } else if (grammar.controllers.containsKey(token.token)) {
      path = "controllers.${token.token}";
    }
    return "import ${importPrefix}.${path};";
  }

  @override
  String serializeImport(String import) {
    if (import == importList) {
      return 'import ${JavaImports.list};';
    }
    return 'import ${import};';
  }

  @override
  String serializeGlClass(GLClassModel theClass,
      {bool withImports = true}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports);
    }
    final tokenImports = theClass.importDepencies
        .map((dep) => serializeImportToken(dep))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports);
  }
}
