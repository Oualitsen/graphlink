import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("query definition auto generation inline projection on interfaces2", () {
    final text =
        File("test/queries_auto_gen/queries_auto_gen_interfaces.graphql")
            .readAsStringSync();
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(text);

    expect(g.queries.keys, contains("getProduct"));
    var getProduct = g.queries["getProduct"]!;
    expect(getProduct.tokenInfo, equals("getProduct"));
    expect(getProduct.elements.length, equals(1));
  });
}
