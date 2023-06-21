import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parser/graphql_parser/excpetions/parse_exception.dart';
import 'package:parser/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("querries and mutations generation test", () {
    final GraphQlGrammar g = GraphQlGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("test/queries_mutations/queries_response_generation_test.graphql")
            .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed.isSuccess, true);
    g.saveToFiles(g);
  });
}
