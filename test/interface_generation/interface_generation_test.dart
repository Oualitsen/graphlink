import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("Should generate all implemented interfaces", () {
    final text =
        File("test/interface_generation/interface_generation_test.graphql")
            .readAsStringSync();
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(text);

    expect(
        g.projectedInterfaces.keys, containsAll(["BasicEntity", "UserBase"]));
    var userBase = g.projectedInterfaces["UserBase"]!;
    expect(userBase.getInterfaceNames(), contains("BasicEntity"));
  });
}
