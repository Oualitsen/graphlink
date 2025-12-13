import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQUnionDefinition extends GQExtensibleToken with GQDirectivesMixin {
  final Map<String, TokenInfo> _typeNames = {};
  GQUnionDefinition(
      super.name, super.extension, List<TokenInfo> typeNames, List<GQDirectiveValue> directives) {
    typeNames.forEach(addTypeName);
    directives.forEach(addDirective);
  }

  void addTypeName(TokenInfo info) {
    if (_typeNames.containsKey(info.token)) {
      throw ParseException("${info} already declared for union ${token}");
    }
    _typeNames[info.token] = info;
  }

  List<TokenInfo> get typeNames => _typeNames.values.toList();

  @override
  void merge<T extends GQExtensibleToken>(T other) {
    if (other is GQUnionDefinition) {
      other.typeNames.forEach(addTypeName);
      other.getDirectives().forEach(addDirective);
    }
  }
}
