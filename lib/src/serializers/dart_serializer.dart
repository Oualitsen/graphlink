import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
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

class DartSerializer extends GqSerializer {
  @override
  final bool generateJsonMethods;
  DartSerializer(super.grammar, {this.generateJsonMethods = true}) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations(AnnotationSerializer.serializeAnnotation);
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.writeln("enum ${def.tokenInfo} {");
    buffer.write(def.values.map((e) => doSerializeEnumValue(e)).toList().join(", ").ident());
    buffer.writeln(";");
    // toJson
    buffer.writeln("String toJson() {".ident());
    buffer.writeln('switch(this) {'.ident(2));
    // switch cases
    var switchCases = def.values.map((val) => 'case ${val.token}: return "${val.token}";').join("\n");
    buffer.writeln(switchCases.ident(3));
    buffer.writeln('}'.ident(2));
    buffer.writeln("}".ident());
    // end toJson
    // fromJson
    buffer.writeln("static ${def.token} fromJson(String value) {".ident());
    //switch statement
    buffer.writeln('switch(value) {'.ident(2));
    var switchCasesFromJson = def.values.map((val) => 'case "${val.token}": return ${val.token};').join("\n");
    buffer.writeln(switchCasesFromJson.ident(3));
    buffer.writeln('default: throw ArgumentError("Invalid ${def.token}: \$value");'.ident(3));

    buffer.writeln("}".ident(2));
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
    return "${serializeDecorators(def.getDirectives())}final ${serializeType(type, hasInculeOrSkipDiretives)} $name;";
  }

  @override
  String serializeType(GQType def, bool forceNullable, [bool _ = false]) {
    String postfix = "";
    if (forceNullable || def.nullable) {
      postfix = "?";
    }
    if (def is GQListType) {
      return "List<${serializeType(def.inlineType, false)}>$postfix";
    }
    final token = def.token;
    var dartTpe = getTypeNameFromGQExternal(token) ?? token;
    return "$dartTpe$postfix";
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def) {
    var buffer = StringBuffer();
    var decorators = serializeDecorators(def.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.writeln('class ${def.tokenInfo} {');
    buffer.writeln(serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(),
            join: "\n", withParenthesis: false)
        .ident());
    buffer.writeln(
        '${def.tokenInfo}({${def.getSerializableFields(grammar.mode).map((e) => toConstructorDeclaration(e)).join(", ")}});'
            .ident());
    if (generateJsonMethods) {
      buffer.writeln();
      buffer.writeln(generateToJson(def.getSerializableFields(mode)).ident());
      buffer.writeln();
      buffer.writeln(generateFromJson(def.getSerializableFields(mode), def.token).ident());
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  String toConstructorDeclaration(GQField field) {
    if (grammar.nullableFieldsRequired || !field.type.nullable) {
      return "required this.${field.name}";
    } else {
      return "this.${field.name}";
    }
  }

  String generateFromJson(List<GQField> fields, String token) {
    if (!generateJsonMethods) {
      return "";
    }
    var buffer = StringBuffer("static ${token} fromJson(Map<String, dynamic> json) {");
    buffer.writeln();
    buffer.writeln("return ${token}(".ident());
    for (var field in fields) {
      buffer.write(fieldFromJson(field).ident(2));
      if (field != fields.last) {
        buffer.write(",");
      }
      buffer.writeln();
    }
    buffer.writeln(");".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String generateToJson(List<GQField> fields) {
    var buffer = StringBuffer("Map<String, dynamic> toJson() {");
    buffer.writeln();
    buffer.writeln("return {".ident());
    for (var field in fields) {
      buffer.write(fieldToJson(field).ident(2));
      if (field != fields.last) {
        buffer.write(",");
      }
      buffer.writeln();
    }
    buffer.writeln("};".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  String fieldToJson(GQField field) {
    var buffer = StringBuffer("'${field.name}': ");
    var toJosnCall = callToJson(field, field.type, 0);
    buffer.write("${field.name}${toJosnCall}");
    return buffer.toString();
  }

  String fieldFromJson(GQField field) {
    var buffer = StringBuffer('${field.name}: ');
    var toJosnCall = callFromJson("json['${field.name}']", field, field.type, 0);
    buffer.write(toJosnCall);
    return buffer.toString();
  }

  String castDynamicToType(String variable, GQType type) {
    String dot = type.nullable ? "?." : ".";
    String serializedType = serializeType(type, false);
    String numSuffix = type.nullable ? "?" : "";

    if (type.isList) {
      return "(${variable} as List<dynamic>${numSuffix})";
    }
    if (grammar.isEnum(type.token)) {
      var enumFromJson = "${type.token}.fromJson(${variable} as String)";
      if (type.nullable) {
        return "${variable} == null ? null : ${enumFromJson}";
      } else {
        return enumFromJson;
      }
    }
    if (grammar.isProjectableType(type.token)) {
      var typeFromJson = "${type.token}.fromJson(${variable} as Map<String, dynamic>)";
      if (type.nullable) {
        return "${variable} == null ? null : ${typeFromJson}";
      } else {
        return typeFromJson;
      }
    }

    if (serializedType == "double" || serializedType == "double?") {
      return "(${variable} as num${numSuffix})${dot}toDouble()";
    }

    var result = "${variable} as ${serializedType}";

    if (type is GQListType || grammar.isProjectableType(type.token) || grammar.isEnum(type.token)) {
      return "(${result})";
    }

    return result;
  }

  String callFromJson(String variable, GQField field, GQType type, int index) {
    String fromJsonCall;
    String dot = type.nullable ? "?." : ".";
    fromJsonCall = castDynamicToType(variable, type);
    if (type.isList) {
      String varName = "e${index}";
      var inlneCallToJson = callFromJson(varName, field, type.inlineType, index + 1);
      return "${fromJsonCall}${dot}map((${varName}) => ${inlneCallToJson}).toList()";
    }
    return fromJsonCall;
  }

  String callToJson(GQField field, GQType type, int index) {
    var fieldType = field.type.inlineType;
    String toJsonCall;
    String dot = type.nullable ? "?." : ".";
    //check if enum
    if (grammar.isProjectableType(fieldType.token) || grammar.isEnum(fieldType.token)) {
      toJsonCall = '${dot}toJson()';
    } else {
      toJsonCall = '';
    }
    if (type.isList) {
      String varName = "e${index}";
      var inlneCallToJson = callToJson(field, type.inlineType, index + 1);
      return "${dot}map((${varName}) => ${varName}${inlneCallToJson}).toList()";
    }
    return toJsonCall;
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
    final token = def.token;
    final implementations = def is GQInterfaceDefinition ? def.implementations : <GQTypeDefinition>{};

    final interfaceNames = def.interfaceNames.map((e) => e.token).toSet();
    interfaceNames.addAll(implementations.map((e) => e.token));
    var decorators = serializeDecorators(def.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators);
    }
    buffer.write("class $token");
    var implements = _serializeImplements(interfaceNames);
    buffer.write(" ");

    if (implements.isNotEmpty) {
      buffer.write(implements);
    }
    buffer.writeln("{");
    buffer.writeln();
    buffer.writeln(serializeListText(def.getSerializableFields(grammar.mode).map((e) => serializeField(e)).toList(),
            join: "\n", withParenthesis: false)
        .ident());
    buffer.writeln();
    buffer.writeln("$token(${serializeContructorArgs(def, grammar)});".ident());
    buffer.writeln();
    var equalsHascodeCode = generateEqualsAndHashCode(def);
    if (equalsHascodeCode.isNotEmpty) {
      buffer.writeln(equalsHascodeCode.ident());
    }
    if (generateJsonMethods) {
      buffer.writeln(generateToJson(def.getSerializableFields(mode)).ident());
      buffer.writeln();
      buffer.writeln(generateFromJson(def.getSerializableFields(mode), def.token).ident());
    }
    buffer.writeln("}");
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
    var buffer = StringBuffer();
    buffer.writeln('@override');
    buffer.writeln('bool operator ==(Object other) {');
    buffer.writeln('if (identical(this, other)) return true;'.ident());
    buffer.writeln('return other is $token &&'.ident());
    buffer.write(fields.map((e) => "$e == other.$e").join(" && ").ident());
    buffer.writeln(';');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('@override');
    buffer.writeln('int get hashCode => Object.hashAll([${fields.join(", ")}]);');
    return buffer.toString();
  }

  String serializeContructorArgs(GQTypeDefinition def, GQGrammar grammar) {
    var fields = def.getSerializableFields(grammar.mode);
    if (fields.isEmpty) {
      return "";
    }
    String nonCommonFields;
    if (fields.isEmpty) {
      nonCommonFields = "";
    } else {
      nonCommonFields = fields.map((e) => toConstructorDeclaration(e)).join(", ");
    }

    var combined = [nonCommonFields].where((element) => element.isNotEmpty).toSet();
    if (combined.isEmpty) {
      return "";
    } else if (combined.length == 1) {
      return "{${combined.first}}";
    }
    return "{${[nonCommonFields].join(", ")}}";
  }

  static String _serializeToJsonForInterface(String token) {
    return "Map<String, dynamic> toJson();";
  }

  static String _serializeFromJsonForInterface(String token, Set<GQTypeDefinition> implementations) {
    var buffer = StringBuffer("static ${token} fromJson(Map<String, dynamic> json) {");
    buffer.writeln();

    buffer.writeln("var typename = json['__typename'] as String;".ident());
    buffer.writeln("switch(typename) {".ident());
    for (var st in implementations) {
      String typeName = st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token;
      String currentToken = st.tokenInfo.token;
      buffer.writeln("case '${typeName}': return ${currentToken}.fromJson(json);".ident(2));
    }
    buffer.writeln(
        'default: throw ArgumentError("Invalid type \$typename. \$typename does not implement $token or not defined");'
            .ident(2));
    buffer.writeln("}".ident());
    buffer.writeln("}");
    return buffer.toString();
  }

  static String _serializeImplements(Set<String> interfaceNames) {
    if (interfaceNames.isEmpty) {
      return '';
    }
    return "implements ${interfaceNames.join(", ")} ";
  }

  String serializeInterface(GQInterfaceDefinition interface) {
    final token = interface.tokenInfo.token;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(grammar.mode);
    var buffer = StringBuffer();
    var decorators = serializeDecorators(interface.getDirectives());
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    buffer.write("abstract class $token ");
    if (interfaces.isNotEmpty) {
      buffer.write("extends ${interfaces.map((e) => e.tokenInfo).join(", ")} ");
    }
    buffer.writeln("{");
    for (var field in fields) {
      var fieldDecorators = serializeDecorators(field.getDirectives());
      if (fieldDecorators.isNotEmpty) {
        buffer.writeln(fieldDecorators.trim().ident());
      }
      buffer.writeln("${serializeGetterDeclaration(field)};".ident());
    }

    if (generateJsonMethods) {
      buffer.writeln(_serializeToJsonForInterface(token).ident());
    }
    if (generateJsonMethods && interface.implementations.isNotEmpty) {
      buffer.writeln(_serializeFromJsonForInterface(token, interface.implementations).ident());
    }

    buffer.writeln("}");
    return buffer.toString();
  }

  String serializeGetterDeclaration(GQField field) {
    return """${serializeType(field.type, false)} get ${field.name}""";
  }

  @override
  String getFileNameFor(GQToken token) {
    return "${token.token.toSnakeCase()}.dart";
  }

  @override
  String serializeImportToken(GQToken token, String importPrefix) {
    String? init;
    if (token is GQEnumDefinition) {
      init = "enums/${getFileNameFor(token)}";
    } else if (token is GQInterfaceDefinition) {
      init = "interfaces/${getFileNameFor(token)}";
    } else if (token is GQTypeDefinition) {
      init = "types/${getFileNameFor(token)}";
    } else if (token is GQInputDefinition) {
      init = "inputs/${getFileNameFor(token)}";
    }

    return "import '${importPrefix}/${init}';";
  }

  @override
  String serializeImport(String import) {
    if (import == importList) {
      return "";
    }
    return """import '$import';""";
  }
}
