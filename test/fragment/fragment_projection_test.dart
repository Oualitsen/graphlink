import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("fragment projection test 2", () {
    final text = File("test/fragment/fragment_projection_test.graphql")
        .readAsStringSync();

    final GLParser g = GLParser();

    g.parse(text);
  });

  test("fragment projection test 3", () {
    final text =
        File("test/fragment/fragment_projection_mismatch_fragment_type.graphql")
            .readAsStringSync();

    final GLParser g = GLParser();

    expect(() => g.parse(text), throwsA(isA<ParseException>()));
  });
}
