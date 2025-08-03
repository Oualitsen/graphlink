import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Input transformation 2", () {
    final GQGrammar g = GQGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("test/interface/interface_schema.graphql").readAsStringSync();

    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.interfaces.length, greaterThanOrEqualTo(1));
    final i = g.interfaces["UserInput1"]!;
    expect(i.fieldNames, containsAll(["firstName", "lastName", "middleName"]));

    final i2 = g.interfaces["AddressInput1"]!;
    expect(i2.fieldNames, containsAll(["street", "wilayaId", "city"]));
    expect(i2.fieldNames,
        isNot(containsAll(["firstName1", "lastName1", "middleName1"])));
    expect(i2.getParentNames(), contains("UserInput1"));
  });
}
