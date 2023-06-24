import 'package:test/test.dart';
import 'package:retrofit_graphql/graphql_parser/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("Single quote String token", () {
    var parser = g.buildFrom(g.singleLineStringToken().end());
    var result = parser.parse('''"azul"''');
    expect(result.isSuccess, true);
    result = g.singleLineStringToken().parse('''"azul
    Fellawen
    "''');
    expect(result.isSuccess, false);
  });

  test("BlockString token Test", () {
    var parser = g.buildFrom(g.blockStringToken().end());
    var result = parser.parse('''""" Hello world """''');
    expect(result.isSuccess, true);
    result = g.singleLineStringToken().parse('''"""
    azul
    Fellawen
    """''');
    expect(result.isSuccess, true);
  });

  test("Boolean token test", () {
    var g = GQGrammar();
    var parser = g.buildFrom(g.boolean().end());
    var result = parser.parse("true");
    expect(result.isSuccess, true);
    result = parser.parse("false");
    expect(result.isSuccess, true);

    result = parser.parse("true1");

    expect(result.isSuccess, false);
  });

  test("Int token test", () {
    var parser = g.buildFrom(g.intParser().end());
    var result = parser.parse("0x1234");
    expect(result.isSuccess, true);
    result = g.intParser().parse("12");
    expect(result.isSuccess, true);

    result = g.intParser().parse("anything");
    expect(result.isSuccess, false);
  });

  test("Double token test", () {
    var parser = g.buildFrom(g.doubleParser().end());

    var result = parser.parse("0x123456.15");
    expect(result.isSuccess, false);
    result = parser.parse("12.12");
    expect(result.isSuccess, true);

    result = parser.parse("12");
    expect(result.isSuccess, true);

    result = parser.parse("anything");
    expect(result.isSuccess, false);
  });
}
