import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("fragment projection test 1", () {
    final text = File("test/frag_ref/fragment_ref.graphql").readAsStringSync();
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

    var product = g.types['Product']!;
    expect(product.fieldNames, containsAll(["make", "name", "variant"]));

    var variant = g.types['Variant']!;
    expect(variant.fieldNames, containsAll(["make", "name", "model"]));
  });
}
