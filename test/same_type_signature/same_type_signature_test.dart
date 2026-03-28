import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test(
      "same type signature should generate different classes when derrived from different types",
      () {
    final text = File("test/same_type_signature/same_type_signature.graphql")
        .readAsStringSync();
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

    expect(g.types.keys, containsAll(["Make", "Model"]));
  });
}
