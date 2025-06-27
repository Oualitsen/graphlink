import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_token.dart';

class GQInputDefinition extends GQTokenWithFields {
  GQInputDefinition({required String name, required List<GQField> fields})
      : super(name, fields);

  @override
  String toString() {
    return 'InputType{fields: $fields, name: $token}';
  }

  @override
  String serialize() {
    return """
      input $token {
      
      }
    """;
  }
 
}
