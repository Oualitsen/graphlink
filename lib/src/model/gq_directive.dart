import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQDirectiveDefinition {
  final String name;
  final List<GQArgumentDefinition> arguments;
  final Set<GQDirectiveScope> scopes;

  GQDirectiveDefinition(this.name, this.arguments, this.scopes);
}

enum GQDirectiveScope {
// ignore: constant_identifier_names
  QUERY,
  // ignore: constant_identifier_names
  MUTATION,
  // ignore: constant_identifier_names
  SUBSCRIPTION,
  // ignore: constant_identifier_names
  FIELD_DEFINITION,
  // ignore: constant_identifier_names
  FIELD,
  // ignore: constant_identifier_names
  FRAGMENT_DEFINITION,
  // ignore: constant_identifier_names
  FRAGMENT_SPREAD,
  // ignore: constant_identifier_names
  INLINE_FRAGMENT,
  // ignore: constant_identifier_names
  SCHEMA,
  // ignore: constant_identifier_names
  SCALAR,
  // ignore: constant_identifier_names
  OBJECT,

  // ignore: constant_identifier_names
  ARGUMENT_DEFINITION,
  // ignore: constant_identifier_names
  INTERFACE,
  // ignore: constant_identifier_names
  UNION,
  // ignore: constant_identifier_names
  ENUM,
  // ignore: constant_identifier_names
  ENUM_VALUE,
  // ignore: constant_identifier_names
  INPUT_OBJECT,
  // ignore: constant_identifier_names
  INPUT_FIELD_DEFINITION,
  // ignore: constant_identifier_names
  VARIABLE_DEFINITION
// ignore: constant_identifier_names
}

class GQDirectiveValue extends GQToken {
  final List<GQDirectiveScope> locations;
  final List<GQArgumentValue> arguments;
  final Map<String, GQArgumentValue> _argsMap = {};

  GQDirectiveValue(super.name, this.locations, this.arguments) {
    for (var arg in arguments) {
      _argsMap[arg.token] = arg;
    }
  }

  void setDefualtArguments(List<GQArgumentDefinition> args) {
    List<GQArgumentValue> argsToAdd = [];
    for (var argDef in args) {
      var argValue = _argsMap[argDef.token];
      if (argValue == null && argDef.initialValue != null) {
        var newArgValue = GQArgumentValue(argDef.token, argDef.initialValue);
        _argsMap[argDef.token] = newArgValue;
        argsToAdd.add(newArgValue);
      }
    }
    arguments.addAll(argsToAdd);
  }

  @override
  String serialize() {
    //don't serialize the gqTypeName directive
    if (GQGrammar.directivesToSkip.contains(token)) {
      return "";
    }
    var args = arguments.isEmpty ? "" : "(${arguments.map((e) => e.serialize()).join(",")})";
    return "$token$args";
  }
}
