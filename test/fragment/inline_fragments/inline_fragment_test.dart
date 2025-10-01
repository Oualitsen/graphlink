import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("inline fragment test 1", () {
    final text = File("test/fragment/inline_fragments/inline_fragment_test.graphql").readAsStringSync();
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var serialize = DartSerializer(g);
    g.projectedTypes.values.forEach((pt) {
      print("############# ${pt.token} #############");
      print(serialize.serializeTypeDefinition(pt, ""));
    });
  });

  test("inline fragment test 2", () {
    final text = File("test/fragment/inline_fragments/inline_fragment_test2.graphql").readAsStringSync();
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var serialize = DartSerializer(g);
    for (var pt in g.projectedTypes.values) {
      print(serialize.serializeTypeDefinition(pt, ""));
    }
  });
}
