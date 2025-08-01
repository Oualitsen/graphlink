import 'dart:io';

import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';

void main() {
  var logger = Logger();
  test("generate projection", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.start());

    var parsed = parser.parse(File(
            "test/types/genration/types_projection_generation_simple_case_schema.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");
    expect(parsed is Success, true);
    var serializer = DartSerializer(g);
    logger.i("""
    _______________ projected types _________________
    ${g.projectedTypes.values.map((e) => serializer.serializeTypeDefinition(e)).toList()}
    _________________________________________________

    _______________ inputs types _________________
    ${g.inputs.values.map((e) => serializer.serializeInputDefinition(e)).toList()}
    _________________________________________________


""");
  });

  test("projection fragment reference", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.start());

    var parsed = parser.parse(File(
            "test/types/genration/types_projection_generation_frag_ref.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");
    expect(parsed is Success, true);
    final serializer = DartSerializer(g);
    logger.i("""
    _______________ projected types _________________
    ${g.projectedTypes.values.map((e) => serializer.serializeTypeDefinition(e)).toList()}
    _________________________________________________

""");
  });

  test("All Fields fragment generation", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parser = g.buildFrom(g.start());

    var parsed = parser.parse(File(
            "test/types/genration/types_all_fields_fragments_generation.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");
    expect(parsed is Success, true);
    expect(g.fragments.isEmpty, false);
  });

  test("test add all fields fragments to fragment depencies", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.start());

    var parsed = parser.parse(File(
            "test/types/genration/types_all_fields_fragments_dependecies.graphql")
        .readAsStringSync());
    expect(parsed is Success, true);
    expect(
        g
            .getFragment("UserFields")
            .dependecies
            .map((e) => e.token)
            .contains("AddressFields"),
        true);
  });

  test("test projection validation", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.start());
    expect(
        () => parser.parse(
            File("test/types/genration/types_projection_validation.graphql")
                .readAsStringSync()),
        throwsA(isA<ParseException>()));
  });
}
