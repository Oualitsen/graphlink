import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_scalar_definition.dart';
import 'package:graphlink/src/model/gl_schema.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_union.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/utils.dart';

const _skippedDirectives = {
  glDecorators,
  glSkipOnServer,
  glSkipOnClient,
  glServiceName,
  glTypeNameDirective,
  glEqualsHashcode,
  glExternal,
  glRepository,
  glCache,
  glCacheInvalidate,
};

bool _shouldSkipDriectiveDefinition(GLDirectiveDefinition def) {
  return _skippedDirectives.contains(def.name.token) ||
      def.arguments
          .where(
              (arg) => arg.token == glAnnotation && arg.type.token == "Boolean")
          .isNotEmpty;
}

bool _shouldSkipDriectiveValue(GLDirectiveValue def) {
  return _skippedDirectives.contains(def.token) ||
      GLParser.directivesToSkip.contains(def.token) ||
      def.getArgValueAsBool(glAnnotation);
}

// this is for skipping generating objects that should be hidden from the client
const clientMode = CodeGenerationMode.client;

class GLGraphqSerializer {
  final GLParser parser;
  final bool escapeDolar;

  GLGraphqSerializer(this.parser, [this.escapeDolar = true]);

  String generateSchema() {
    final buffer = StringBuffer();

    ///schema
    buffer.writeln(serializeSchemaDefinition(parser.schema));

    /// sacalars

    var scalars = filterSerialization(parser.scalars.values, clientMode)
        .where((s) => !parser.builtInScalars.contains(s.token))
        .map(serializeScalarDefinition)
        .join("\n");
    buffer.writeln(scalars);

    /// directives

    var directiveDefinitions = parser.directiveDefinitions.values
        .map(serializeDirectiveDefinition)
        .where((s) => s.isNotEmpty)
        .join("\n");

    buffer.writeln(directiveDefinitions);

    // inputs
    var inputSerial = filterSerialization(parser.inputs.values, clientMode)
        .map((e) => serializeInputDefinition(e, clientMode))
        .join("\n");
    buffer.writeln(inputSerial);

    // types
    var typesSerial = filterSerialization(parser.types.values, clientMode)
        .map((e) => serializeTypeDefinition(e, clientMode))
        .join("\n");
    buffer.writeln(typesSerial);
    // interfaces

    var interfacesSerial =
        filterSerialization(parser.interfaces.values, clientMode)
            .where((i) => !i.fromUnion)
            .map((e) => serializeTypeDefinition(e, clientMode))
            .join("\n");
    buffer.writeln(interfacesSerial);
    // enums
    var enumsSerial = filterSerialization(parser.enums.values, clientMode)
        .map(serializeEnumDefinition)
        .join("\n");
    buffer.writeln(enumsSerial);

    //unions
    var unionSerial =
        parser.unions.values.map(serializeUnionDefinition).join("\n");
    buffer.writeln(unionSerial);

    return buffer.toString();
  }

  String serializeScalarDefinition(GLScalarDefinition def) {
    return '''
scalar ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeDirectiveValueList(List<GLDirectiveValue> values) {
    return values.map(serializeDirectiveValue).join(" ");
  }

  String serializeDirectiveValue(GLDirectiveValue value) {
    if (_shouldSkipDriectiveValue(value)) {
      return '';
    }
    var arguments = value.getArguments();
    var args = arguments.isEmpty
        ? ""
        : "(${arguments.map((e) => serializeArgumentValue(e)).join(", ")})";
    return "${value.tokenInfo}$args";
  }

  String serializeDirectiveDefinition(GLDirectiveDefinition def) {
    // check if we should skip some directives
    if (_shouldSkipDriectiveDefinition(def)) {
      return '';
    }
    return '''
directive ${def.name}${serializeDirectiveArgs(def.arguments)} on ${def.scopes.map((e) => e.name).join(" | ")}
'''
        .trim();
  }

  String serializeDirectiveArgs(List<GLArgumentDefinition> arguments) {
    if (arguments.isEmpty) {
      return "";
    }
    var result = arguments.map(serializeArgumentDefinition).join(", ");
    return "($result)";
  }

  String serializeArgumentDefinition(GLArgumentDefinition def) {
    var buffer =
        StringBuffer("${_escapeDolar(def.token)}: ${serializeType(def.type)}");
    if (def.initialValue != null) {
      buffer.write(" = ${def.initialValue}");
    }
    return buffer.toString();
  }

  String _escapeDolar(String token) {
    if (escapeDolar) {
      return token.dolarEscape();
    }
    return token;
  }

  String serializeSchemaDefinition(GLSchema schema) {
    var inner = GLQueryType.values
        .where(
            (value) => parser.types.containsKey(schema.getByQueryType(value)))
        .map((value) {
      switch (value) {
        case GLQueryType.query:
          return "query: ${schema.getByQueryType(value)}";
        case GLQueryType.mutation:
          return "mutation: ${schema.getByQueryType(value)}";
        case GLQueryType.subscription:
          return "subscription: ${schema.getByQueryType(value)}";
      }
    });
    if (inner.isEmpty) {
      return "";
    }
    return '''
schema {
${inner.join("\n").ident()}
}
'''
        .trim();
  }

  String serializeInputDefinition(
      GLInputDefinition def, CodeGenerationMode mode) {
    return '''
input ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{
${def.getSerializableFields(mode, skipGenerated: true).map(serializeField).map((e) => e.ident()).join("\n")}
}
''';
  }

  String serializeTypeDefinition(
      GLTypeDefinition def, CodeGenerationMode mode) {
    String type;
    Iterable<String> interfaces =
        def.getInterfaceNames().where((i) => !parser.interfaces[i]!.fromUnion);
    if (def is GLInterfaceDefinition) {
      type = "interface";
    } else {
      type = "type";
    }

    var result = StringBuffer("$type ${def.tokenInfo}");
    if (interfaces.isNotEmpty) {
      result.write(" implements ");
      result.write(interfaces.join(" & "));
    }
    var directives =
        serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    if (directives.isNotEmpty) {
      result.write(" ");
      result.write(directives);
    }
    result.writeln(" {");
    result.writeln(def
        .getSerializableFields(mode, skipGenerated: true)
        .map(serializeField)
        .map((e) => e.ident())
        .join("\n"));
    result.write("}");
    return result.toString();
  }

  String serializeEnumDefinition(GLEnumDefinition def) {
    return '''
enum ${def.tokenInfo} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{
${"\t"}${def.values.map(serializeEnumValue).join(" ")}
}
''';
  }

  String serializeEnumValue(GLEnumValue enumValue) {
    return '''
${enumValue.value} ${serializeDirectiveValueList(enumValue.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeField(GLField field) {
    return '''
${field.name}${serializeArgs(field.arguments)}: ${serializeType(field.type)} ${serializeDirectiveValueList(field.getDirectives(skipGenerated: true))}
'''
        .trim();
  }

  String serializeType(GLType glType, {bool forceNullable = false}) {
    String nullableText =
        forceNullable ? '' : _getNullableText(glType.nullable);
    if (glType.isList) {
      return "[${serializeType(glType.inlineType)}]${nullableText}";
    }
    return "${glType.tokenInfo}${nullableText}";
  }

  String _getNullableText(bool nullable) => nullable ? "" : "!";

  String serializeArgs(List<GLArgumentDefinition> arguments) {
    if (arguments.isEmpty) {
      return "";
    }
    var result = arguments.map(serializeArgumentDefinition).join(", ");
    return "($result)";
  }

  String serializeArgumentValue(GLArgumentValue value) {
    var token = _escapeDolar(value.token);
    String val = "${value.value}";
    if (escapeDolar) {
      val = val.replaceFirst("\$", "\\\$");
    }
    return '${token}: ${val}';
  }

  String serializeInlineFragment(GLInlineFragmentDefinition def) {
    return """... on ${def.onTypeName} ${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))} ${serializeBlock(def.block)} """;
  }

  String serializeBlock(GLFragmentBlockDefinition def) {
    return """{${serializeListText(def.projections.values.map(serializeProjection).toList(), join: " ", withParenthesis: false)}}""";
  }

  String serializeFragmentDefinition(GLFragmentDefinition def) {
    return """fragment ${def.fragmentName} on ${def.onTypeName}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}${serializeBlock(def.block)}""";
  }

  String serializeFragmentDefinitionBase(GLFragmentDefinitionBase def) {
    if (def is GLFragmentDefinition) {
      return serializeFragmentDefinition(def);
    } else if (def is GLInlineFragmentDefinition) {
      return serializeInlineFragment(def);
    }
    throw "serialization of ${def.tokenInfo} is not supported yet";
  }

  String serializeProjection(GLProjection proj) {
    if (proj is GLInlineFragmentsProjection) {
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
      buffer.write(
          serializeDirectiveValueList(proj.getDirectives(skipGenerated: true)));
    }

    if (proj.block != null) {
      buffer.write(serializeBlock(proj.block!));
    }
    return buffer.toString();
  }

  String serializeUnionDefinition(GLUnionDefinition def) {
    return "union ${def.tokenInfo} = ${serializeListText(def.typeNames.map((e) => e.token).toList(), withParenthesis: false, join: " | ")}";
  }

  String serializeQueryDefinition(GLQueryDefinition def) {
    return """${def.type.name} ${def.tokenInfo}${serializeListText(def.arguments.map(serializeArgumentDefinition).toList(), join: ",")}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}{${serializeListText(def.elements.map(serializeQueryElement).toList(), join: " ", withParenthesis: false)}}""";
  }

  List<DividedQuery> divideQueryDefinition(
      GLQueryDefinition def, GLParser grammar) {
    var result = <DividedQuery>[];
    for (var element in def.elements) {
      final operationName =
          '${def.token}_${element.alias ?? ''}_${element.token}';
      var serialQuery = serializeQueryElement(element);
      final dq = DividedQuery(
        query: serialQuery,
        operationName: operationName,
        cacheTTL: element.cacheTTL,
        tags: element.cacheTags,
        elementKey: element.alias?.token ?? element.token,
        variables: [...element.arguments.map((e) => e.value?.toString() ?? '')],
        fragmentNames: element
            .getFragmentsAndDependecies(grammar)
            .map((e) => e.token)
            .toSet(),
        argumentDeclarations: element.arguments
            .map((arg) => "${arg.value}: ${serializeType(arg.type)}")
            .toList(),
        staleIfOffline: element
                .getDirectiveByName(glCache)
                ?.getArgValueAsBool(glCacheArgStaleIfOffline) ??
            false,
      );
      result.add(dq);
    }
    return result;
  }

  String serializeQueryElement(GLQueryElement def) {
    return """${def.escapedToken}${serializeListText(def.arguments.map(serializeArgumentValue).toList(), join: ",")}${serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}${def.block != null ? serializeBlock(def.block!) : ''}""";
  }
}

class DividedQuery {
  final String query;
  final String operationName;
  final List<String> variables;
  final String elementKey;
  final Set<String> fragmentNames;
  final List<String> argumentDeclarations;
  final int cacheTTL;
  final List<String> tags;
  final bool staleIfOffline;

  DividedQuery({
    required this.query,
    required this.operationName,
    required this.variables,
    required this.elementKey,
    required this.fragmentNames,
    required this.argumentDeclarations,
    required this.cacheTTL,
    required this.tags,
    required this.staleIfOffline,
  });
}
