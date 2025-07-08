import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Object value test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.scalarDefinition().end());
    var result = parser.parse("""
      scalar Date 
    """);
    expect(result is Success, true);
    expect(result.value.token, "Date");
  });

  test("Object value test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.scalarDefinition().end());
    var result = parser.parse("""
      scalar Date @skip(if: true) @skip2(ifNot: 12
      )
    """);
    expect(result is Success, true);
    expect(result.value.token, "Date");
  });
}
