import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("fragment projection test 2", () {
    final text = File("test/fragment/fragment_projection_test.graphql")
        .readAsStringSync();

    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
  });

  test("fragment projection test 3", () {
    final text =
        File("test/fragment/fragment_projection_mismatch_fragment_type.graphql")
            .readAsStringSync();

    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
