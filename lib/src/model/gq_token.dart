import 'package:retrofit_graphql/src/model/gq_field.dart';

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

class Base {
  final String firstName;
  final String lastName;

  Base({required this.firstName, required this.lastName});
}

class Super extends Base {
  final String username;
  final String password;

  Super(
      {required this.username,
      required this.password,
      required final String firstName,
      required final String lastName})
      : super(firstName: firstName, lastName: lastName);
}
