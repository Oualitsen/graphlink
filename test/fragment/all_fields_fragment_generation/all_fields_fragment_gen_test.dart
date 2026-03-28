import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("all_fields_fragments_test", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_test.graphql")
        .readAsStringSync();
    g.parse(text);

    var frag = g.fragments[GLGrammarExtension.allFieldsFragmentName("User")]!;

    expect(
        frag.dependecies.map((e) => e.token),
        containsAll([
          GLGrammarExtension.allFieldsFragmentName("Address"),
          GLGrammarExtension.allFieldsFragmentName("State"),
        ]));
  });

  test("all_fields_fragments_test with skip on client", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_skip_on_client_test.graphql")
        .readAsStringSync();
    g.parse(text);

    var frag = g.fragments[GLGrammarExtension.allFieldsFragmentName("User")]!;
    expect(frag.block.projections.keys, isNot(contains("password")));
    expect(
        frag.block.projections.keys,
        containsAll(
            ["firstName", "lastName", "middleName", "address", "username"]));
  });

  test("all_fields_fragments_test with skip on client on interface", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/all_fields_fragment_generation/all_fields_fragment_gen_skip_on_client_test.graphql")
        .readAsStringSync();
    g.parse(text);

    var frag =
        g.fragments[GLGrammarExtension.allFieldsFragmentName("UserBase")]!;
    expect(frag.block.projections.keys, isNot(contains("password")));
  });
}
