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

  String serializeEnumDefinition(GQEnumDefinition def);
  String serializeField(GQField def);
  String serializeType(GQType def, bool forceNullable);
  String serializeInputDefinition(GQInputDefinition def);
  String serializeTypeDefinition(GQTypeDefinition def);

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
