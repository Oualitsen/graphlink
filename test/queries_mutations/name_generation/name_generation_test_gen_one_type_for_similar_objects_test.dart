import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("name_generation_test_gen_one_type_for_similar_objects_test", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/name_generation/name_generation_test_gen_one_type_for_similar_objects_test.graphql")
        .readAsStringSync();
    g.parse(text);

    expect(
        g.projectedTypes.values
            .where((element) => element.token != "ProductResponse")
            .map((e) => e.tokenInfo)
            .toList(),
        hasLength(1));
  });
}
