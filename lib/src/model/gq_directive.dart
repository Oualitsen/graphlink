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
  FIELD_DEFINITION,
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
}

class GQDirectiveValue extends GQToken {
  final List<GQDirectiveScope> locations;
  final List<GQArgumentValue> arguments;

  GQDirectiveValue(String name, this.locations, this.arguments) : super(name);

  @override
  String serialize() {
    //don't serialize the gqTypeName directive
    if (token == GQGrammar.gqTypeNameDirective) {
      return "";
    }
    var args = arguments.isEmpty ? "" : "(${arguments.map((e) => e.serialize()).join(",")})";
    return "$token$args";
  }
}
