import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("inline fragment test 1", () {
    final text =
        File("test/fragment/inline_fragments/inline_fragment_test.graphql")
            .readAsStringSync();
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse(text);

    var serialize = DartSerializer(g);
    for (var pt in g.projectedTypes.values) {
      print("############# ${pt.token} #############");
      print(serialize.serializeTypeDefinition(pt, ""));
    }
  });

  test("inline fragment test 2", () {
    final text =
        File("test/fragment/inline_fragments/inline_fragment_test2.graphql")
            .readAsStringSync();
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse(text);

    var serialize = DartSerializer(g);
    for (var pt in g.projectedTypes.values) {
      print(serialize.serializeTypeDefinition(pt, ""));
    }
  });
}
