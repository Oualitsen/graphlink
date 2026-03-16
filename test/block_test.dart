import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:petitparser/debug.dart';

void main() {
  test("Fragment value test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fragmentBlock().end());
    var result = parser.parse('''
        {
          ...name ... dob ... on merde
         }
    ''');
    expect(result is Success, true);
  });

  test("Plain fragment field test", () {
    final GLGrammar g = GLGrammar();

    var parser = g.buildFrom(g.fragmentBlock().end());
    var result = trace(parser).parse('''
        {
          name 
         }
    ''');
    expect(result is Success, true);
  });
}
