import 'package:graphlink/src/constants.dart';
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
  final codeGenUtils = JavaCodeGenUtils();
  @override
  final bool generateJsonMethods;
  JavaSerializer(
    super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false,
    this.generateJsonMethods = false,
    this.typesCheckForNulls = false,
    this.inputsCheckForNulls = true,
    this.immutableInputFields = true,
    this.immutableTypeFields = false,
  }) {
    _initAnnotations();
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

  String serializeToJsonForEnum(GLEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    return codeGenUtils.createMethod(
      returnType: "public String",
      methodName: "toJson",
      statements: ["return name();"],
    );
  }

  String serializeFromJsonForEnum(GLEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
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

  @override
  String doSerializeEnumValue(GLEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.value.token;
    } else {
      return "$decorators ${value.value.token}";
    }
  }

  @override
  String doSerializeField(GLField def, bool immutable, bool isTypeField) {
    final type = def.type;
    final name = def.name;
    final forceNullable = isTypeField && (def.hasInculeOrSkipDiretives || forceFieldNullable);
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives(), joiner: "\n");
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("private ");
    if (immutable) {
      buffer.write("final ");
    }
    buffer.write('${serializeType(type, forceNullable)} $name;');
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
      {bool withDecorators = false, String decoratorJoiner = "\n"}) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    final buffer = StringBuffer();
    if (withDecorators) {
      var decorators =
          serializeDecorators(def.getDirectives(), joiner: decoratorJoiner);
      if (decorators.trim().isNotEmpty) {
        buffer.write(decorators);
        buffer.write(decoratorJoiner);
      }
    }
    buffer.write(
        serializeType(type, hasInculeOrSkipDiretives));
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
        return "Flux<${convertPrimitiveToBoxed(serializeTypeReactive(glType: glType.inlineType, context: context))}>";
      }
      context?.addImport(importList);
        return _listOf(
            convertPrimitiveToBoxed(serializeType(glType.inlineType, false)));
    }
    final token = glType.token;

    var type = getTypeNameFromGQExternal(token) ?? token;
    if (reactive) {
      context?.addImport(JavaImports.mono);
      return "Mono<${convertPrimitiveToBoxed(type)}>";
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
      GLInputDefinition def, String targetType, MappingPlan plan) {
    // Whether the source input and target type are records (affects accessor style).
    final sourceIsRecord = inputsAsRecords;
    final targetIsRecord = typesAsRecords;

    final params = [
      ...plan.requiredParams.map(
        (f) => '${serializeType(f.targetField.type, false)} ${f.targetField.name.token}',
      ),
      ...plan.defaultParams.map(
        (f) => '${serializeType(f.targetField.type, false)} default${f.targetField.name.token.firstUp}',
      ),
    ];

    // Source accessor: records use field(), classes use getField().
    String sourceAccessor(String fieldName) => sourceIsRecord
        ? '$fieldName()'
        : '${_getterName(fieldName, false)}()';

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
          final getter = sourceAccessor(f.sourceField!.name.token);
          constructorArgs.add(_toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def));
        } else if (defaultByTarget.containsKey(name)) {
          final f = defaultByTarget[name]!;
          final getter = sourceAccessor(f.sourceField!.name.token);
          constructorArgs.add('$getter != null ? $getter : default${f.targetField.name.token.firstUp}');
        } else if (requiredByTarget.containsKey(name)) {
          constructorArgs.add(name);
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
        final getter = sourceAccessor(f.sourceField!.name.token);
        final expr = _toMappingExpr(getter, f.sourceField!.type, f.targetField.type, 0, def);
        return '.${f.targetField.name.token}($expr)';
      }),
      ...plan.defaultParams.map((f) {
        final getter = sourceAccessor(f.sourceField!.name.token);
        return '.${f.targetField.name.token}($getter != null ? $getter : default${f.targetField.name.token.firstUp})';
      }),
      ...plan.requiredParams.map(
        (f) => '.${f.targetField.name.token}(${f.targetField.name.token})',
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
      GLInputDefinition def, String targetType, MappingPlan plan) {
    final allMapped = [...plan.autoMapped, ...plan.defaultParams];

    final elementMismatch = allMapped
        .where((f) => _hasElementNullabilityMismatch(f.sourceField!.type, f.targetField.type))
        .toList();
    final autoMappable = allMapped
        .where((f) => !_hasElementNullabilityMismatch(f.sourceField!.type, f.targetField.type))
        .toList();

    final autoMappableBySource = {
      for (final f in autoMappable) f.sourceField!.name.token: f
    };
    final elementMismatchNames = {
      for (final f in elementMismatch) f.sourceField!.name.token
    };

    final targetVar = targetType.firstLow;

    final nullableListDefaultParams = autoMappable
        .where((f) =>
            f.targetField.type.nullable &&
            !f.sourceField!.type.nullable &&
            f.sourceField!.type.isList)
        .map((f) =>
            '${serializeType(f.sourceField!.type, false)} default${f.sourceField!.name.token.firstUp}');

    final elementMismatchParams = elementMismatch.map(
      (f) => '${serializeType(f.sourceField!.type, false)} ${f.sourceField!.name.token}',
    );

    final inputOnlyParams = plan.inputOnlyFields.map(
      (f) => '${serializeType(f.type, false)} ${f.name.token}',
    );

    // Build positional constructor args in field declaration order.
    final fields = def.getSerializableFields(grammar.mode);
    final constructorArgs = <String>[];
    for (final field in fields) {
      final fieldName = field.name.token;
      if (autoMappableBySource.containsKey(fieldName)) {
        final f = autoMappableBySource[fieldName]!;
        final targetFieldName = f.targetField.name.token;
        final sourceExpr = typesAsRecords
            ? '$targetVar.$targetFieldName()'
            : '$targetVar.${_getterName(targetFieldName, false)}()';
        var expr = _fromMappingExpr(
            sourceExpr, f.sourceField!.type.firstType.token, f.targetField.type, 0, def);
        if (f.targetField.type.nullable &&
            !f.sourceField!.type.nullable &&
            f.sourceField!.type.isList) {
          expr = '$expr != null ? $expr : default${f.sourceField!.name.token.firstUp}';
        }
        constructorArgs.add(expr);
      } else if (elementMismatchNames.contains(fieldName)) {
        constructorArgs.add(fieldName);
      } else {
        // input-only field — taken from parameter
        constructorArgs.add(fieldName);
      }
    }

    return codeGenUtils.createMethod(
      returnType: 'public static ${def.token}',
      methodName: 'from${targetType.firstUp}',
      arguments: [
        '$targetType $targetVar',
        ...nullableListDefaultParams,
        ...elementMismatchParams,
        ...inputOnlyParams,
      ],
      statements: [
        'return new ${def.token}(',
        ...constructorArgs.asMap().entries.map(
              (e) => e.key < constructorArgs.length - 1
                  ? '${e.value},'
                  : e.value,
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
      final streamExpr =
          '$variable.stream().map($varName -> $inner).collect(Collectors.toList())';
      if (sourceType.nullable) {
        return '$variable == null ? null : $streamExpr';
      }
      return streamExpr;
    }
    final sourceInput = grammar.inputs[sourceType.token];
    if (sourceInput?.mapsToType == targetType.token) {
      if (sourceType.nullable) {
        return '$variable == null ? null : $variable.to${targetType.token.firstUp}()';
      }
      return '$variable.to${targetType.token.firstUp}()';
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
      final streamExpr =
          '$variable.stream().map($varName -> $inner).collect(Collectors.toList())';
      if (targetType.nullable) {
        return '$variable == null ? null : $streamExpr';
      }
      return streamExpr;
    }
    final sourceInput = grammar.inputs[sourceElemToken];
    if (sourceInput?.mapsToType == targetType.token) {
      if (targetType.nullable) {
        return '$variable == null ? null : $sourceElemToken.from${targetType.token.firstUp}($variable)';
      }
      return '$sourceElemToken.from${targetType.token.firstUp}($variable)';
    }
    return variable; // same type — direct copy
  }

  /// Returns true if [targetType] contains a nullable element at any list depth
  /// where the corresponding [sourceType] element is non-null.
  bool _hasElementNullabilityMismatch(GLType sourceType, GLType targetType) {
    if (!sourceType.isList || !targetType.isList) return false;
    final sourceElem = sourceType.inlineType;
    final targetElem = targetType.inlineType;
    if (targetElem.nullable && !sourceElem.nullable) return true;
    return _hasElementNullabilityMismatch(sourceElem, targetElem);
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
        callToJson(field, field.type, field.name.token, 0, context);
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
      String method;
        if (varName == inlineCallToJson) {
          method = "stream().${javaCollectorsToList}";
        } else {
          method = "stream().map(${varName} -> ${inlineCallToJson}).${javaCollectorsToList}";
        }
        context.addImport(JavaImports.collectors);
        return JavaCodeGenUtils.safeCall(variableName, method, type.nullable);
      
    } else  if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return JavaCodeGenUtils.safeCall(variableName, "toJson()", type.nullable);
    }
    return variableName;
  }

  String generateContructor(
      String name, List<GLField> fields, String? modifier, GLToken context,
      {bool checkForNulls = false}) {
    String nullCheck = "";
    if (checkForNulls) {
      var checkingFields = fields
          .where((e) => !e.type.nullable && !_isPrimitiveType(e.type))
          .map((e) => "Objects.requireNonNull(${e.name});")
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
        "$name(${serializeListText(fields.map((e) => serializeArgumentField(e)).toList(), join: ", ", withParenthesis: false)}) {");
    if (nullCheck.isNotEmpty) {
      buffer.writeln(nullCheck.ident());
    }
    if (fields.isNotEmpty) {
      buffer.writeln(serializeListText(
              fields.map((e) => "this.${e.name} = ${e.name};").toList(),
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
      ...fields
          .map((field) => GLField(
              name: field.name,
              type: field.type,
              arguments: field.arguments,
              directives: []))
          .map((field) => serializeField(field, false, !forInput)),
      "",
      ...fields.map((e) => codeGenUtils.createMethod(
          returnType: 'public Builder',
          methodName: e.name.token,
          arguments: [serializeArgumentField(e)],
          statements: ['this.${e.name} = ${e.name};', 'return this;'])),
      "",
      codeGenUtils.createMethod(
          returnType: 'public $name',
          methodName: 'build',
          statements: [
            'return new $name(${fields.map((e) => e.name).join(", ")});'
          ]),
    ]));

    return buffer.toString();
  }

  String serializeGetter(GLField field, GLToken context,
      {bool checkForNulls = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    var returnType = serializeType(field.type, false);
    return codeGenUtils.createMethod(
        returnType: "public ${returnType}",
        methodName: _getterName(field.name.token, returnType == "boolean"),
        statements: [
          if (checkForNulls &&
              !field.type.nullable &&
              !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.name});',
          'return ${field.name};'
        ]);
  }

  String serializeMethod(GLField field, {String? modifier}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives());
    var args = serializeListText(
        field.arguments.map(serializeArgument).toList(),
        withParenthesis: false,
        join: ", ");
    var result =
        "${serializeType(field.type, false)} ${field.name}($args)";
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
        components: fields
            .map((f) => serializeArgumentField(f,
                withDecorators: true, decoratorJoiner: " "))
            .toList(),
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
      {bool skipModifier = false, bool asProperty = false}) {
    var returnType = serializeType(field.type, false);
    var result = serializeType(field.type, false);
    if (asProperty) {
      result = "$result ${field.name}";
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
    return codeGenUtils.createMethod(
        returnType: 'public void',
        methodName: _setterName(field.name.token),
        arguments: [
          serializeArgumentField(field)
        ],
        statements: [
          if (checkForNulls &&
              !field.type.nullable &&
              !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.name});',
          "this.${field.name} = ${field.name};"
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
                checkForNulls: typesCheckForNulls),
          "",
          generateContructor(def.token, def.getSerializableFields(grammar.mode),
              immutableTypeFields ? "public" : "private", def),
          "",
          generateBuilder(
              def.token, def.getSerializableFields(grammar.mode), false),
          "",
          ...def.getSerializableFields(grammar.mode).map((e) =>
              serializeGetter(e, def, checkForNulls: typesCheckForNulls)),
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
    if (getters) {
      if (typesAsRecords && !forceClassGetters) {
        buffer.write(
            serializeGetterDeclaration(f, skipModifier: true, asProperty: true)
                .ident());
      } else {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true).ident());
      }
    } else {
      buffer.write(serializeMethod(f).ident());
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
          if (generateJsonConverstionMethods) ...[
            "",
            "Map<String, Object> toJson();",
            _serializeFromJsonForInterface(
                interface.token, interface.implementations)
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
  String serializeImportToken(GLToken token, String importPrefix) {
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
      {bool withImports = true, required String importPrefix}) {
    if (!withImports || theClass.importDepencies.isEmpty && theClass.imports.isEmpty) {
      return super.serializeGlClass(theClass, withImports: withImports, importPrefix: importPrefix);
    }
    final tokenImports = theClass.importDepencies
        .map((dep) => serializeImportToken(dep, importPrefix))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final simpleImports = theClass.imports.map((imp) => serializeImport(imp)).toList();
    final merged = GLClassModel(
      imports: {...tokenImports, ...simpleImports}.toList(),
      body: theClass.body,
    );
    return super.serializeGlClass(merged, withImports: withImports, importPrefix: importPrefix);
  }
}
