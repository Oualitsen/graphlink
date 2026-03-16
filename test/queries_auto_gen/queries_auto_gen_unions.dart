import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() async {
  test("query definition auto generation on unions", () {
    final text = File("test/queries_auto_gen/queries_auto_gen_unions.graphql").readAsStringSync();
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.projectedTypes, contains("MyUnion"));
  });
}
