import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_has_directives.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';

abstract class GqSerializer {
  final GQGrammar grammar;

  GqSerializer(this.grammar);

  String serializeEnumDefinition(GQEnumDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.getDirectives())) {
      return "";
    }
    return doSerializeEnumDefinition(def);
  }

  String serialzeEnumValue(GQEnumValue value) {
    if (grammar.shouldSkipSerialization(directives: value.getDirectives())) {
      return "";
    }
    return doSerialzeEnumValue(value);
  }

  String doSerializeEnumDefinition(GQEnumDefinition def);

  String doSerialzeEnumValue(GQEnumValue value);

  String serializeField(GQField def) {
    if (grammar.shouldSkipSerialization(directives: def.getDirectives())) {
      return "";
    }
    return doSerializeField(def);
  }

  String doSerializeField(GQField def);
  String serializeType(GQType def, bool forceNullable, [bool asArray = false]);

  String serializeInputDefinition(GQInputDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.getDirectives())) {
      return "";
    }
    return doSerializeInputDefinition(def);
  }

  String doSerializeInputDefinition(GQInputDefinition def);

  String serializeTypeDefinition(GQTypeDefinition def) {
    if (grammar.shouldSkipSerialization(directives: def.getDirectives())) {
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
