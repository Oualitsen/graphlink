import 'dart:io';

import 'package:retrofit_graphql/graphql_parser/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("name_generation_fail_on_same_name_diffrent_types_test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/queries_mutations/name_generation/name_generation_fail_on_same_name_diffrent_types_test.graphql")
        .readAsStringSync();
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
