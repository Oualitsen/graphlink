import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_scalar_definition.dart';
import 'package:retrofit_graphql/src/model/gq_schema.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';

const _skippedDirectives = {
  gqDecorators,
  gqSkipOnServer,
  gqSkipOnClient,
  gqArray,
  gqServiceName,
  gqTypeNameDirective,
  gqEqualsHashcode,
  gqExternal,
  gqRepository
};

bool _shouldSkipDriectiveDefinition(GQDirectiveDefinition def) {
  return _skippedDirectives.contains(def.name.token) ||
      def.arguments
          .where(
              (arg) => arg.token == gqAnnotation && arg.type.token == "Boolean")
          .isNotEmpty;
}

bool _shouldSkipDriectiveValue(GQDirectiveValue def) {
  return _skippedDirectives.contains(def.token) ||
      GQGrammar.directivesToSkip.contains(def.token) ||
      def.getArgValue(gqAnnotation) == true;
}
// this is for skipping generating objects that should be hidden from the client
const clientMode = CodeGenerationMode.client;
class GraphqSerializer {
  final GQGrammar grammar;

  GraphqSerializer(this.grammar);

  String generateSchema() {
    
    final buffer = StringBuffer();

    ///schema
    buffer.writeln(serializeSchemaDefinition(grammar.schema));

    /// sacalars

    var scalars = 
        filterSerialization(grammar.scalars.values, clientMode)
        .where((s) => !grammar.builtInScalars.contains(s.token))
        .map(serializeScalarDefinition)
        .join("\n");
    buffer.writeln(scalars);

    /// directives

    var directiveDefinitions = grammar.directiveDefinitions.values
        .map(serializeDirectiveDefinition)
        .where((s) => s.isNotEmpty)
        .join("\n");

    buffer.writeln(directiveDefinitions);

    // inputs
    var inputSerial = filterSerialization(grammar.inputs.values, clientMode)
    .map((e) => serializeInputDefinition(e, clientMode)).join("\n");
    buffer.writeln(inputSerial);

    // types
    var typesSerial =
     filterSerialization(grammar.types.values, clientMode).map((e) => serializeTypeDefinition(e, clientMode)).join("\n");
    buffer.writeln(typesSerial);
    // interfaces

    var interfacesSerial =
    filterSerialization(grammar.interfaces.values, clientMode)
        .where((i) => !i.fromUnion)
        .map((e) => serializeTypeDefinition(e, clientMode)).join("\n");
    buffer.writeln(interfacesSerial);
    // enums
    var enumsSerial =
       filterSerialization(grammar.enums.values, clientMode).map(serializeEnumDefinition).join("\n");
    buffer.writeln(enumsSerial);

    //unions
    var unionSerial =
        grammar.unions.values.map(serializeUnionDefinition).join("\n");
    buffer.writeln(unionSerial);

    return buffer.toString();
  }

  String serializeScalarDefinition(GQScalarDefinition def) {
    return '''
scalar ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeDirectiveValueList(List<GQDirectiveValue> values) {
    return values.map(serializeDirectiveValue).join(" ");
  }

  String serializeDirectiveValue(GQDirectiveValue value) {
    if (_shouldSkipDriectiveValue(value)) {
      return '';
    }
    var arguments = value.getArguments();
    var args = arguments.isEmpty
        ? ""
        : "(${arguments.map((e) => serializeArgumentValue(e)).join(", ")})";
    return "${value.tokenInfo}$args";
  }

  String serializeDirectiveDefinition(GQDirectiveDefinition def) {
    // check if we should skip some directives
    if (_shouldSkipDriectiveDefinition(def)) {
      return '';
    }
    return '''
directive ${def.name}${serializeDirectiveArgs(def.arguments)} on ${def.scopes.map((e) => e.name).join(" | ")}
'''
        .trim();
  }

  String serializeDirectiveArgs(List<GQArgumentDefinition> arguments) {
    if (arguments.isEmpty) {
      return "";
    }
    var result = arguments.map(serializeArgumentDefinition).join(", ");
    return "($result)";
  }

  String serializeArgumentDefinition(GQArgumentDefinition def) {
    var buffer =
        StringBuffer("${def.token.dolarEscape()}: ${serializeType(def.type)}");
    if (def.initialValue != null) {
      buffer.write(" = ${def.initialValue}");
    }
    return buffer.toString();
  }

  String serializeSchemaDefinition(GQSchema schema) {
   var inner = GQQueryType.values
    .where((value) => grammar.types.containsKey(schema.getByQueryType(value)))
    .map((value) {
      switch(value) {
        
        case GQQueryType.query:
          return "query: ${schema.query}";
        case GQQueryType.mutation:
          return "mutation: ${schema.mutation}";
        case GQQueryType.subscription:
          return "subscription: ${schema.subscription}";
      }
    });
if(inner.isEmpty) {
  return "";
}
    return '''
schema {
${inner.join("\n").ident()}
}
'''.trim();
  }

  String serializeInputDefinition(GQInputDefinition def, CodeGenerationMode mode) {
    return '''
input ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{
${def.getSerializableFields(mode, skipGenerated: true).map(serializeField).map((e) => e.ident()).join("\n")}
}
''';
  }

  String serializeTypeDefinition(GQTypeDefinition def, CodeGenerationMode mode) {

    String type;
    Iterable<String> interfaces;
    if(def is GQInterfaceDefinition) {
      type = "interface";
      interfaces = def.getParentNames();
    }else { 
      type = "type";
      interfaces = def.getInterfaceNames();
    }

    var result = StringBuffer("$type ${def.tokenInfo}");
    if(interfaces.isNotEmpty) {
      result.write(" implements ");
      result.write(interfaces.join(" & "));
    }
    var directives = serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    if(directives.isNotEmpty) {
      result.write(" ");
      result.write(directives);
    }
    result.writeln(" {");
    result.writeln(def.getSerializableFields(mode, skipGenerated: true).map(serializeField).map((e) => e.ident()).join("\n"));
    result.write("}");
    return result.toString();
  }



  String serializeEnumDefinition(GQEnumDefinition def) {
    return '''
enum ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{
${"\t"}${def.values.map(serializeEnumValue).join(" ")}
}
''';
  }

  String serializeEnumValue(GQEnumValue enumValue) {
    return '''
${enumValue.value} ${serializeDirectiveValueList(enumValue.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeField(GQField field) {
    return '''
${field.name}${serializeArgs(field.arguments)}: ${serializeType(field.type)} ${serializeDirectiveValueList(field.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeType(GQType gqType, {bool forceNullable = false}) {
    String nullableText =
        forceNullable ? '' : _getNullableText(gqType.nullable);
    if (gqType is GQListType) {
      return "[${serializeType(gqType.inlineType)}]${nullableText}";
    }
    return "${gqType.tokenInfo}${nullableText}";
  }

  String _getNullableText(bool nullable) => nullable ? "" : "!";

  String serializeArgs(List<GQArgumentDefinition> arguments) {
    if (arguments.isEmpty) {
      return "";
    }
    var result = arguments.map(serializeArgumentDefinition).join(", ");
    return "($result)";
  }

  String serializeArgumentValue(GQArgumentValue value) {
    return "${value.token.dolarEscape()}: ${"${value.value}".replaceFirst("\$", "\\\$")}";
  }

  String serializeInlineFragment(GQInlineFragmentDefinition def) {
    return """... on ${def.onTypeName} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))} ${serializeBlock(def.block)} """;
  }

  String serializeBlock(GQFragmentBlockDefinition def) {
    return """{${serializeListText(def.projections.values.map(serializeProjection).toList(), join: " ", withParenthesis: false)}}""";
  }

  String serializeFragmentDefinition(GQFragmentDefinition def) {
    return """fragment ${def.fragmentName} on ${def.onTypeName}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}${serializeBlock(def.block)}""";
  }

  String serializeFragmentDefinitionBase(GQFragmentDefinitionBase def) {
    if (def is GQFragmentDefinition) {
      return serializeFragmentDefinition(def);
    } else if (def is GQInlineFragmentDefinition) {
      return serializeInlineFragment(def);
    }
    throw "serialization of ${def.tokenInfo} is not supported yet";
  }

  String serializeProjection(GQProjection proj) {
    if (proj is GQInlineFragmentsProjection) {
      return serializeListText(
          proj.inlineFragments.map(serializeInlineFragment).toList(),
          join: " ",
          withParenthesis: false);
    }
    final buffer = StringBuffer();
    if (proj.isFragmentReference) {
      buffer.write("...");
    }
    if (proj.alias != null) {
      buffer.write(proj.alias);
      buffer.write(":");
    } else {
      buffer.write(proj.targetToken);
    }
    if (proj.getDirectives(skipGenerated: true).isNotEmpty) {
      buffer.write(serializeDirectiveValueList(proj.getDirectives(skipGenerated: true)));
    }

    if (proj.block != null) {
      buffer.write(serializeBlock(proj.block!));
    }
    return buffer.toString();
  }

  String serializeUnionDefinition(GQUnionDefinition def) {
    return "union ${def.tokenInfo} = ${serializeListText(def.typeNames.map((e) => e.token).toList(), withParenthesis: false, join: " | ")}";
  }

  String serializeQueryDefinition(GQQueryDefinition def) {
    return """${def.type.name} ${def.tokenInfo}${serializeListText(def.arguments.map(serializeArgumentDefinition).toList(), join: ",")}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{${serializeListText(def.elements.map(serializeQueryElement).toList(), join: " ", withParenthesis: false)}}""";
  }

  String serializeQueryElement(GQQueryElement def) {
    return """${def.escapedToken}${serializeListText(def.arguments.map(serializeArgumentValue).toList(), join: ",")}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}${def.block != null ? serializeBlock(def.block!) : ''}""";
  }
}
