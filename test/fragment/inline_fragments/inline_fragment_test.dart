import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() async {
  test("inline fragment test 1", () {
    final text =
        File("test/fragment/inline_fragments/inline_fragment_test.graphql").readAsStringSync();
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var serialize = DartSerializer(g);
    g.projectedTypes.values.forEach((pt) {
      print("############# ${pt.token} #############");
      print(serialize.serializeTypeDefinition(pt, ""));
    });
  });

  test("inline fragment test 2", () {
    final text =
        File("test/fragment/inline_fragments/inline_fragment_test2.graphql").readAsStringSync();
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var serialize = DartSerializer(g);
    for (var pt in g.projectedTypes.values) {
      print(serialize.serializeTypeDefinition(pt, ""));
    }
  });
}
