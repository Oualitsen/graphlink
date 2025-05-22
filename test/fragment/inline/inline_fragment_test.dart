/*import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  const folderPath = "test/fragment/inline";

  test("Simple projection", () {
    final GQGrammar g = GQGrammar();

    final text = File("$folderPath/inline_fragment_test.graphql").readAsStringSync();

    final parser = g.buildFrom(g.fullGrammar().end());
    final parsed = parser.parse(text);

    expect(parsed is Success, true);
  });
}
*/
