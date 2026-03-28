import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("inheritence test with naming", () {
    final GLParser g = GLParser();

    final text = File("test/inheritence/inheritance_projection_test.graphql")
        .readAsStringSync();
    g.parse(text);
  });
}

enum Gender { male, femal }
