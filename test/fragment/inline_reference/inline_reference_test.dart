import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("inline reference", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("test/fragment/inline_reference/inline_reference_test.graphql")
            .readAsStringSync();

    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });
}
