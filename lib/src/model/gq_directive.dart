import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

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
  ENUM_VALUE,
  // ignore: constant_identifier_names
  ENUM,
  
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
  final Map<String, GQArgumentValue> _argsMap = {};
  ///
  /// helps with the schema serialization
  ///
  final bool generated;

  GQDirectiveValue(
      super.name, this.locations, List<GQArgumentValue> arguments, {required this.generated}) {
    _addArgument(arguments);
  }

  void _addArgument(List<GQArgumentValue> arguments) {
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
    _addArgument(argsToAdd);
  }

  Object? getArgValue(String name) {
    var arg = _argsMap[name];
    return arg?.value;
  }

  String? getArgValueAsString(String name) {
    var value = getArgValue(name);
    if (value == null) {
      return null;
    }
    return (value as String).removeQuotes();
  }

  void addArg(String name, Object? value) {
    _argsMap[name] = GQArgumentValue(name, value);
  }

  List<GQArgumentValue> getArguments() {
    return _argsMap.values.toList();
  }

  static GQDirectiveValue createDirectiveValue(
      {required String directiveName, required bool generated}) {
    return GQDirectiveValue(directiveName, [], [], generated: generated);
  }

  static GQDirectiveValue createGqDecorators({
    required List<String> decorators,
    bool applyOnServer = true,
    bool applyOnClient = true,
  }) {
    return GQDirectiveValue(gqDecorators, [], [
      GQArgumentValue(
          "value", decorators.map((s) => '"$s"').toList()),
      GQArgumentValue("applyOnServer", applyOnServer),
      GQArgumentValue("applyOnClient", applyOnClient),
      
    ], generated: true);
  }
}
