import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/utils.dart';

enum GQQueryType { query, mutation, subscription }

class GQQueryDefinition extends GQToken {
  final List<GQDirectiveValue> directives;
  final List<GQArgumentDefinition> arguments;
  final List<GQQueryElement> elements;
  final GQQueryType type; //query|mutation|subscription
  Set<GQFragmentDefinitionBase>? _allFrags;

  GQTypeDefinition? _gqTypeDefinition;

  Set<String> get fragmentNames {
    return elements.expand((e) => e.fragmentNames).toSet();
  }

  Set<GQFragmentDefinitionBase> fragments(GQGrammar g) {
    if (_allFrags == null) {
      var frags = fragmentNames.map((e) => g.getFragment(e)).toSet();
      _allFrags = {...frags, ...frags.expand((e) => e.dependecies)};
    }
    return _allFrags!;
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
    return """${type.name} $token${serializeList(arguments, join: ",")}${serializeDirectives(directives)}{${serializeList(elements, join: " ", withParenthesis: false)}}""";
  }

  GQTypeDefinition getGeneratedTypeDefinition() {
    var gqDef = _gqTypeDefinition;
    if (gqDef == null) {
      _gqTypeDefinition = gqDef = GQTypeDefinition(
        name: _getGeneratedTypeName(),
        nameDeclared: getNameValueFromDirectives(directives) != null,
        fields: _generateFields(),
        directives: directives,
        interfaceNames: {},
        derivedFromType: null,
      );
    }
    return gqDef;
  }

  void updateTypeDefinition(GQTypeDefinition def) {
    _gqTypeDefinition = def;
  }

  String _getGeneratedTypeName() {
    return getNameValueFromDirectives(directives) ??
        "${_capitilizedFirstLetterToken}Response";
  }

  String get _capitilizedFirstLetterToken {
    if (token.length == 1) {
      return token.toUpperCase();
    }
    return "${token[0].toUpperCase()}${token.substring(1)}";
  }

  List<GQField> _generateFields() {
    return elements
        .map(
          (e) => GQField(
            name: e.alias ?? e.token,
            type: e.returnProjectedType,
            arguments: [],
            directives: e.directives,
          ),
        )
        .toList();
  }

  GQArgumentDefinition findByName(String name) =>
      arguments.where((arg) => arg.token == name).first;
}

class GQQueryElement extends GQToken {
  final List<GQDirectiveValue> directives;
  final GQFragmentBlockDefinition? block;

  final List<GQArgumentValue> arguments;
  final String? alias;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  late final GQType returnType;

  ///
  ///This is unknown on parse time. It is filled on run time.
  ///
  GQTypeDefinition? projectedType;

  String? projectedTypeKey;

  Set<String> get fragmentNames {
    if (block == null) {
      return {};
    }
    return _getFragmentNamesByBlock(block!);
  }

  Set<String> _getFragmentNamesByBlock(GQFragmentBlockDefinition block) {
    var set1 = block.projections.values
        .where((element) => element.isFragmentReference)
        .map((e) => e.fragmentName!)
        .toSet();
    var set2 = block.projections.values
        .where(
            (element) => !element.isFragmentReference && element.block != null)
        .map((e) => e.block!)
        .expand((element) => _getFragmentNamesByBlock(element))
        .toSet();
    return {...set1, ...set2};
  }

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

  GQQueryElement(
      super.token, this.directives, this.block, this.arguments, this.alias);

  @override
  String serialize() {
    return """$_escapedToken${serializeList(arguments, join: ",")}${serializeDirectives(directives)}${block != null ? block!.serialize() : ''}""";
  }

  String get _escapedToken {
    var aliasText = alias == null ? '' : "$alias:";
    return "$aliasText$token".replaceFirst("\$", "\\\$");
  }
}
