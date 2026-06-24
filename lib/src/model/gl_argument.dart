import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_token.dart';

///
///  some thing like function(if: Boolean = true, name: String! = "Ahmed" ...)
///

class GLArgumentDefinition extends GLToken with GLDirectivesMixin {
  final GLType type;
  final GLDefaultValue? defaultValue;
  GLArgumentDefinition(super.tokenInfo, this.type, List<GLDirectiveValue> directives, {this.defaultValue}) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'Argument{name: $tokenInfo, type: $type}';
  }

  String get dartArgumentName => tokenInfo.token.substring(1);

  /// The argument's bare name (the variable token without the leading `$`).
  /// This is the canonical wire name used as the GraphQL variable / variables
  /// map key, and the base for [codeName].
  String get bareName =>
      tokenInfo.token.startsWith('\$') ? tokenInfo.token.substring(1) : tokenInfo.token;

  /// Target-language-safe identifier for the generated parameter. Defaults to
  /// [bareName] and is overridden by the parser's code-name pass when the name
  /// collides with a reserved keyword (e.g. `default` -> `default_`). Only use
  /// this in *identifier* positions; the variables-map key / GraphQL variable
  /// must keep [bareName].
  String? _codeName;

  String get codeName => _codeName ?? bareName;

  set codeName(String value) => _codeName = value;
}

///
///  some thing like function(if: true, name: "Ahmed" ...)
///

class GLArgumentValue extends GLToken {
  Object? value;
  //this is not know at parse type, it must be set only once the grammer parsing is done.
  late final GLType type;
  GLArgumentValue(super.tokenInfo, this.value);

  @override
  String toString() {
    return 'GraphqlArgumentValue{value: $value name: $tokenInfo}';
  }
}


class GLDefaultValue {
  final Object? value;
  GLDefaultValue(this.value);
}