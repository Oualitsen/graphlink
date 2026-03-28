import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("inline reference", () {
    final GLParser g = GLParser();

    final text =
        File("test/fragment/inline_reference/inline_reference_test.graphql")
            .readAsStringSync();

    g.parse(text);
  });
}
