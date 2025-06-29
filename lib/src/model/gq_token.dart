import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';

abstract class GQToken {
  final String token;
  GQToken(this.token);
  String serialize();
}

abstract class GQTokenWithFields extends GQToken {
  final List<GQField> fields;

  final _fieldNames = <String>{};
  final _serializableFields = <GQField>[];

  GQTokenWithFields(super.token, this.fields);

  bool hasField(String name) {
    return fieldNames.contains(name);
  }

  Set<String> get fieldNames {
    if (fields.isEmpty) {
      return {};
    }
    if (_fieldNames.isEmpty) {
      _fieldNames.addAll(fields.map((e) => e.name));
    }
    return _fieldNames;
  }

  List<GQField> getSerializableFields(GQGrammar grammar) {
    if (_serializableFields.isEmpty) {
      _serializableFields
          .addAll(fields.where((f) => !grammar.shouldSkipSerialization(directives: f.directives)));
    }
    return _serializableFields;
  }
}
