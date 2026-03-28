import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("renaming_projected_types_2", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/queries_mutations/renaming_projected_types_2/renaming_projected_types_2_test.graphql")
        .readAsStringSync();
    g.parse(text);

    var product = g.projectedTypes["Product"]!;
    var list = g.findSimilarTo(product);
    expect(list, isNotEmpty);
  });
}
