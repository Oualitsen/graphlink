import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';

abstract class GQToken {
  final TokenInfo tokenInfo;
  GQToken(this.tokenInfo);
  String get token => tokenInfo.token;
}

abstract class GQTokenWithFields extends GQToken {
  final Map<String, GQField> _fieldMap = {};

  final _fieldNames = <String>{};

  List<GQField>? _skipOnClientFields;
  List<GQField>? _skipOnServerFields;

  GQTokenWithFields(super.tokenInfo, List<GQField> allFields) {
    allFields.forEach(addField);
  }

  void addField(GQField field) {
    if (_fieldMap.containsKey(field.name.token)) {
      throw ParseException("Duplicate field defition on type ${tokenInfo}, field: ${field.name}", info: field.name);
    }
    _fieldMap[field.name.token] = field;
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

  GQField findFieldByName(String fieldName, GQGrammar g) {
    var field = getFieldByName(fieldName);
    if (field == null) {
      if (fieldName == GQGrammar.typename) {
        return GQField(
          name: fieldName.toToken(),
          type: GQType(g.getLangType("String").toToken(), false),
          arguments: [],
          directives: [],
        );
      } else {
        throw ParseException("Could not find field '$fieldName' on type ${tokenInfo}", info: tokenInfo);
      }
    }
    return field;
  }

  Set<String> get fieldNames {
    if (fields.isEmpty) {
      return {};
    }
    if (_fieldNames.isEmpty) {
      _fieldNames.addAll(fields.map((e) => e.name.token));
    }
    return _fieldNames;
  }

  List<GQField> getSerializableFields(CodeGenerationMode mode, {bool skipGenerated = false}) {
    return fields
        .where((f) => !shouldSkipSerialization(directives: f.getDirectives(skipGenerated: skipGenerated), mode: mode))
        .toList();
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
