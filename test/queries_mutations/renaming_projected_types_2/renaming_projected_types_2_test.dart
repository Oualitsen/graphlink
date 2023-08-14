import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("renaming_projected_types_2", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/renaming_projected_types_2/renaming_projected_types_2_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed.isSuccess, true);
    var product = g.projectedTypes["Product"]!;
    var list = g.findSimilarTo(product);
    //print("list = ${list.first.token}");
    //renamed product input

    File("test/queries_mutations/renaming_projected_types_2/types.dart")
        .writeAsStringSync(g.generateTypes());
  });
}
