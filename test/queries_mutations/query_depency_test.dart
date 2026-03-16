import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("query_depency_test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/queries_mutations/query_depency_test.graphql").readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(
        g.queries["ProductQuery"]!.fragments(g).map((e) => e.token), contains("ProductFragment"));
  });
}
