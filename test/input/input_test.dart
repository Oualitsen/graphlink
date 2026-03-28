import 'dart:io';

import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("Input transformation 1", () {
    var logger = Logger();
    final GLParser g = GLParser();
    logger.i(
        "________________________________________init______________________");

    logger.i("reading file");

    final text = File("test/input/input_schema.graphql").readAsStringSync();
    logger.i("file read $test");
    g.parse(text);

    expect(g.inputs.length, greaterThanOrEqualTo(1));
  });
}
