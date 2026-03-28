import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("name_generation_fail_on_same_name_diffrent_types_test", () {
    final GLParser g = GLParser();

    final text = File(
            "test/queries_mutations/name_generation/name_generation_fail_on_same_name_diffrent_types_test.graphql")
        .readAsStringSync();
    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });
}
