import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQEnumDefinition extends GQToken with GqDirectivesMixin {
  List<GQEnumValue> values;

  GQEnumDefinition({required TokenInfo token, required this.values, required List<GQDirectiveValue> directives}) : super(token) {
    directives.forEach(addDirective);
  }
}

class GQEnumValue with GqDirectivesMixin {
  final TokenInfo value;
  final String? comment;

  GQEnumValue({required this.value, required this.comment, required List<GQDirectiveValue> directives}){
    directives.forEach(addDirective);
  }
}
