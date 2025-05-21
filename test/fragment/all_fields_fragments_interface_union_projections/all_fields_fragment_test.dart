import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("All field fragments on interface/union as a projection", () {
    final text =
        File("test/fragment/all_fields_fragments_interface_union_projections/all_fields_fragment_test.graphql")
            .readAsStringSync();
    var g = GQGrammar(generateAllFieldsFragments: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.fragments.keys,
        containsAll(["_all_fields_Animal", "_all_fields_Animal2"]));
    var allFieldAnimal = g.fragments["_all_fields_Animal"]!;
    expect(allFieldAnimal.dependecies.map((d) => d.token).toList(),
        containsAll(["_all_fields_Cat", "_all_fields_Dog"]));

    var allFieldAnimal2 = g.fragments["_all_fields_Animal2"]!;
    expect(allFieldAnimal2.dependecies.map((d) => d.token).toList(),
        containsAll(["_all_fields_Cat", "_all_fields_Dog"]));
  });
}
