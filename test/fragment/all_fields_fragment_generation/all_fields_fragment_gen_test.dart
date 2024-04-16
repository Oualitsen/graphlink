import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("all_fields_fragments_test", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed.isSuccess, true);

    var frag = g.allFieldsFragments[GQGrammarExtension.allFieldsFragmentName("User")]!;

    expect(
        frag.fragment.dependecies.map((e) => e.token),
        containsAll([
          GQGrammarExtension.allFieldsFragmentName("Address"),
          GQGrammarExtension.allFieldsFragmentName("State"),
        ]));
  });
}
