import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQScalarDefinition extends GQToken with GqDirectivesMixin {
 

  GQScalarDefinition({required TokenInfo token, required List<GQDirectiveValue> directives,}) : super(token) {
    directives.forEach(addDirective);
  }
  
}

