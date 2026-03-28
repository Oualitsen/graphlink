import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Empty Array value test 2", () {
    final GLParser g = GLParser();

    final text = File("test/schema.graphql").readAsStringSync();

    g.parse(text);
  });
}
