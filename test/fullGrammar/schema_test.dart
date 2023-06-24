import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Empty Array value test", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/schema.graphql").readAsStringSync();

    var parsed = parser.parse(text);
    expect(parsed.isSuccess, true);
  });
}
