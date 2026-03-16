import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() async {
  test("fragment projection test 2", () {
    final text = File("test/fragment/fragment_projection_test.graphql").readAsStringSync();

    final GLGrammar g = GLGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
  });

  test("fragment projection test 3", () {
    final text =
        File("test/fragment/fragment_projection_mismatch_fragment_type.graphql").readAsStringSync();

    final GLGrammar g = GLGrammar();
    var parser = g.buildFrom(g.fullGrammar().end());
    expect(() => parser.parse(text), throwsA(isA<ParseException>()));
  });
}
