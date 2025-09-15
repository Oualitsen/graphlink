import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQScalarDefinition extends GQToken with GQDirectivesMixin {
  GQScalarDefinition({
    required TokenInfo token,
    required List<GQDirectiveValue> directives,
  }) : super(token) {
    directives.forEach(addDirective);
  }
}
