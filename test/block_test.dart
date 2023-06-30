import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:petitparser/debug.dart';

void main() {
  test("Fragment value test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentBlock().end());
    var result = parser.parse('''
        {
          ...name ... dob ... on merde
         }
    ''');
    expect(result.isSuccess, true);
  });

  test("Plain fragment field test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.fragmentBlock().end());
    var result = trace(parser).parse('''
        {
          name 
         }
    ''');
    expect(result.isSuccess, true);
  });
}
