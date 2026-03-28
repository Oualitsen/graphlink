import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  var logger = Logger();
  test("generate projection", () {
    final GLParser g = GLParser();

    g.parse(File(
            "test/types/genration/types_projection_generation_simple_case_schema.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");

    var serializer = DartSerializer(g);
    logger.i("""
    _______________ projected types _________________
    ${g.projectedTypes.values.map((e) => serializer.serializeTypeDefinition(e, "")).toList()}
    _________________________________________________

    _______________ inputs types _________________
    ${g.inputs.values.map((e) => serializer.serializeInputDefinition(e, "")).toList()}
    _________________________________________________


""");
  });

  test("projection fragment reference", () {
    final GLParser g = GLParser();

    g.parse(File(
            "test/types/genration/types_projection_generation_frag_ref.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");

    final serializer = DartSerializer(g);
    logger.i("""
    _______________ projected types _________________
    ${g.projectedTypes.values.map((e) => serializer.serializeTypeDefinition(e, "")).toList()}
    _________________________________________________

""");
  });

  test("All Fields fragment generation", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    g.parse(File(
            "test/types/genration/types_all_fields_fragments_generation.graphql")
        .readAsStringSync());
    logger.i("g.projectedTypes.length = ${g.projectedTypes.length}");

    expect(g.fragments.isEmpty, false);
  });

  test("test add all fields fragments to fragment depencies", () {
    final GLParser g = GLParser();

    g.parse(File(
            "test/types/genration/types_all_fields_fragments_dependecies.graphql")
        .readAsStringSync());

    expect(
        g
            .getFragmentByName("UserFields")!
            .dependecies
            .map((e) => e.token)
            .contains("AddressFields"),
        true);
  });

  test("test projection validation", () {
    final GLParser g = GLParser();

    expect(
        () => g.parse(
            File("test/types/genration/types_projection_validation.graphql")
                .readAsStringSync()),
        throwsA(isA<ParseException>()));
  });
}
