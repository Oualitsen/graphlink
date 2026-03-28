import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("queries_generation_list_types_test", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/queries_generation_list_types_test.graphql")
        .readAsStringSync();
    g.parse(text);
  });
}
