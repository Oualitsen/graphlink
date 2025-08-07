import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("all_fields_without_type_name 1", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/fragment/all_fields_without_type_name/all_fields_without_type_name_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    var vehicleFrag = g.getFragmentByName("_all_fields_Vehicle")!;
    var depencyFragNames = vehicleFrag.dependecies.map((e) => e.token).toList();
    expect(parsed is Success, true);
    expect(depencyFragNames, contains("_all_fields_Make"));
  });
}
