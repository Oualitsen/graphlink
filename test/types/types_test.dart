import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Types test", () {
    final GLGrammar g = GLGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());

    var parsed = parser.parse(File("test/types/types_schema.graphql").readAsStringSync());
    expect(parsed is Success, true);
    expect(g.types.length, greaterThanOrEqualTo(2));
    final db = g.types["DataBase"]!;
    expect(db.fieldNames, containsAll(["firstReleaseYear", "name", "noSQL"]));
  });
}
