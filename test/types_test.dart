import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("identifier test 1", () {
    var parser = g.buildFrom(g.identifier().end());
    var result = parser.parse(''' test12 ''');
    expect(result is Success, true);
    result = parser.parse(''' 1test ''');
    expect(result is Success, false);
  });

  test("simple type test", () {
    var parser = g.buildFrom(g.simpleTypeTokenDefinition().end());
    var result = parser.parse(''' test12 ''');
    expect(result is Success, true);
    result = parser.parse(''' 1test ''');
    expect(result is Success, false);

    result = parser.parse(''' test! ''');
    expect(result is Success, true);
  });

  test("list type test", () {
    var parser = g.buildFrom(g.listTypeDefinition().end());
    var result = parser.parse(''' [test12] ''');
    expect(result is Success, true);
    result = parser.parse(''' 1test ''');
    expect(result is Success, false);

    result = parser.parse(''' [test]! ''');
    expect(result is Success, true);

    result = parser.parse(''' [test!]! ''');
    expect(result is Success, true);
  });

  test(" type test", () {
    var parser = g.buildFrom(g.typeTokenDefinition().end());
    var result = parser.parse(''' [test12] ''');
    expect(result is Success, true);
    result = parser.parse(''' 1test ''');
    expect(result is Success, false);

    result = parser.parse(''' [test]! ''');
    expect(result is Success, true);

    result = parser.parse(''' [test!]! ''');
    expect(result is Success, true);

    result = parser.parse(''' test! ''');
    expect(result is Success, true);

    result = parser.parse(''' test ''');
    expect(result is Success, true);
  });
}
