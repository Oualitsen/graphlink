import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() async {
  test("fragment projection test 1", () {
    final text = File("test/frag_ref/fragment_ref.graphql").readAsStringSync();
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var product = g.types['Product']!;
    expect(product.fieldNames, containsAll(["make", "name", "variant"]));

    var variant = g.types['Variant']!;
    expect(variant.fieldNames, containsAll(["make", "name", "model"]));
  });
}
