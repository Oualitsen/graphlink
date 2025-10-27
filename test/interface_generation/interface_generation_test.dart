import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("Should generate all implemented interfaces", () {
    final text = File("test/interface_generation/interface_generation_test.graphql").readAsStringSync();
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.projectedInterfaces.keys, containsAll(["BasicEntity", "UserBase"]));
    var userBase = g.projectedInterfaces["UserBase"]!;
    expect(userBase.getInterfaceNames(), contains("BasicEntity"));
  });
}
