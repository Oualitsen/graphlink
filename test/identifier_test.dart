
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {

  test("identifier test 1", () {
    final GQGrammar g = GQGrammar();
    var idParser = g.buildFrom(g.identifier().end());
    var result = idParser.parse('''
      value
      
    ''');
    expect(result is Success, true);
    expect(result.value.token, "value");
  });
  test("identifier test 2", () {
    final GQGrammar g = GQGrammar();
    var idParser = g.buildFrom(g.identifier().plus().end());
    var result = idParser.parse('''
      id
      id2 id3
      hello
      world
    '''.trim());
    expect(result is Success, true);
    expect(result.value.map((e) => e.token), containsAll(["id", "id2", "id3", "hello", "world"]));
  });

  test("identifier test 3", () {
    final GQGrammar g = GQGrammar();
    var idParser = g.buildFrom(g.identifier().end());
    var result = idParser.parse('''
      value # comment
      
    ''');
    expect(result is Success, true);
    expect(result.value.token, "value");
  });
}