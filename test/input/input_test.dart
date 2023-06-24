import 'dart:io';

import 'package:test/test.dart';
import 'package:logger/logger.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("Input transformation", () {
    var logger = Logger();
    final GQGrammar g = GQGrammar();
    logger.i(
        "________________________________________init______________________");

    var parser = g.buildFrom(g.fullGrammar().end());
    logger.i("reading file");

    final text = File("test/input/input_schema.graphql").readAsStringSync();
    logger.i("file read $test");
    var parsed = parser.parse(text);
    expect(parsed.isSuccess, true);
    expect(g.inputs.length, greaterThanOrEqualTo(1));
  });
}
