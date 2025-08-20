import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/utils.dart';

const _toList = "collect(java.util.stream.Collectors.toList())";
const _list = "java.util.List";
const _map = "java.util.Map";
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
  final bool generateJsonMethods;
  JavaSerializer(
    super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false,
    this.generateJsonMethods = false,
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
    buffer.writeln("public String toJson() {".ident());
    buffer.writeln("return name();".ident(2));
    buffer.writeln("}".ident());
    buffer.writeln("public static ${def.token} fromJson(String value) {".ident());
    buffer.writeln("return java.util.Optional.ofNullable(value).map(${def.token}::valueOf).orElse(null);".ident(2));
    buffer.writeln("}".ident());
    buffer.writeln("}");
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
    return "${serializeDecorators(def.getDirectives(), joiner: "\n")}private ${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name;";
  }

  String serializeArgument(GQArgumentDefinition arg) {
    var type = arg.type;
    var name = arg.tokenInfo;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "final ${serializeType(type, false)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators $result";
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

  String serializeTypeReactive(
      {required GQType gqType, bool forceNullable = false, bool asArray = false, bool reactive = false}) {
    if (gqType is GQListType) {
      if (reactive) {
        return "reactor.core.publisher.Flux<${convertPrimitiveToBoxed(serializeTypeReactive(gqType: gqType.inlineType))}>";
      }
      if (asArray) {
        return "${serializeType(gqType.inlineType, false, asArray)}[]";
      } else {
        return _listOf(convertPrimitiveToBoxed(serializeType(gqType.inlineType, false)));
      }
    }
    final token = gqType.token;

    var type = getTypeNameFromGQExternal(token) ?? token;
    if (reactive) {
      return "reactor.core.publisher.Mono<${convertPrimitiveToBoxed(type)}>";
    }
    if (typeIsJavaPrimitive(type) && (gqType.nullable || forceNullable)) {
      return convertPrimitiveToBoxed(type);
    }
    return type;
  }

  @override
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]) {
    return serializeTypeReactive(gqType: def, forceNullable: forceNullable, asArray: asArray, reactive: false);
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def, {bool checkForNulls = false}) {
    final decorators = serializeDecorators(def.getDirectives());
    if (inputsAsRecords) {
      var buffer = StringBuffer();
      if (decorators.isNotEmpty) {
        buffer.writeln(decorators);
      }
      buffer.writeln(serializeRecord(def.token, def.fields, {}));
      return buffer.toString();
    }

    return """
$decorators
public class ${def.tokenInfo.token} {
${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}
${generateContructor(def.token, [], "public", checkForNulls: checkForNulls).ident()}

${generateContructor(def.token, def.getSerializableFields(grammar.mode), "private").ident()}

${generateBuilder(def.token, def.getSerializableFields(grammar.mode)).ident()}
          
${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeGetter(e, checkForNulls: checkForNulls)).toList(), join: "\n", withParenthesis: false).ident()}

${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeSetter(e, checkForNulls: checkForNulls)).toList(), join: "\n", withParenthesis: false).ident()}

${generateToJson(def.getSerializableFields(grammar.mode)).ident()}

${generateFromJson(def.getSerializableFields(mode), def.token).ident()}
}
""";
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

  String getFromJsonCall(GQField field, String varName, int depth, [GQType? type]) {
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
      String mapFunction = 'map(${newVarName} -> ${getFromJsonCall(field, newVarName, depth + 1, type.inlineType)})';
      return '$nullCheckStatement (${targetCast}${varName}${callMapDotGet}).stream().${mapFunction}.${_toList}';
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

  String generateFromJson(List<GQField> fields, String token) {
    if (!generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer("public static ${token} fromJson(${_mapOf('String', 'Object')} json) {");
    buffer.writeln();
    buffer.writeln("return new ${token}(".ident());
    for (var field in fields) {
      String statement = getFromJsonCall(field, 'json', 0);
      if (field != fields.last) {
        statement = "${statement},";
      }
      buffer.writeln(statement.ident(2));
    }
    buffer.writeln(");".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String generateToJson(List<GQField> fields) {
    if (!generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer("public ${_mapOf('String', 'Object')} toJson() {");
    buffer.writeln();
    buffer.writeln("${_mapOf('String', 'Object')} map = new java.util.HashMap<>();".ident());
    for (var field in fields) {
      buffer.writeln('map.put("${field.name}", ${fieldToJson(field)});'.ident());
    }
    buffer.writeln("return map;".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String fieldToJson(GQField field) {
    var buffer = StringBuffer();
    var toJosnCall = callToJson(field, field.type, field.name.token, 0);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String safeCall(String variable, String method, bool nullable) {
    if (nullable) {
      return "$variable == null ? null : ${variable}.${method}";
    }
    return "${variable}.${method}";
  }

  String callToJson(GQField field, GQType type, String variableName, int index) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson = callToJson(field, inlineType, varName, index + 1);
      if (field.getDirectiveByName(gqArray) != null) {
        // array
        String method = "java.util.stream.Stream.of(${variableName}).map(${varName} -> ${inlineCallToJson}).${_toList}";
        return "${variableName} == null ? null : $method";
      } else {
        // list

        String method;
        if (varName == inlineCallToJson) {
          method = "stream().${_toList}";
        } else {
          method = "stream().map(${varName} -> ${inlineCallToJson}).${_toList}";
        }

        return safeCall(variableName, method, type.nullable);
      }
    }
    if (grammar.isEnum(type.token) || grammar.isProjectableType(type.token)) {
      return safeCall(variableName, "toJson()", type.nullable);
    }
    return variableName;
  }

  String generateContructor(String name, List<GQField> fields, String? modifier, {bool checkForNulls = false}) {
    String nullCheck;
    if (checkForNulls) {
      var checkingFields =
          fields.where((e) => !e.type.nullable).map((e) => "java.util.Objects.requireNonNull(${e.name});").toList();
      if (checkingFields.isNotEmpty) {
        nullCheck = serializeListText(checkingFields, join: "\n", withParenthesis: false);
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

    return """public static Builder builder() {
${'return new Builder();'.ident()}
}


public static class Builder {
${serializeListText(fields.map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}

${serializeListText(fields.map((e) => '''public Builder ${e.name}(${serializeArgumentField(e)}) {
${'this.${e.name} = ${e.name};'.ident()}
${'return this;'.ident()}
}''').toList(), join: "\n", withParenthesis: false).ident()}

${'public $name build() {'.ident()}
${'return new $name(${fields.map((e) => e.name).join(", ")});'.ident(2)}
${'}'.ident()}

}
"""
        .trim();
  }

  String serializeGetter(GQField field, {bool checkForNulls = false}) {
    String? nullCheck;
    final returnStatement = "return ${field.name};";
    if (!field.type.nullable && checkForNulls) {
      nullCheck = "java.util.Objects.requireNonNull(${field.name});";
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
    var decorators = serializeDecorators(field.getDirectives());
    var args = serializeListText(field.arguments.map(serializeArgument).toList(), withParenthesis: false);
    var result = "${serializeType(field.type, false, field.serialzeAsArray)} ${field.name}($args)";
    if (modifier != null) {
      result = "$modifier $result";
    }
    if (decorators.isNotEmpty) {
      result = """
$decorators
$result
""";
    }
    return result.trim();
  }

  String serializeRecord(String recordName, List<GQField> fields, Set<String> interfaceNames) {
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
    buffer.writeln(generateToJson(fields).ident());
    buffer.writeln(generateFromJson(fields, recordName).ident());
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

  String serializeSetter(GQField field, {bool checkForNulls = false}) {
    String? nullCheck;
    final setStatement = "this.${field.name} = ${field.name};";

    if (!field.type.nullable && checkForNulls) {
      nullCheck = "java.util.Objects.requireNonNull(${field.name});";
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

  String _doSerializeTypeDefinition(GQTypeDefinition def, {bool checkNulls = false}) {
    final token = def.tokenInfo;
    final interfaceNames = def.interfaceNames;
    final decorators = serializeDecorators(def.getDirectives());

    if (typesAsRecords) {
      return """
$decorators
${serializeRecord(def.token, def.fields, interfaceNames.map((e) => e.token).toSet())}
""";
    }

    return """
${decorators}
public class $token ${_serializeImplements(interfaceNames.map((e) => e.token).toSet())}{
  
${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}
    
${generateContructor(def.token, [], "public", checkForNulls: checkNulls).ident()}
${generateContructor(def.token, def.getSerializableFields(grammar.mode), "private").ident()}
${generateBuilder(def.token, def.getSerializableFields(grammar.mode)).ident()}

${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeGetter(e, checkForNulls: checkNulls)).toList(), join: "\n", withParenthesis: false).ident()}
    
${serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeSetter(e, checkForNulls: checkNulls)).toList(), join: "\n", withParenthesis: false).ident()}
    
${generateEqualsAndHashCode(def).ident()}

${generateToJson(def.getSerializableFields(grammar.mode)).ident()}
${generateFromJson(def.getSerializableFields(grammar.mode), def.token).ident()}

}
    """;
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
    return """
@Override
public boolean equals(Object o) {
${'if (!(o instanceof $token)) return false;'.ident()}
${'$token o2 = ($token) o;'.ident()}
${'return ${fields.map((e) => "java.util.Objects.equals($e, o2.$e);").join(" && ")}'.ident()}
}

@Override
public int hashCode() {
${'return java.util.Objects.hash(${fields.join(", ")});'.ident()}
}   
  """;
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
      buffer.writeln(decorators);
    }
    buffer.write("public interface $token");
    if (interfaces.isNotEmpty) {
      buffer.write(" extends ${interfaces.map((e) => e.tokenInfo.token).join(", ")}");
    }
    buffer.writeln(" {");
    for (var f in fields) {
      if (getters) {
        var fieldDecorators = serializeDecorators(f.getDirectives(), joiner: "\n");
        if (fieldDecorators.isNotEmpty) {
          buffer.write(fieldDecorators.ident());
        }
        if (typesAsRecords) {
          buffer.write(serializeGetterDeclaration(f, skipModifier: true, asProperty: true).ident());
        } else {
          buffer.write(serializeGetterDeclaration(f, skipModifier: true).ident());
        }
      } else {
        buffer.write(serializeMethod(f).ident());
      }
      buffer.writeln(";");
    }
    // toJson
    if (generateJsonMethods) {
      buffer.writeln("java.util.Map<String, Object> toJson();".ident());
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
}
