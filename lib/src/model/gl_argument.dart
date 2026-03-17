import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_token.dart';

///
///  some thing like function(if: Boolean = true, name: String! = "Ahmed" ...)
///

class GLArgumentDefinition extends GLToken with GLDirectivesMixin {
  final GLType type;
  final Object? initialValue;
  GLArgumentDefinition(super.tokenInfo, this.type, List<GLDirectiveValue> directives, {this.initialValue}) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'Argument{name: $tokenInfo, type: $type}';
  }

  String get dartArgumentName => tokenInfo.token.substring(1);
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
