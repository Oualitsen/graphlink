import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

abstract class GqSerializer {
  final GQGrammar grammar;
  late final CodeGenerationMode mode;
  GqSerializer(this.grammar) : mode = grammar.mode;

  String serializeEnumDefinition(GQEnumDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeEnumDefinition(def);
  }

  String serialzeEnumValue(GQEnumValue value) {
    if (shouldSkipSerialization(directives: value.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeEnumValue(value);
  }

  String doSerializeEnumDefinition(GQEnumDefinition def);

  String doSerializeEnumValue(GQEnumValue value);

  String serializeField(GQField def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeField(def);
  }

  String doSerializeField(GQField def);
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]);

  String serializeInputDefinition(GQInputDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeInputDefinition(def);
  }

  String doSerializeInputDefinition(GQInputDefinition def);

  String serializeTypeDefinition(GQTypeDefinition def) {
    if (shouldSkipSerialization(directives: def.getDirectives(), mode: mode)) {
      return "";
    }
    return doSerializeTypeDefinition(def);
  }

  String doSerializeTypeDefinition(GQTypeDefinition def);

  String serializeDecorators(List<GQDirectiveValue> list, {String joiner = "\n"}) {
    var decorators = GQGrammarExtension.extractDecorators(directives: list, mode: grammar.mode);
    if (decorators.isEmpty) {
      return "";
    }
    return "${serializeListText(decorators, withParenthesis: false, join: joiner)}$joiner";
  }

  String? getTypeNameFromGQExternal(String token) {
    Object? typeWithDirectives = grammar.types[token] ?? grammar.projectedTypes[token] ?? grammar.interfaces[token]
     ?? grammar.inputs[token] ?? grammar.enums[token] ?? grammar.scalars[token];
      typeWithDirectives = typeWithDirectives as GqDirectivesMixin?;
     var result = typeWithDirectives?.getDirectiveByName(gqExternal)?.getArgValueAsString(gqExternalArg);
     if(result == null) {
      // check on typeMap
      return grammar.typeMap[token];
     }
     return result;

  }
}
