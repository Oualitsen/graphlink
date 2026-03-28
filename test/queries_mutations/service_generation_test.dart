import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Input transformation 4", () {
    final GLParser g = GLParser();

    final text =
        File("test/queries_mutations/simple_queries_service_generation.graphql")
            .readAsStringSync();
    g.parse(text);
  });
}
