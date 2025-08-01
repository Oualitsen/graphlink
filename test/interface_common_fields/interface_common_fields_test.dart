import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("common interface fields", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_test.graphql")
        .readAsStringSync();
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: false, autoGenerateQueries: false);

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var basicEntityInterface = g.projectedTypes["BasicEntity"]!;
    expect(basicEntityInterface.fieldNames.length, 2);
    expect(basicEntityInterface.fieldNames, containsAll(["id", "lastUpdate"]));
  });
}
