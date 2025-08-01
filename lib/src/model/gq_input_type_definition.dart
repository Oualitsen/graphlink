import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQInputDefinition extends GQTokenWithFields with GqDirectivesMixin {
  GQInputDefinition(
      {required List<GQDirectiveValue> directives, required String name, required List<GQField> fields})
      : super(name, fields) {
    directives.forEach(addDirective);
  }

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $token}';
  }
  
}
