import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_directives_mixin.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';

class GQInputDefinition extends GQTokenWithFields with GQDirectivesMixin {
  GQInputDefinition(
      {required List<GQDirectiveValue> directives, required TokenInfo name, required List<GQField> fields})
      : super(name, fields) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $tokenInfo}';
  }
}
