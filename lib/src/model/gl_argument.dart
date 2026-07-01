import 'package:graphlink/src/model/code_name_mixin.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_token.dart';

///
///  some thing like function(if: Boolean = true, name: String! = "Ahmed" ...)
///

class GLArgumentDefinition extends GLToken with GLDirectivesMixin, CodeNameMixin {
  final GLType type;
  final GLDefaultValue? defaultValue;

  /// False only for *propagated* (hoisted) field-argument variables added by
  /// `_addGeneratedArgument`; true for the operation's own declared variables.
  /// Drives the hoist-args pass, which extracts the non-declared ones into a
  /// synthesized `<Op>FieldArgs` input.
  final bool isDeclared;

  /// Set on the single synthetic argument that *replaces* the extracted
  /// propagated args (its [type] is the `<Op>FieldArgs` input). Non-null marks
  /// this arg for expansion back into flat wire variables by the query-string
  /// and variables-map serializers; null for every normal argument.
  GLInputDefinition? hoistArgsInput;

  GLArgumentDefinition(super.tokenInfo, this.type, List<GLDirectiveValue> directives,
      {this.defaultValue, this.isDeclared = true}) {
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

  @override
  String get wireName => bareName;
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