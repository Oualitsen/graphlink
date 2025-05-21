import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("query definition auto generation on unions", () {
    final text = File("test/queries_auto_gen/queries_auto_gen_unions.graphql")
        .readAsStringSync();
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    print(g.generateTypes());
  });
}
