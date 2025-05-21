import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("type_looks_like_test", () {
    final text =
        File("test/all_fields_fragments/all_fields_fragment_test.graphql")
            .readAsStringSync();
    var g = GQGrammar(generateAllFieldsFragments: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.fragments.keys, contains("_all_fields_Animal"));
    var frag = g.fragments["_all_fields_Animal"]!;
    expect(frag.dependecies.map((d) => d.token).toList(),
        containsAll(["_all_fields_Cat", "_all_fields_Dog"]));
  });
}
