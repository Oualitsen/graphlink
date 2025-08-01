import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/utils.dart';

class DartSerializer extends GqSerializer {
  DartSerializer(super.grammar) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations(AnnotationSerializer.serializeAnnotation);
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    return """
${serializeDecorators(def.getDirectives())}
  enum ${def.token} { ${def.values.map((e) => doSerialzeEnumValue(e)).toList().join(", ")} }
""";
  }

  @override
  String doSerialzeEnumValue(GQEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if(decorators.isEmpty) {
      return value.value;
    }else {
      return "$decorators ${value.value}";
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
    return """
${serializeDecorators(def.getDirectives())}
@JsonSerializable(explicitToJson: true)
class ${def.token} {
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}
        
${'${def.token}({${def.getSerializableFields(grammar).map((e) => grammar.toConstructorDeclaration(e)).join(", ")}});'.ident()}
        
${'factory ${def.token}.fromJson(Map<String, dynamic> json) => _\$${def.token}FromJson(json);'.ident()}
        
${'Map<String, dynamic> toJson() => _\$${def.token}ToJson(this);'.ident()}
}
""";
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
    final subTypes = def.subTypes;
    final interfaceNames = def.interfaceNames;
    return """
      ${serializeDecorators(def.getDirectives())}
      @JsonSerializable(explicitToJson: true)
      class $token ${_serializeImplements(interfaceNames)}{
        
          ${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n\r          ", withParenthesis: false)}
          
          $token(${serializeContructorArgs(def, grammar)});
          
          ${generateEqualsAndHashCode(def)}
          
          factory $token.fromJson(Map<String, dynamic> json) {
             ${_serializeFromJson(token, subTypes)}
          }
          ${interfaceNames.isNotEmpty ? '\n${"\t" * 5}@override' : ''}
          Map<String, dynamic> toJson() {
            ${_serializeToJson(token)}
          }
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
    final token = def.token;
    return """\n\n
    @override
    bool operator ==(Object other) {
      if (identical(this, other)) return true;

      return other is $token &&
          ${fields.map((e) => "$e == other.$e").join(" && ")};
    }

    @override
    int get hashCode => Object.hashAll([${fields.join(", ")}]);
  """;
  }

  static String serializeContructorArgs(GQTypeDefinition def, GQGrammar grammar) {
    var fields = def.getSerializableFields(grammar);
    if (fields.isEmpty) {
      return "";
    }
    String nonCommonFields;
    if (fields.isEmpty) {
      nonCommonFields = "";
    } else {
      nonCommonFields = fields.map((e) => grammar.toConstructorDeclaration(e)).join(", ");
    }

    var combined = [nonCommonFields].where((element) => element.isNotEmpty).toSet();
    if (combined.isEmpty) {
      return "";
    } else if (combined.length == 1) {
      return "{${combined.first}}";
    }
    return "{${[nonCommonFields].join(", ")}}";
  }

  static String _serializeToJson(String token) {
    return "return _\$${token}ToJson(this);";
  }

  static String _serializeFromJson(String token, Set<GQTypeDefinition> subTypes) {
    if (subTypes.isEmpty) {
      return "return _\$${token}FromJson(json);";
    } else {
      return """
      var typename = json["__typename"];
      switch(typename) {
        
        ${subTypes.map((st) => "case \"${st.derivedFromType?.token ?? st.token}\": return _\$${st.token}FromJson(json);").join("\n        ")}
      }
      return _\$${token}FromJson(json);
    """;
    }
  }

  static String _serializeImplements(Set<String> interfaceNames) {
    if (interfaceNames.isEmpty) {
      return '';
    }
    return "implements ${interfaceNames.join(", ")} ";
  }

  String serializeInterface(GQInterfaceDefinition interface) {
    final token = interface.token;
    final parents = interface.parents;
    final fields = interface.getSerializableFields(grammar);

    return """
${serializeDecorators(interface.getDirectives())}
abstract class $token ${parents.isNotEmpty ? "extends ${parents.map((e) => e.token).join(", ")} " : ""}{

\t${fields.map((f) => serializeGetterDeclaration(f)).join(";\n\t")}${fields.isNotEmpty ? ";" : ""}
}""";
  }

  String serializeGetterDeclaration(GQField field) {
    return """${serializeType(field.type, false)} get ${field.name}""";
  }

  
}
