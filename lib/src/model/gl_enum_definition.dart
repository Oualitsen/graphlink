import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/token_info.dart';

class GLEnumDefinition extends GLExtensibleToken with GLDirectivesMixin {
  final Map<String, GQEnumValue> _values = {};

  GLEnumDefinition(
      {required TokenInfo token,
      required Iterable<GQEnumValue> values,
      required List<GLDirectiveValue> directives,
      required bool extension})
      : super(token, extension) {
    values.forEach(addValue);

    directives.forEach(addDirective);
  }

  List<GQEnumValue> get values => _values.values.toList();

  void addValue(GQEnumValue value) {
    if (_values.containsKey(value.token)) {
      throw ParseException("${value.token} already defined on enum ${token}",
          info: value.tokenInfo);
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

class GQEnumValue extends GLToken with GLDirectivesMixin {
  final TokenInfo value;
  final String? comment;

  GQEnumValue(
      {required this.value, required this.comment, required List<GLDirectiveValue> directives})
      : super(value) {
    directives.forEach(addDirective);
  }
}
