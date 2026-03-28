import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLDirectiveDefinition {
  final TokenInfo name;
  final List<GLArgumentDefinition> arguments;
  final Set<GLDirectiveScope> scopes;
  final bool repeatable;
  final String? documentation;

  GLDirectiveDefinition(
      TokenInfo name, this.arguments, this.scopes, this.repeatable,
      {this.documentation})
      : name = name.token.startsWith('@')
            ? name
            : name.ofNewName("@${name.token}");
}

enum GLDirectiveScope {
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

class GLDirectiveValue extends GLToken {
  final List<GLDirectiveScope> locations;
  final Map<String, GLArgumentValue> _argsMap = {};

  ///
  /// helps with the schema serialization
  ///
  final bool generated;

  GLDirectiveValue(
      TokenInfo tokenInfo, this.locations, List<GLArgumentValue> arguments,
      {required this.generated})
      : super(tokenInfo.token.startsWith('@')
            ? tokenInfo
            : tokenInfo.ofNewName('@${tokenInfo.token}')) {
    _addArgument(arguments);
  }

  void _addArgument(List<GLArgumentValue> arguments) {
    for (var arg in arguments) {
      _argsMap[arg.token] = arg;
    }
  }

  void setDefualtArguments(List<GLArgumentDefinition> args) {
    List<GLArgumentValue> argsToAdd = [];
    for (var argDef in args) {
      var argValue = _argsMap[argDef.token];
      if (argValue == null && argDef.initialValue != null) {
        var newArgValue =
            GLArgumentValue(argDef.tokenInfo, argDef.initialValue);
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

  bool getArgValueAsBool(String name) {
    var arg = getArgValue(name);
    if (arg == null) {
      return false;
    }
    return arg is bool ? arg : false;
  }

  String? getArgValueAsString(String name) {
    var value = getArgValue(name);
    if (value == null) {
      return null;
    }
    return (value as String).removeQuotes();
  }

  GLArgumentValue? getArgumentByName(String name) {
    return _argsMap[name];
  }

  void addArg(String name, Object? value) {
    _argsMap[name] = GLArgumentValue(TokenInfo.ofString(name), value);
  }

  List<GLArgumentValue> getArguments() {
    return _argsMap.values.toList();
  }

  static GLDirectiveValue createDirectiveValue(
      {required String directiveName,
      required bool generated,
      List<GLArgumentValue> args = const []}) {
    return GLDirectiveValue(TokenInfo.ofString(directiveName), [], args,
        generated: generated);
  }

  static GLDirectiveValue createDefaultCacheDirectiveValue(
      TokenInfo tokenInfo, int defaultTTL) {
    return GLDirectiveValue(
        tokenInfo.ofNewName(glCache),
        [],
        [
          GLArgumentValue(tokenInfo.ofNewName(glCacheTTL), defaultTTL),
        ],
        generated: true);
  }

  static GLDirectiveValue createCacheDirective(
      TokenInfo tokenInfo, int ttl, List<String> tags) {
    return GLDirectiveValue(
        tokenInfo.ofNewName(glCache),
        [],
        [
          GLArgumentValue(tokenInfo.ofNewName(glCacheTTL), ttl),
          GLArgumentValue(tokenInfo.ofNewName(glCacheTagList), tags),
        ],
        generated: true);
  }

  static GLDirectiveValue createInvalidateCacheDirective(
      TokenInfo tokenInfo, bool all, List<String> tags) {
    return GLDirectiveValue(
        tokenInfo.ofNewName(glCache),
        [],
        [
          GLArgumentValue(tokenInfo.ofNewName(glCacheArgAll), all),
          GLArgumentValue(tokenInfo.ofNewName(glCacheTagList), all ? [] : tags),
        ],
        generated: true);
  }

  static GLDirectiveValue createGqDecorators({
    required List<String> decorators,
    bool applyOnServer = true,
    bool applyOnClient = true,
    String? import,
  }) {
    return GLDirectiveValue(
        TokenInfo.ofString(glDecorators),
        [],
        [
          GLArgumentValue(TokenInfo.ofString("value"),
              decorators.map((s) => '"$s"').toList()),
          GLArgumentValue(TokenInfo.ofString(glApplyOnServer), applyOnServer),
          GLArgumentValue(TokenInfo.ofString(glApplyOnClient), applyOnClient),
          if (import != null)
            GLArgumentValue(TokenInfo.ofString(glImport), import),
        ],
        generated: true);
  }
}
