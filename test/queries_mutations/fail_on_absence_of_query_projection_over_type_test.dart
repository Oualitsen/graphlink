import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("fail_on_absence_of_query_projection_over_type_test 1", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text =
        File("test/queries_mutations/fail_on_absence_of_query_projection_over_type_test.graphql")
            .readAsStringSync();
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
