import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("inheritence test with naming", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fullGrammar().end());

    final text = File("test/inheritence/inheritance_projection_test.graphql").readAsStringSync();
    var result = parser.parse(text);
    expect(result is Success, true);
  });
}

enum Gender { male, femal }
