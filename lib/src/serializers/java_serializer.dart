import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
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
    grammar.handleAnnotations((val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln("public enum ${def.tokenInfo} {");
    buffer.write(def.values.map((e) => doSerializeEnumValue(e)).toList().join(", ").ident());
    buffer.writeln(";");
    var toJson = serializeToJsonForEnum(def);
    if (toJson.isNotEmpty) {
      buffer.writeln(toJson.ident());
    }

    var fromJson = serializeFromJsonForEnum(def);
    if (fromJson.isNotEmpty) {
      buffer.writeln(fromJson.ident());
    }
    buffer.writeln("}");
    return buffer.toString();
  }

  String serializeToJsonForEnum(GQEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer();
    buffer.writeln("public String toJson() {");
    buffer.writeln("return name();".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String serializeFromJsonForEnum(GQEnumDefinition def) {
    if (!generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer();
    buffer.writeln("public static ${def.token} fromJson(String value) {");
    buffer.writeln("return Optional.ofNullable(value).map(${def.token}::valueOf).orElse(null);".ident());
    buffer.writeln("}");
    def.addImport(JavaImports.optional);
    return buffer.toString();
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
    buffer.write('private ${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name;');
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
      {bool withFianl = true, bool withDecorators = false, String decoratorJoiner = "\n"}) {
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
    if (withFianl) {
      buffer.write("final ");
    }
    buffer.write(serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray));
    buffer.write(" ");
    buffer.write(name);
    return buffer.toString();
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

    buffer.writeln('public class ${def.tokenInfo.token} {');
    buffer.writeln(serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(),
            join: "\n", withParenthesis: false)
        .ident());
    buffer.writeln(generateContructor(def.token, [], "public", def, checkForNulls: inputsCheckForNulls).ident());
    buffer.writeln(generateContructor(def.token, def.getSerializableFields(grammar.mode), "private", def).ident());
    buffer.writeln(generateBuilder(def.token, def.getSerializableFields(grammar.mode)).ident());
    buffer.writeln(serializeListText(
            def
                .getSerializableFields(grammar.mode)
                .map((e) => serializeGetter(e, def, checkForNulls: inputsCheckForNulls))
                .toList(),
            join: "\n",
            withParenthesis: false)
        .ident());
    buffer.writeln(serializeListText(
            def
                .getSerializableFields(grammar.mode)
                .map((e) => serializeSetter(e, def, checkForNulls: inputsCheckForNulls))
                .toList(),
            join: "\n",
            withParenthesis: false)
        .ident());
    if (generateJsonMethods) {
      buffer.writeln(generateToJson(def.getSerializableFields(grammar.mode), def).ident());
      buffer.writeln(generateFromJson(def.getSerializableFields(mode), def.token, def).ident());
    }
    buffer.writeln("}");
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

  String getFromJsonCall(GQField field, String varName, int depth, GQToken context, [GQType? type]) {
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
    if (grammar.isNonProjectableType(type.token) && !grammar.isEnum(type.token) && !grammar.isInput(type.token)) {
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
    var buffer = StringBuffer("public static ${token} fromJson(${_mapOf('String', 'Object')} json) {");
    buffer.writeln();
    buffer.writeln("return new ${token}(".ident());
    for (var field in fields) {
      String statement = getFromJsonCall(field, 'json', 0, context);
      if (field != fields.last) {
        statement = "${statement},";
      }
      buffer.writeln(statement.ident(2));
    }
    buffer.writeln(");".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String generateToJson(List<GQField> fields, GQToken context) {
    var buffer = StringBuffer("public ${_mapOf('String', 'Object')} toJson() {");
    buffer.writeln();
    buffer.writeln("${_mapOf('String', 'Object')} map = new HashMap<>();".ident());
    for (var field in fields) {
      buffer.writeln('map.put("${field.name}", ${fieldToJson(field, context)});'.ident());
    }
    buffer.writeln("return map;".ident());
    buffer.writeln("}");
    context.addImport(JavaImports.hasMap);
    context.addImport(JavaImports.map);

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
        String method = "Stream.of(${variableName}).map(${varName} -> ${inlineCallToJson}).${_toList}";
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
    String nullCheck;
    if (checkForNulls) {
      var checkingFields =
          fields.where((e) => !e.type.nullable).map((e) => "Objects.requireNonNull(${e.name});").toList();
      if (checkingFields.isNotEmpty) {
        nullCheck = serializeListText(checkingFields, join: "\n", withParenthesis: false);
        context.addImport(JavaImports.objects);
      } else {
        nullCheck = "";
      }
    } else {
      nullCheck = "";
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
    buffer.writeln('public static Builder builder() {');
    buffer.writeln('return new Builder();'.ident());
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln('public static class Builder {');
    buffer.writeln();
    for (var field in fields) {
      var noDirectiveField = GQField(name: field.name, type: field.type, arguments: field.arguments, directives: []);
      buffer.writeln(serializeField(noDirectiveField).trim().ident());
    }
    buffer.writeln();
    for (var e in fields) {
      buffer.writeln('public Builder ${e.name}(${serializeArgumentField(e)}) {'.ident());
      buffer.writeln('this.${e.name} = ${e.name};'.ident(2));
      buffer.writeln('return this;'.ident(2));
      buffer.writeln('}'.ident());
    }
    buffer.writeln();
    buffer.writeln('public $name build() {'.ident());
    buffer.writeln('return new $name(${fields.map((e) => e.name).join(", ")});'.ident(2));
    buffer.writeln('}'.ident());
    buffer.writeln('}');
    return buffer.toString();
  }

  String serializeGetter(GQField field, GQToken context, {bool checkForNulls = false}) {
    String? nullCheck;
    final returnStatement = "return ${field.name};";
    if (!field.type.nullable && checkForNulls) {
      context.addImport(JavaImports.objects);
      nullCheck = "Objects.requireNonNull(${field.name});";
    }
    var statements = [if (nullCheck != null) nullCheck, returnStatement];
    return """
${serializeGetterDeclaration(field)} { 
${statements.join("\n").ident()}
}
"""
        .trim();
  }

  String serializeMethod(GQField field, {String? modifier}) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(field.getDirectives());
    var args = serializeListText(field.arguments.map(serializeArgument).toList(), withParenthesis: false, join: ", ");
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
    final list = fields
        .map((f) => serializeArgumentField(f, withFianl: false, withDecorators: true, decoratorJoiner: " "))
        .toList();
    String interfaceImpl = _serializeImplements(interfaceNames);
    var buffer = StringBuffer();
    buffer.write("public record $recordName");

    buffer.write("(");
    buffer.write(serializeListText(list, withParenthesis: false, join: ", "));
    buffer.write(")");
    if (interfaceImpl.isNotEmpty) {
      buffer.write(" ");
      buffer.write(interfaceImpl);
    }
    buffer.writeln(" {");
    if (generateJsonMethods) {
      buffer.writeln(generateToJson(fields, context).ident());
      buffer.writeln(generateFromJson(fields, recordName, context).ident());
    }
    buffer.write("}");
    return buffer.toString();
  }

  String serializeGetterDeclaration(GQField field, {bool skipModifier = false, bool asProperty = false}) {
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
    String? nullCheck;
    final setStatement = "this.${field.name} = ${field.name};";

    if (!field.type.nullable && checkForNulls) {
      context.addImport(JavaImports.objects);
      nullCheck = "Objects.requireNonNull(${field.name});";
    }
    var statements = [if (nullCheck != null) nullCheck, setStatement];
    return """
public void ${_setterName(field.name.token)}(${serializeArgumentField(field)}) {
${statements.join("\n").ident()}
}
"""
        .trim();
  }

  @override
  String doSerializeTypeDefinition(GQTypeDefinition def) {
    if (def is GQInterfaceDefinition) {
      return serializeInterface(def);
    } else {
      return _doSerializeTypeDefinition(def);
    }
  }

  String _doSerializeTypeDefinition(GQTypeDefinition def) {
    final token = def.tokenInfo;
    final interfaceNames = def.interfaceNames;
    final decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    if (typesAsRecords) {
      buffer.writeln(serializeRecord(def.token, def.fields, interfaceNames.map((e) => e.token).toSet(), def));
      return buffer.toString();
    }

    buffer.writeln('public class $token ${_serializeImplements(interfaceNames.map((e) => e.token).toSet())}{');

    buffer.writeln(serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(),
            join: "\n", withParenthesis: false)
        .ident());
    buffer.writeln(generateContructor(def.token, [], "public", def, checkForNulls: typesCheckForNulls).ident());
    buffer.writeln(generateContructor(def.token, def.getSerializableFields(grammar.mode), "private", def).ident());
    buffer.writeln(generateBuilder(def.token, def.getSerializableFields(grammar.mode)).ident());
    buffer.writeln(serializeListText(
            def.getSerializableFields(grammar.mode).map((e) => serializeGetter(e, def, checkForNulls: typesCheckForNulls)).toList(),
            join: "\n",
            withParenthesis: false)
        .ident());
    buffer.writeln(serializeListText(
            def
                .getSerializableFields(grammar.mode)
                .map((e) => serializeSetter(e, def, checkForNulls: typesCheckForNulls))
                .toList(),
            join: "\n",
            withParenthesis: false)
        .ident());
    buffer.writeln(generateEqualsAndHashCode(def).ident());
    if (generateJsonMethods) {
      buffer.writeln(generateToJson(def.getSerializableFields(grammar.mode), def).ident());
      buffer.writeln(generateFromJson(def.getSerializableFields(grammar.mode), def.token, def).ident());
    }
    buffer.writeln('}');
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
    buffer.writeln('public boolean equals(Object o) {');
    buffer.writeln('if (!(o instanceof $token)) return false;'.ident());
    buffer.writeln('$token o2 = ($token) o;'.ident());
    buffer.writeln('return ${fields.map((e) => "Objects.equals($e, o2.$e);").join(" && ")}'.ident());
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('@Override');
    buffer.writeln('public int hashCode() {');
    buffer.writeln('return Objects.hash(${fields.join(", ")});'.ident());
    buffer.writeln('}');
    return buffer.toString();
  }

  static String _serializeImplements(Set<String> interfaceNames) {
    if (interfaceNames.isEmpty) {
      return '';
    }
    return "implements ${interfaceNames.join(", ")} ";
  }

  String serializeInterface(GQInterfaceDefinition interface, {bool getters = true}) {
    final token = interface.tokenInfo;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var decorators = serializeDecorators(interface.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("public interface $token");
    if (interfaces.isNotEmpty) {
      buffer.write(" extends ${interfaces.map((e) => e.tokenInfo.token).join(", ")}");
    }
    buffer.writeln(" {");
    buffer.writeln();
    for (var f in fields) {
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
      buffer.writeln(";");
      buffer.writeln();
    }
    // toJson
    if (generateJsonMethods) {
      interface.addImport(JavaImports.map);
      buffer.writeln("Map<String, Object> toJson();".ident());
    }
    // fromJson to Json
    if (interface.implementations.isNotEmpty) {
      buffer.writeln(_serializeFromJsonForInterface(interface.token, interface.implementations).ident());
    }
    buffer.write("}");
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
    } else if (grammar.interfaces.containsKey(token.token)) {
      path = "interfaces.${token.token}";
    } else if (grammar.types.containsKey(token.token)) {
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
      return 'import java.util.List;';
    }
    return 'import ${import};';
  }
}
