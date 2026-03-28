import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("fail_on_absence_of_query_projection_over_type_test 1", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/fail_on_absence_of_query_projection_over_type_test.graphql")
        .readAsStringSync();
    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });
}
