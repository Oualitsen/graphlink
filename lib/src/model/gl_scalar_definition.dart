import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLScalarDefinition extends GLExtensibleToken with GLDirectivesMixin {
  GLScalarDefinition({
    required TokenInfo token,
    required List<GLDirectiveValue> directives,
    required bool extension,
  }) : super(token, extension) {
    directives.forEach(addDirective);
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLScalarDefinition) {
      other.getDirectives().forEach(addDirective);
    }
  }
}
