import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQScalarDefinition extends GQExtensibleToken with GQDirectivesMixin {
  GQScalarDefinition({
    required TokenInfo token,
    required List<GQDirectiveValue> directives,
    required bool extension,
  }) : super(token, extension) {
    directives.forEach(addDirective);
  }

  @override
  void merge<T extends GQExtensibleToken>(T other) {
    if (other is GQScalarDefinition) {
      other.getDirectives().forEach(addDirective);
    }
  }
}
