import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/utils.dart';

abstract class GqSerializer {
  final GQGrammar grammar;

  GqSerializer(this.grammar);

  String serializeEnumDefinition(GQEnumDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.directives)) {
      return "";
    }
    return doSerializeEnumDefinition(def);
  }

  String doSerializeEnumDefinition(GQEnumDefinition def);

  String serializeField(GQField def) {
    if (grammar.shouldSkipSerialization(directives: def.directives)) {
      return "";
    }
    return doSerializeField(def);
  }

  String doSerializeField(GQField def);
  String serializeType(GQType def, bool forceNullable);

  String serializeInputDefinition(GQInputDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.directives)) {
      return "";
    }
    return doSerializeInputDefinition(def);
  }

  String doSerializeInputDefinition(GQInputDefinition def);

  String serializeTypeDefinition(GQTypeDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.directives)) {
      return "";
    }
    return doSerializeTypeDefinition(def);
  }

  String doSerializeTypeDefinition(GQTypeDefinition def);

  String serializeDecorators(List<GQDirectiveValue> list) {
    var decorators = GQGrammarExtension.extractDecorators(directives: list, mode: grammar.mode);
    if (decorators.isEmpty) {
      return "";
    }
    return "${serializeListText(decorators, withParenthesis: false, join: " ")} ";
  }

  static String indentWithTabs(String text, int tabCount) {
    final tabs = '\t' * tabCount;
    return text.split('\n').map((line) => '$tabs$line').join('\n');
  }
}
