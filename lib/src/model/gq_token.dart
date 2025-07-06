import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';

abstract class GQToken {
  final String token;
  GQToken(this.token);
  String serialize();
}

abstract class GQTokenWithFields extends GQToken {
  final Map<String, GQField> _fieldMap = {};

  final _fieldNames = <String>{};
  final _serializableFields = <GQField>[];

  List<GQField>? _skipOnClientFields;
  List<GQField>? _skipOnServerFields;

  GQTokenWithFields(super.token, List<GQField> allFields) {
    allFields.forEach(addField);
  }

  void addField(GQField field) {
    _fieldMap[field.name] = field;
  }

  bool hasField(String name) {
    return fieldNames.contains(name);
  }

  List<GQField> get fields {
    return _fieldMap.values.toList();
  }

  GQField? getFieldByName(String name) {
    return _fieldMap[name];
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
          .addAll(fields.where((f) => !grammar.shouldSkipSerialization(directives: f.getDirectives())));
    }
    return _serializableFields;
  }

  void invalidateSerializableFieldsCache() {
    _serializableFields.clear();
  }

  List<GQField> getSkipOnServerFields() {
    return _skipOnServerFields ??= fields.where((field) {
      return field.getDirectives().where((d) => d.token == gqSkipOnServer).isNotEmpty;
    }).toList();
  }

  List<GQField> getSkinOnClientFields() {
    return _skipOnClientFields ??= fields.where((field) {
      return field.getDirectives().where((d) => d.token == gqSkipOnClient).isNotEmpty;
    }).toList();
  }
}
