import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Types test", () {
    final GLParser g = GLParser();

    g.parse(File("test/types/types_schema.graphql").readAsStringSync());

    expect(g.types.length, greaterThanOrEqualTo(2));
    final db = g.types["DataBase"]!;
    expect(db.fieldNames, containsAll(["firstReleaseYear", "name", "noSQL"]));
  });
}
