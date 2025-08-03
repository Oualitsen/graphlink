import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Empty Array value test 2", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/schema.graphql").readAsStringSync();

    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });
}
