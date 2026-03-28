import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("type_looks_like_test 2", () {
    final text =
        File("test/base_types_and_unions/unions.graphql").readAsStringSync();
    var g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

    expect(g.projectedTypes.keys, containsAll(["Cat", "Dog_age_ownerName"]));
    expect(g.projectedInterfaces.keys, containsAll(["Animal"]));
  });
}
