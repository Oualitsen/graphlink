import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("depedecy_cycle_detection_test_indirect_dependency 1", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test.graphql")
            .readAsStringSync();
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });

  test("depedecy_cycle_detection_test_indirect_dependency 2", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File(
            "test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test_indirect_dependency.graphql")
        .readAsStringSync();
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
