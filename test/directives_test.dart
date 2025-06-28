import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() {
  test("Directive value  test", () {
    var parser = g.buildFrom(g.directiveValue().end());
    var result = parser.parse('''
      @skip(if: true)
    ''');
    expect(result is Success, true);

    result = parser.parse('''
      @skip(if: [1 2, {name:"ramdane", age: 33}])
    ''');
    expect(result is Success, true);

    result = parser.parse('''@azul''');
    expect(result is Success, true);
  });

  test("Directive scopes test", () {
    var parser = g.buildFrom(g.directiveScopes().end());
    var result = parser.parse('''
    SCALAR|OBJECT|INTERFACE | ARGUMENT_DEFINITION
    ''');
    expect(result is Success, true);
  });

  test("Directive definition test", () {
    var parser = g.buildFrom(g.directiveDefinition().end());
    var result = parser.parse('''
    directive @test(test: String!, arg2: [String!]! ) on INTERFACE | ARGUMENT_DEFINITION
    ''');
    expect(result is Success, true);
  });

  test("Directive definition test2", () {
    var parser = g.buildFrom(g.directiveDefinition().end());
    var result = parser.parse('''
    directive @gqDecorator(value: String) on  OBJECT | INPUT_OBJECT| FIELD_DEFINITION | FIELD
    ''');
    expect(result is Success, true);
  });
}
