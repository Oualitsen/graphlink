import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQEnumDefinition extends GQExtensibleToken with GQDirectivesMixin {
  final Map<String, GQEnumValue> _values = {};

  GQEnumDefinition(
      {required TokenInfo token,
      required Iterable<GQEnumValue> values,
      required List<GQDirectiveValue> directives,
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
  void merge<T extends GQExtensibleToken>(T other) {
    if (other is GQEnumDefinition) {
      other.getDirectives().forEach(addDirective);
      other.values.forEach(addValue);
    }
  }
}

class GQEnumValue extends GQToken with GQDirectivesMixin {
  final TokenInfo value;
  final String? comment;

  GQEnumValue(
      {required this.value, required this.comment, required List<GQDirectiveValue> directives})
      : super(value) {
    directives.forEach(addDirective);
  }
}
