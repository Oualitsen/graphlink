import 'package:retrofit_graphql/src/code_gen_utils.dart';
import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/utils.dart';

const _toList = "collect(Collectors.toList())";
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

class JavaSerializer extends GqSerializer {
  final bool inputsAsRecords;
  final bool typesAsRecords;
  final bool typesCheckForNulls;
  final bool inputsCheckForNulls;
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
  }) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations(
        (val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  String serializeAnnotation(GQDirectiveValue value) {
    return AnnotationSerializer.serializeAnnotation(value, multiLineString: false);
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
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
        methods: [if (fromJson.isNotEmpty) fromJson, if (toJson.isNotEmpty) toJson]);
    buffer.writeln(enum_);
    return buffer.toString();
  }

  String serializeToJsonForEnum(GQEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    return codeGenUtils.createMethod(
      returnType: "public String",
      methodName: "toJson",
      statements: ["return name();"],
    );
  }

  String serializeFromJsonForEnum(GQEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    def.addImport(JavaImports.optional);
    return codeGenUtils.createMethod(
      returnType: "public static ${def.token}",
      methodName: "fromJson",
      arguments: ["String value"],
      statements: ["return Optional.ofNullable(value).map(${def.token}::valueOf).orElse(null);"],
    );
  }

  @override
  String doSerializeEnumValue(GQEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.value.token;
    } else {
      return "$decorators ${value.value.token}";
    }
  }

  @override
  String doSerializeField(GQField def) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives(), joiner: "\n");
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write(
        'private ${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name;');
    return buffer.toString();
  }

  String serializeArgument(GQArgumentDefinition arg) {
    var type = arg.type;
    var name = arg.tokenInfo;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "${serializeType(type, false)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators$result";
    }
    return result;
  }

  String serializeArgumentField(GQField def,
      {bool withDecorators = false, String decoratorJoiner = "\n"}) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    final buffer = StringBuffer();
    if (withDecorators) {
      var decorators = serializeDecorators(def.getDirectives(), joiner: decoratorJoiner);
      if (decorators.trim().isNotEmpty) {
        buffer.write(decorators);
        buffer.write(decoratorJoiner);
      }
    }
    buffer.write(serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray));
    buffer.write(" ");
    buffer.write(name);
    return buffer.toString();
  }

  bool _isPrimitiveType(GQType type) {
    var serialized = serializeType(type, false);
    return _javaPrimitives.contains(serialized);
  }

  String serializeTypeReactive({
    required GQType gqType,
    bool forceNullable = false,
    bool asArray = false,
    bool reactive = false,
    required GQToken? context,
  }) {
    if (gqType is GQListType) {
      if (reactive) {
        context?.addImport(JavaImports.flux);
        return "Flux<${convertPrimitiveToBoxed(serializeTypeReactive(gqType: gqType.inlineType, context: context))}>";
      }
      if (asArray) {
        return "${serializeType(gqType.inlineType, false, asArray)}[]";
      } else {
        context?.addImport(importList);
        return _listOf(convertPrimitiveToBoxed(serializeType(gqType.inlineType, false)));
      }
    }
    final token = gqType.token;

    var type = getTypeNameFromGQExternal(token) ?? token;
    if (reactive) {
      context?.addImport(JavaImports.mono);
      return "Mono<${convertPrimitiveToBoxed(type)}>";
    }
    if (typeIsJavaPrimitive(type) && (gqType.nullable || forceNullable)) {
      return convertPrimitiveToBoxed(type);
    }
    return type;
  }

  @override
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]) {
    var token = def.token;
    var context = grammar.getTokenByKey(token);
    return serializeTypeReactive(
      context: context,
      gqType: def,
      forceNullable: forceNullable,
      asArray: asArray,
      reactive: false,
    );
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def) {
    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (inputsAsRecords) {
      buffer.writeln(serializeRecord(def.token, def.fields, {}, def));
      return buffer.toString();
    }
    var class_ = codeGenUtils.createClass(className: def.tokenInfo.token, statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e)),
      "",
      generateContructor(def.token, [], "public", def, checkForNulls: inputsCheckForNulls),
      "",
      generateContructor(def.token, def.getSerializableFields(grammar.mode), "private", def,
          checkForNulls: inputsCheckForNulls),
      generateBuilder(def.token, def.getSerializableFields(grammar.mode)),
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeGetter(e, def, checkForNulls: inputsCheckForNulls)),
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeSetter(e, def, checkForNulls: inputsCheckForNulls)),
      if (generateJsonMethods) ...[
        generateToJson(def.getSerializableFields(grammar.mode), def),
        generateFromJson(def.getSerializableFields(mode), def.token, def)
      ]
    ]);
    buffer.write(class_);
    return buffer.toString();
  }

  bool _isNumber(GQType type) {
    if (type.isList) {
      return _isNumber(type.inlineType);
    }
    var serializedType = serializeType(type, false);
    return _javaNumbers.contains(serializedType);
  }

  String _numberValueMethod(GQType type) {
    if (type.isList) {
      return _numberValueMethod(type.inlineType);
    }
    return _javaNumberMethods[serializeType(type, false)]!;
  }

  String getFromJsonCall(GQField field, String varName, int depth, GQToken context,
      [GQType? type]) {
    type ??= field.type;
    String callMapDotGet = depth == 0 ? '.get("${field.name.token}")' : '';
    String nullCheckStatement = type.nullable ? '${varName}${callMapDotGet} == null ? null :' : '';

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
          '$nullCheckStatement (${targetCast}${varName}${callMapDotGet}).stream().${mapFunction}.${_toList}';
      context.addImport(JavaImports.collectors);
      return finalResult;
    }
    String result;
    if (grammar.isNonProjectableType(type.token) &&
        !grammar.isEnum(type.token) &&
        !grammar.isInput(type.token)) {
      if (_isNumber(type)) {
        result = '((Number)${varName}${callMapDotGet}).${_numberValueMethod(type)}';
      } else {
        result = '(${serializeType(type, false)})${varName}${callMapDotGet}';
      }
    } else if (grammar.isEnum(type.token)) {
      result = '${type.token}.fromJson((String)${varName}${callMapDotGet})';
    } else {
      result = '${type.token}.fromJson((${_mapOf('String', 'Object')})${varName}${callMapDotGet})';
    }
    return nullCheckStatement.isEmpty ? result : '$nullCheckStatement $result';
  }

  String generateFromJson(List<GQField> fields, String token, GQToken context) {
    var buffer = StringBuffer();

    buffer.writeln(
      codeGenUtils
          .createMethod(returnType: "public static ${token}", methodName: "fromJson", arguments: [
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

  String generateToJson(List<GQField> fields, GQToken context) {
    var buffer = StringBuffer();
    context.addImport(JavaImports.hashMap);
    context.addImport(JavaImports.map);

    buffer.writeln(
      codeGenUtils.createMethod(
          returnType: "public ${_mapOf('String', 'Object')}",
          methodName: "toJson",
          statements: [
            "${_mapOf('String', 'Object')} map = new HashMap<>();",
            ...fields.map((field) => 'map.put("${field.name}", ${fieldToJson(field, context)});'),
            'return map;'
          ]),
    );

    return buffer.toString();
  }

  String fieldToJson(GQField field, GQToken context) {
    var buffer = StringBuffer();
    var toJosnCall = callToJson(field, field.type, field.name.token, 0, context);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String safeCall(String variable, String method, bool nullable) {
    if (nullable) {
      return "$variable == null ? null : ${variable}.${method}";
    }
    return "${variable}.${method}";
  }

  String callToJson(GQField field, GQType type, String variableName, int index, GQToken context) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson = callToJson(field, inlineType, varName, index + 1, context);
      if (field.getDirectiveByName(gqArray) != null) {
        // array
        String method =
            "Stream.of(${variableName}).map(${varName} -> ${inlineCallToJson}).${_toList}";
        context.addImport(JavaImports.stream);
        return "${variableName} == null ? null : $method";
      } else {
        // list

        String method;
        if (varName == inlineCallToJson) {
          method = "stream().${_toList}";
        } else {
          method = "stream().map(${varName} -> ${inlineCallToJson}).${_toList}";
        }
        context.addImport(JavaImports.collectors);

        return safeCall(variableName, method, type.nullable);
      }
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return safeCall(variableName, "toJson()", type.nullable);
    }
    return variableName;
  }

  String generateContructor(String name, List<GQField> fields, String? modifier, GQToken context,
      {bool checkForNulls = false}) {
    String nullCheck = "";
    if (checkForNulls) {
      var checkingFields = fields
          .where((e) => !e.type.nullable && !_isPrimitiveType(e.type))
          .map((e) => "Objects.requireNonNull(${e.name});")
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
        "$name(${serializeListText(fields.map((e) => serializeArgumentField(e)).toList(), join: ", ", withParenthesis: false)}) {");
    if (nullCheck.isNotEmpty) {
      buffer.writeln(nullCheck.ident());
    }
    if (fields.isNotEmpty) {
      buffer.writeln(serializeListText(fields.map((e) => "this.${e.name} = ${e.name};").toList(),
              join: "\n", withParenthesis: false)
          .ident());
    }
    buffer.writeln("}");
    return buffer.toString();
  }

  String generateBuilder(String name, List<GQField> fields) {
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
      ...fields
          .map((field) => GQField(
              name: field.name, type: field.type, arguments: field.arguments, directives: []))
          .map(serializeField),
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
          statements: ['return new $name(${fields.map((e) => e.name).join(", ")});']),
    ]));

    return buffer.toString();
  }

  String serializeGetter(GQField field, GQToken context, {bool checkForNulls = false}) {
    if (checkForNulls) {
      context.addImport(JavaImports.objects);
    }
    var returnType = serializeType(field.type, false, field.serialzeAsArray);
    return codeGenUtils.createMethod(
        returnType: "public ${returnType}",
        methodName: _getterName(field.name.token, returnType == "boolean"),
        statements: [
          if (checkForNulls && !field.type.nullable && !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.name});',
          'return ${field.name};'
        ]);
  }

  String serializeMethod(GQField field, {String? modifier}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives());
    var args = serializeListText(field.arguments.map(serializeArgument).toList(),
        withParenthesis: false, join: ", ");
    var result = "${serializeType(field.type, false, field.serialzeAsArray)} ${field.name}($args)";
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
    List<GQField> fields,
    Set<String> interfaceNames,
    GQToken context,
  ) {
    return codeGenUtils.createRecord(
        recordName: recordName,
        components: fields
            .map((f) => serializeArgumentField(f, withDecorators: true, decoratorJoiner: " "))
            .toList(),
        interfaces: interfaceNames.toList(),
        statements: [
          if (generateJsonMethods) ...[
            generateToJson(fields, context),
            generateFromJson(fields, recordName, context)
          ]
        ]);
  }

  String serializeGetterDeclaration(GQField field,
      {bool skipModifier = false, bool asProperty = false}) {
    var returnType = serializeType(field.type, false);
    var result = serializeType(field.type, false, field.serialzeAsArray);
    if (asProperty) {
      result = "$result ${field.name}";
    } else {
      result = "$result ${_getterName(field.name.token, returnType == "boolean")}";
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

  String serializeSetter(GQField field, GQToken context, {bool checkForNulls = false}) {
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
          if (checkForNulls && !field.type.nullable && !_isPrimitiveType(field.type))
            'Objects.requireNonNull(${field.name});',
          "this.${field.name} = ${field.name};"
        ]);
  }

  @override
  String doSerializeTypeDefinition(GQTypeDefinition def) {
    if (def is GQInterfaceDefinition) {
      return serializeInterface(def,
          getters: def.getDirectiveByName(gqInterfaceFieldAsProperties) == null);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GQTypeDefinition def) {
    final token = def.tokenInfo;
    final interfaceNames = def.interfaceNames.map((e) => e.token).toSet();

    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (typesAsRecords) {
      buffer.writeln(serializeRecord(def.token, def.fields, interfaceNames, def));
      return buffer.toString();
    }
    buffer.writeln(codeGenUtils
        .createClass(className: token.token, interfaceNames: interfaceNames.toList(), statements: [
      ...def.getSerializableFields(grammar.mode).map((e) => serializeField(e)),
      "",
      generateContructor(def.token, [], "public", def, checkForNulls: typesCheckForNulls),
      "",
      generateContructor(def.token, def.getSerializableFields(grammar.mode), "private", def),
      "",
      generateBuilder(def.token, def.getSerializableFields(grammar.mode)),
      "",
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeGetter(e, def, checkForNulls: typesCheckForNulls)),
      "",
      ...def
          .getSerializableFields(grammar.mode)
          .map((e) => serializeSetter(e, def, checkForNulls: typesCheckForNulls)),
      generateEqualsAndHashCode(def),
      if (generateJsonMethods) ...[
        generateFromJson(def.getSerializableFields(grammar.mode), def.token, def),
        generateToJson(def.getSerializableFields(grammar.mode), def)
      ]
    ]));
    return buffer.toString();
  }

  String generateEqualsAndHashCode(GQTypeDefinition def) {
    var fieldsToInclude = def.getIdentityFields(grammar);
    if (fieldsToInclude.isNotEmpty) {
      return equalsHascodeCode(def, fieldsToInclude);
    }
    return "";
  }

  String equalsHascodeCode(GQTypeDefinition def, Set<String> fields) {
    final token = def.tokenInfo;
    def.addImport("java.util.Objects");
    var buffer = StringBuffer();
    buffer.writeln('@Override');
    buffer.writeln(
        codeGenUtils.createMethod(returnType: "public boolean", methodName: "equals", arguments: [
      'Object o'
    ], statements: [
      codeGenUtils
          .ifStatement(condition: '!(o instanceof $token)', ifBlockStatements: ['return false;']),
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

  String _serializeInterfaceField(GQField f, bool getters) {
    var buffer = StringBuffer();
    var fieldDecorators = serializeDecorators(f.getDirectives(), joiner: "\n");
    if (fieldDecorators.isNotEmpty) {
      buffer.writeln(fieldDecorators.trim().ident());
    }
    if (getters) {
      if (typesAsRecords) {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, asProperty: true).ident());
      } else {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true).ident());
      }
    } else {
      buffer.write(serializeMethod(f).ident());
    }
    buffer.write(";");
    return buffer.toString();
  }

  String serializeInterface(GQInterfaceDefinition interface, {required bool getters}) {
    final token = interface.tokenInfo;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var decorators = serializeDecorators(interface.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    bool generateJsonConverstionMethods =
        generateJsonMethods && interface.getDirectiveByName(gqInterfaceFieldAsProperties) == null;
    if (generateJsonConverstionMethods) {
      interface.addImport(JavaImports.map);
    }
    buffer.writeln(codeGenUtils.createInterface(
        interfaceName: token.token,
        interfaceNames: interfaces.map((e) => e.tokenInfo.token).toList(),
        statements: [
          ...fields.map((f) => _serializeInterfaceField(f, getters)),
          if (generateJsonConverstionMethods) ...[
            "",
            "Map<String, Object> toJson();",
            _serializeFromJsonForInterface(interface.token, interface.implementations)
          ]
        ]));
    return buffer.toString();
  }

  String _serializeFromJsonForInterface(String token, Set<GQTypeDefinition> subTypes) {
    if (subTypes.isEmpty || !generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer("static ${token} fromJson(${_mapOf("String", "Object")} json) {");
    buffer.writeln();

    buffer.writeln('String typename = (String)json.get("__typename");'.ident());
    buffer.writeln("switch(typename) {".ident());
    for (var st in subTypes) {
      String typeNameValue = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      String currentToken = st.tokenInfo.token;
      buffer.writeln('case "${typeNameValue}": return ${currentToken}.fromJson(json);'.ident(2));
    }
    buffer.writeln(
        'default: throw new RuntimeException(String.format("Invalid type %s. %s does not implement $token or not defined", typename, typename));'
            .ident(2));
    buffer.writeln("}".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  @override
  String getFileNameFor(GQToken token) {
    return "${token.token}.java";
  }

  @override
  String serializeImportToken(GQToken token, String importPrefix) {
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
}
