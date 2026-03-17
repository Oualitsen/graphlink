import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLEnumDefinition extends GLExtensibleToken with GLDirectivesMixin {
  final Map<String, GLEnumValue> _values = {};

  GLEnumDefinition(
      {required TokenInfo token,
      required Iterable<GLEnumValue> values,
      required List<GLDirectiveValue> directives,
      required bool extension})
      : super(token, extension) {
    values.forEach(addValue);

    directives.forEach(addDirective);
  }

  List<GLEnumValue> get values => _values.values.toList();

  void addValue(GLEnumValue value) {
    if (_values.containsKey(value.token)) {
      throw ParseException("${value.token} already defined on enum ${token}", info: value.tokenInfo);
    }
    _values[value.token] = value;
  }

  @override
  void merge<T extends GLExtensibleToken>(T other) {
    if (other is GLEnumDefinition) {
      other.getDirectives().forEach(addDirective);
      other.values.forEach(addValue);
    }
  }
}

class GLEnumValue extends GLToken with GLDirectivesMixin {
  final TokenInfo value;
  final String? comment;

  GLEnumValue({required this.value, required this.comment, required List<GLDirectiveValue> directives}) : super(value) {
    directives.forEach(addDirective);
  }
}
