import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("query definition auto generation on unions", () {
    final text = File("test/queries_auto_gen/queries_auto_gen_unions.graphql")
        .readAsStringSync();
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(text);

    expect(g.projectedTypes, contains("MyUnion"));
  });
}
