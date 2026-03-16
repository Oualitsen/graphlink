import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Object value test 1", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.scalarDefinition().end());
    var result = parser.parse("""
      scalar Date 
    """);
    expect(result is Success, true);
    expect(result.value.token, "Date");
  });

  test("Object value test 2", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.scalarDefinition().end());
    var result = parser.parse("""
      scalar Date @skip(if: true) @skip2(ifNot: 12
      )
    """);
    expect(result is Success, true);
    expect(result.value.token, "Date");
  });
}
