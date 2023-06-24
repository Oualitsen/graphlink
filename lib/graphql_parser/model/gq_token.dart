import 'package:retrofit_graphql/graphql_parser/model/gq_field.dart';

abstract class GQToken {
  final String token;
  GQToken(this.token);
  String serialize();
}

abstract class GQTokenWithFields extends GQToken {
  final List<GQField> fields;

  GQTokenWithFields(super.token, this.fields);

  bool hasField(String name) {
    return fields.map((e) => e.name).contains(name);
  }

  Set<String> get fieldNames => fields.map((e) => e.name).toSet();
}
