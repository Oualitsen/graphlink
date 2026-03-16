import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GLGrammar g = GLGrammar();

void main() async {
  test("same type signature should generate different classes when derrived from different types",
      () {
    final text = File("test/same_type_signature/same_type_signature.graphql").readAsStringSync();
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    expect(g.types.keys, containsAll(["Make", "Model"]));
  });
}
