import 'dart:io';

import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("query definition auto generation 2", () {
    final text = File("test/queries_auto_gen/queries_auto_gen2.graphql").readAsStringSync();
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, autoGenerateQueries: true, defaultAlias: "data");
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });
}
//String description String? id List<MatchedSubstring> matchedSubStrings String placeId String reference StructuredFormatting_mainText_mainTextMatchedSubstrings_secondaryText? structuredFormatting List<Term> terms List<String> types
//String description String? id List<MatchedSubstring> matchedSubStrings String placeId String reference StructuredFormatting? structuredFormatting List<Term> terms List<String> types
