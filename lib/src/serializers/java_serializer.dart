import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';
import 'package:retrofit_graphql/src/utils.dart';

class JavaSerializer extends GqSerializer {
  JavaSerializer(super.grammar);

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    return """
${serializeDecorators(def.directives)}
public enum ${def.token} {
${def.values.map((e) => e.value).toList().join(", ").ident()}
}
""";
  }

  @override
  String doSerializeField(GQField def) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    return "${serializeDecorators(def.directives)}private ${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name;";
  }

  String serializeArgument(GQField def) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    return "${serializeDecorators(def.directives)}final ${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name";
  }

  String serializeTypeReactive(
      {required GQType gqType, bool forceNullable = false, bool asArray = false, bool reactive = false}) {
    if (gqType is GQListType) {
      if (reactive) {
        return "reactor.core.publisher.Flux<${serializeTypeReactive(gqType: gqType.inlineType)}>";
      }
      if (asArray) {
        return "${serializeType(gqType.inlineType, false, asArray)}[]";
      } else {
        return "java.util.List<${serializeType(gqType.inlineType, false)}>";
      }
    }
    final token = gqType.token;
    var type = grammar.typeMap[token] ?? grammar.projectedTypes[token]?.token ?? token;
    if (reactive) {
      return "reactor.core.publisher.Mono<$type>";
    }
    return type;
  }

  @override
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]) {
    return serializeTypeReactive(
        gqType: def, forceNullable: forceNullable, asArray: asArray, reactive: false);
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def) {
    return """
${serializeDecorators(def.directives)}
public class ${def.token} {

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}

${generateContructor(def.token, [], "public")}

${generateContructor(def.token, def.getSerializableFields(grammar), "private").ident()}

${generateBuilder(def.token, def.getSerializableFields(grammar)).ident()}
          
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeGetter(e)).toList(), join: "\n", withParenthesis: false).ident()}

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeSetter(e)).toList(), join: "\n", withParenthesis: false).ident()}
}
""";
  }

  String generateContructor(String name, List<GQField> fields, String? modifier) {
    if (fields.isEmpty) {
      return "";
    }
    var result =
        """$name(${serializeListText(fields.map((e) => serializeArgument(e)).toList(), join: ", ", withParenthesis: false)}) {
${serializeListText(fields.where((e) => !e.type.nullable).map((e) => "java.util.Objects.requireNonNull(${e.name});").toList(), join: "\n", withParenthesis: false).ident()}

${serializeListText(fields.map((e) => "this.${e.name} = ${e.name};").toList(), join: "\n", withParenthesis: false).ident()}
}
    """;
    if (modifier != null) {
      return "$modifier $result";
    }
    return result;
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

${serializeListText(fields.map((e) => '''public Builder ${e.name}(${serializeArgument(e)}) {
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

  String serializeGetter(GQField field) {
    String? nullCheck;
    final returnStatement = "return ${field.name};";
    if (!field.type.nullable) {
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

  String serializeGetterDeclaration(GQField field, {skipModifier = false}) {
    final result =
        """${serializeType(field.type, false, field.serialzeAsArray)} ${_getterName(field.name, field.type.token == "Boolean")}()""";
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
    return "$prefix${name[0].toUpperCase()}${name.substring(1)}";
  }

  String serializeSetter(GQField field) {
    String? nullCheck;
    final setStatement = "this.${field.name} = ${field.name};";

    if (!field.type.nullable) {
      nullCheck = "java.util.Objects.requireNonNull(${field.name});";
    }
    var statements = [if (nullCheck != null) nullCheck, setStatement];
    return """
public void ${_setterName(field.name)}(${serializeArgument(field)}) {
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
    final token = def.token;
    final interfaceNames = def.interfaceNames;
    return """
${serializeDecorators(def.directives)}
public class $token ${_serializeImplements(interfaceNames)}{
  
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}
    
${generateContructor(def.token, [], "public").ident()}
${generateContructor(def.token, def.getSerializableFields(grammar), "private").ident()}
${generateBuilder(def.token, def.getSerializableFields(grammar)).ident()}

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeGetter(e)).toList(), join: "\n", withParenthesis: false).ident()}
    
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeSetter(e)).toList(), join: "\n", withParenthesis: false).ident()}
    
${generateEqualsAndHashCode(def).ident()}
    
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

  static String serializeContructorArgs(GQTypeDefinition def, GQGrammar grammar) {
    var fields = def.getFields();
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

  static String _serializeImplements(Set<String> interfaceNames) {
    if (interfaceNames.isEmpty) {
      return '';
    }
    return "implements ${interfaceNames.join(", ")} ";
  }

  String serializeInterface(GQInterfaceDefinition interface) {
    final token = interface.token;
    final parents = interface.parents;
    final fields = interface.fields;

    return """
      ${serializeDecorators(interface.directives)}
      public interface $token ${parents.isNotEmpty ? "extends ${parents.map((e) => e.token).join(", ")} " : ""}{

${fields.map((f) => serializeGetterDeclaration(f, skipModifier: true)).join(";\n").ident()}${fields.isNotEmpty ? ";" : ""}
}""";
  }
}
