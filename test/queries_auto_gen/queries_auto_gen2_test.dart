import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("query definition auto generation 2", () {
    final text = File("test/queries_auto_gen/queries_auto_gen2.graphql")
        .readAsStringSync();
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueries: true,
        defaultAlias: "data");

    g.parse(text);
  });
}
//String description String? id List<MatchedSubstring> matchedSubStrings String placeId String reference StructuredFormatting_mainText_mainTextMatchedSubstrings_secondaryText? structuredFormatting List<Term> terms List<String> types
//String description String? id List<MatchedSubstring> matchedSubStrings String placeId String reference StructuredFormatting? structuredFormatting List<Term> terms List<String> types
