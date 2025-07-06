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
    expect(parsed is Success, true);

    var frag = g.fragments[GQGrammarExtension.allFieldsFragmentName("User")]!;

    expect(
        frag.dependecies.map((e) => e.token),
        containsAll([
          GQGrammarExtension.allFieldsFragmentName("Address"),
          GQGrammarExtension.allFieldsFragmentName("State"),
        ]));
  });

  test("all_fields_fragments_test with skip on client", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_skip_on_client_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var frag = g.fragments[GQGrammarExtension.allFieldsFragmentName("User")]!;
    expect(frag.block.projections.keys, isNot(contains("password")));
    expect(frag.block.projections.keys,
        containsAll(["firstName", "lastName", "middleName", "address", "username"]));
    print(frag);
  });

  test("all_fields_fragments_test with skip on client on interface", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_skip_on_client_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var frag = g.fragments[GQGrammarExtension.allFieldsFragmentName("UserBase")]!;
    expect(frag.block.projections.keys, isNot(contains("password")));
    print(frag);
  });
}
