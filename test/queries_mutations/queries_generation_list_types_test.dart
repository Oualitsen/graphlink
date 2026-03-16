import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("queries_generation_list_types_test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/queries_mutations/queries_generation_list_types_test.graphql")
        .readAsStringSync();
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });
}
