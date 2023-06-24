import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("identifier test", () {
    var parser = g.buildFrom(g.identifier().end());
    var result = parser.parse(''' test12 ''');
    expect(result.isSuccess, true);
    result = parser.parse(''' 1test ''');
    expect(result.isSuccess, false);
  });

  test("simple type test", () {
    var parser = g.buildFrom(g.simpleTypeTokenDefinition().end());
    var result = parser.parse(''' test12 ''');
    expect(result.isSuccess, true);
    result = parser.parse(''' 1test ''');
    expect(result.isSuccess, false);

    result = parser.parse(''' test! ''');
    expect(result.isSuccess, true);
  });

  test("list type test", () {
    var parser = g.buildFrom(g.listTypeDefinition().end());
    var result = parser.parse(''' [test12] ''');
    expect(result.isSuccess, true);
    result = parser.parse(''' 1test ''');
    expect(result.isSuccess, false);

    result = parser.parse(''' [test]! ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' [test!]! ''');
    expect(result.isSuccess, true);
  });

  test(" type test", () {
    var parser = g.buildFrom(g.typeTokenDefinition().end());
    var result = parser.parse(''' [test12] ''');
    expect(result.isSuccess, true);
    result = parser.parse(''' 1test ''');
    expect(result.isSuccess, false);

    result = parser.parse(''' [test]! ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' [test!]! ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' test! ''');
    expect(result.isSuccess, true);

    result = parser.parse(''' test ''');
    expect(result.isSuccess, true);
  });
}
