import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("All field fragments on interface/union as a projection", () {
    final text = File(
            "test/fragment/all_fields_fragments_interface_union_projections/all_fields_fragment_test.graphql")
        .readAsStringSync();
    var g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

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
