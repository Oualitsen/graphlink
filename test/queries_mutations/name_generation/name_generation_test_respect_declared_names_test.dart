import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("name_generation_test_respect_declared_names_test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/name_generation/name_generation_test_respect_declared_names_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);

    expect(parsed.isSuccess, true);
    expect(
        g.projectedTypes.values
            .where((element) => element.token != "ProductResponse")
            .map((e) => e.token)
            .toList(),
        containsAll(["P1", "P2"]));
  });
}
