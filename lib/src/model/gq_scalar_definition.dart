import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQScalarDefinition extends GQToken with GqDirectivesMixin {
 

  GQScalarDefinition({required String token, required List<GQDirectiveValue> directives,}) : super(token) {
    directives.forEach(addDirective);
  }

  @override
  String serialize() {
    throw UnimplementedError();
  }
}

