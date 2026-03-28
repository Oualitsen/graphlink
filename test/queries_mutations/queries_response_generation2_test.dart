import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("querries and mutations generation test 2", () {
    final GLParser g = GLParser();

    final text =
        File("test/queries_mutations/queries_response_generation2_test.graphql")
            .readAsStringSync();
    g.parse(text);
  });
}
