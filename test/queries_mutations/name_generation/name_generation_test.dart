import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("name_generation_test###", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/name_generation/name_generation_test.graphql")
        .readAsStringSync();
    g.parse(text);
  });
}
