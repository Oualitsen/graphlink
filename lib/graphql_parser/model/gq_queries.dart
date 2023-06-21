import 'package:parser/graphql_parser/model/gq_directive.dart';
import 'package:parser/graphql_parser/model/gq_argument.dart';
import 'package:parser/graphql_parser/model/gq_field.dart';
import 'package:parser/graphql_parser/model/gq_fragment.dart';
import 'package:parser/graphql_parser/excpetions/parse_exception.dart';
import 'package:parser/graphql_parser/model/gq_token.dart';
import 'package:parser/graphql_parser/model/gq_type.dart';
import 'package:parser/graphql_parser/model/gq_type_definition.dart';
import 'package:parser/graphql_parser/utils.dart';

enum GQQueryType { query, mutation, subscription }

class GQQueryDefinition extends GQToken {
  final List<GQDirectiveValue> directives;
  final List<GQArgumentDefinition> arguments;
  final List<GQQueryElement> elements;
  final GQQueryType type; //query|mutation|subscription

  Set<GQFragmentDefinitionBase> get fragments {
    return elements
        .expand((e) => e.fragmentReferences)
        .expand((f) => {f, ...f.dependecies})
        .toSet();
  }

  GQQueryDefinition(
      super.token, this.directives, this.arguments, this.elements, this.type) {
    checkVariables();
  }

  void checkVariables() {
    for (var elem in elements) {
      checkElement(elem);
    }
  }

  void checkElement(GQQueryElement element) {
    var list = element.arguments;

    for (var arg in list) {
      if ("${arg.value}".startsWith("\$")) {
        var check = checkValue("${arg.value}");
        if (!check) {
          throw ParseException("Argument ${arg.value} was not declared");
        }
      }
    }
  }

  bool checkValue(String value) {
    for (var arg in arguments) {
      if (arg.token == value) {
        return true;
      }
    }
    return false;
  }

  @override
  String serialize() {
    return """${type.name} $token ${serializeList(arguments)} ${serializeList(directives)} {
        ${serializeList(elements, join: "\n\r", withParenthesis: false)}
      }
    """;
  }

  GQTypeDefinition generate() {
    return GQTypeDefinition(
      name: "${_capitilizedFirstLetterToken}Response",
      fields: _generateFields(),
      directives: directives,
      interfaceNames: {},
    );
  }

  String get _capitilizedFirstLetterToken {
    if (token.length == 1) {
      return token.toUpperCase();
    }
    return "${token[0].toUpperCase()}${token.substring(1)}";
  }

  List<GQField> _generateFields() {
    return elements
        .map((e) =>
            GQField(name: e.token, type: e.returnProjectedType, arguments: []))
        .toList();
  }

  GQArgumentDefinition findByName(String name) =>
      arguments.where((arg) => arg.token == name).first;
}

class GQQueryElement extends GQToken {
  final List<GQDirectiveValue> directives;
  final GQFragmentBlockDefinition? block;
  final List<GQArgumentValue> arguments;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  late final GQType returnType;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  GQTypeDefinition? projectedType;

  final Set<GQFragmentDefinitionBase> fragmentReferences = {};

  GQType _getReturnProjectedType(
      GQTypeDefinition? projectedType, GQType returnType) {
    if (projectedType == null) {
      return returnType;
    } else {
      if (returnType is GQListType) {
        return GQListType(
            _getReturnProjectedType(projectedType, returnType.type),
            returnType.nullable);
      } else {
        return GQType(projectedType.token, returnType.nullable,
            isScalar: false);
      }
    }
  }

  GQType get returnProjectedType =>
      _getReturnProjectedType(projectedType, returnType);

  GQQueryElement(super.token, this.directives, this.block, this.arguments);

  @override
  String serialize() {
    return """$_escapedToken ${serializeList(arguments, join: ", ")} ${serializeList(directives, join: " ")}
      ${block != null ? block!.serialize() : ''}""";
  }

  String get _escapedToken => token.replaceFirst("\$", "\\\$");
}
