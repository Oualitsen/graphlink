import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
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

class JavaSerializer extends GqSerializer {
  final bool inputsAsRecords;
  final bool typesAsRecords;
  JavaSerializer(super.grammar, {
    this.inputsAsRecords = false,
    this.typesAsRecords = false
  }) {
    _initAnnotations();
  }

  void _initAnnotations() {
    grammar.handleAnnotations((val) => AnnotationSerializer.serializeAnnotation(val, multiLineString: false));
  }

  @override
  String doSerializeEnumDefinition(GQEnumDefinition def) {
    return """
${serializeDecorators(def.getDirectives())}
public enum ${def.token} {
${def.values.map((e) => doSerialzeEnumValue(e)).toList().join(", ").ident()}
}
""";
  }

  @override
  String doSerialzeEnumValue(GQEnumValue value) {
    var decorators = serializeDecorators(value.getDirectives(), joiner: " ");
    if (decorators.isEmpty) {
      return value.value;
    } else {
      return "$decorators ${value.value}";
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
    var name = arg.token;
    var decorators = serializeDecorators(arg.getDirectives(), joiner: " ");
    var result = "final ${serializeType(type, false)} ${name}";
    if (decorators.isNotEmpty) {
      return "$decorators $result";
    }
    return result;
  }

  String serializeArgumentField(GQField def, {bool withFianl = true, bool withDecorators = false}) {
    final type = def.type;
    final name = def.name;
    final hasInculeOrSkipDiretives = def.hasInculeOrSkipDiretives;
    var result = "${serializeType(type, hasInculeOrSkipDiretives, def.serialzeAsArray)} $name";
    if (withFianl) {
      result = "final $result";
    }
    if (withDecorators) {
      var decorators = serializeDecorators(def.getDirectives());
      if (decorators.trim().isNotEmpty) {
        result = "$decorators $result";
      }
    }
    return result;
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
        return "java.util.List<${convertPrimitiveToBoxed(serializeType(gqType.inlineType, false))}>";
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
    return serializeTypeReactive(
        gqType: def, forceNullable: forceNullable, asArray: asArray, reactive: false);
  }

  @override
  String doSerializeInputDefinition(GQInputDefinition def, {bool checkForNulls = false}) {
    final decorators = serializeDecorators(def.getDirectives());
    if (inputsAsRecords) {
      return """
$decorators
${serializeRecord(def.token, def.fields, {})}
""";
    }

    return """
$decorators
public class ${def.token} {

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}

${generateContructor(def.token, [], "public", checkForNulls: checkForNulls)}

${generateContructor(def.token, def.getSerializableFields(grammar), "private").ident()}

${generateBuilder(def.token, def.getSerializableFields(grammar)).ident()}
          
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeGetter(e, checkForNulls: checkForNulls)).toList(), join: "\n", withParenthesis: false).ident()}

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeSetter(e, checkForNulls: checkForNulls)).toList(), join: "\n", withParenthesis: false).ident()}
}
""";
  }

  String generateContructor(String name, List<GQField> fields, String? modifier,
      {bool checkForNulls = false}) {
    String nullCheck;
    if (checkForNulls) {
      nullCheck = serializeListText(
          fields
              .where((e) => !e.type.nullable)
              .map((e) => "java.util.Objects.requireNonNull(${e.name});")
              .toList(),
          join: "\n",
          withParenthesis: false);
    } else {
      nullCheck = "";
    }
    var result =
        """$name(${serializeListText(fields.map((e) => serializeArgumentField(e)).toList(), join: ", ", withParenthesis: false)}) {
${nullCheck.ident()}

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
    final list =
        fields.map((f) => serializeArgumentField(f, withFianl: false, withDecorators: true)).toList();
    String interfaceImpl = _serializeImplements(interfaceNames);
    return "public record $recordName ${interfaceImpl}(${serializeListText(list, withParenthesis: false, join: ", ")}) {}";
  }

  String serializeGetterDeclaration(GQField field, {bool skipModifier = false, bool asProperty = false}) {
    var returnType = serializeType(field.type, false);
    var result = serializeType(field.type, false, field.serialzeAsArray);
    if (asProperty) {
      result = "$result ${field.name}";
    } else {
      result = "$result ${_getterName(field.name, returnType == "boolean")}";
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
    return "$prefix${name[0].toUpperCase()}${name.substring(1)}";
  }

  String serializeSetter(GQField field, {bool checkForNulls = false}) {
    String? nullCheck;
    final setStatement = "this.${field.name} = ${field.name};";

    if (!field.type.nullable && checkForNulls) {
      nullCheck = "java.util.Objects.requireNonNull(${field.name});";
    }
    var statements = [if (nullCheck != null) nullCheck, setStatement];
    return """
public void ${_setterName(field.name)}(${serializeArgumentField(field)}) {
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
    final token = def.token;
    final interfaceNames = def.interfaceNames;
    final decorators = serializeDecorators(def.getDirectives());

      if (typesAsRecords) {
        return """
$decorators
${serializeRecord(def.token, def.fields, interfaceNames)}
""";
      }

    return """
${decorators}
public class $token ${_serializeImplements(interfaceNames)}{
  
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeField(e)).toList(), join: "\n", withParenthesis: false).ident()}
    
${generateContructor(def.token, [], "public", checkForNulls: checkNulls).ident()}
${generateContructor(def.token, def.getSerializableFields(grammar), "private").ident()}
${generateBuilder(def.token, def.getSerializableFields(grammar)).ident()}

${serializeListText(def.getSerializableFields(grammar).map((e) => serializeGetter(e, checkForNulls: checkNulls)).toList(), join: "\n", withParenthesis: false).ident()}
    
${serializeListText(def.getSerializableFields(grammar).map((e) => serializeSetter(e, checkForNulls: checkNulls)).toList(), join: "\n", withParenthesis: false).ident()}
    
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

  String serializeInterface(GQInterfaceDefinition interface, {bool getters = true}) {
    final token = interface.token;
    final parents = interface.parents;
    final fields = interface.getSerializableFields(grammar);
    var decorators = serializeDecorators(interface.getDirectives());

    var result = """
public interface $token ${parents.isNotEmpty ? "extends ${parents.map((e) => e.token).join(", ")} " : ""}{

${fields.map((f) {
              if (getters) {
                if (typesAsRecords) {
                  return "${serializeDecorators(f.getDirectives(), joiner: "\n")}${serializeGetterDeclaration(f, skipModifier: true, asProperty: true)}";
                } else {
                  return "${serializeDecorators(f.getDirectives(), joiner: "\n")}${serializeGetterDeclaration(f, skipModifier: true)}";
                }
              } else {
                return serializeMethod(f);
              }
            }).map((e) => "$e;").join("\n").ident()}
}""";
    if (decorators.isNotEmpty) {
      return """
$decorators
$result
""";
    }
    return result;
  }
}
