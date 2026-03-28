import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("depedecy_cycle_detection_test_indirect_dependency 1", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test.graphql")
        .readAsStringSync();
    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });

  test("depedecy_cycle_detection_test_indirect_dependency 2", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    final text = File(
            "test/fragment/depedecy_cycle_detection/depedecy_cycle_detection_test_indirect_dependency.graphql")
        .readAsStringSync();
    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });
}
