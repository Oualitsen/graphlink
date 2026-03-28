import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Input transformation 3", () {
    final GLParser g = GLParser();

    final text =
        File("test/queries_mutations/schema.graphql").readAsStringSync();
    g.parse(text);

    expect(g.inputs.length, greaterThanOrEqualTo(1));
  });
}
