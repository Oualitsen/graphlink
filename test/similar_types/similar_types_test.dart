import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("type_looks_like_test", () {
    final text = File("test/similar_types/similar_types_test.graphql")
        .readAsStringSync();
    var g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    var type1 = g.projectedTypes["Prduct1"]!;
    var type2 = g.projectedTypes["Prduct2"]!;
    expect(parsed is Success, true);
    expect(type1.isSimilarTo(type2), true);
  });
}
