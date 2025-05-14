import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Type test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.typeDefinition().end());
    var result = parser.parse('''
      type Test2 implements Test {
        name: String!
        test: Boolean
        next: Test2
      }
    ''');
    expect(result is Success, true);

    result = parser.parse('''
      type Test3  {
        name: String!
        test: Boolean
        next: Test3
      }
    ''');
    expect(result is Success, true);

    result = parser.parse('''
      type Test4 @test(if: true) {
        name: String!
        test(test: Int!): [Boolean!]!
        next: [Test4!]
      }
    ''');
    expect(result is Success, true);
  });

  test("Type test with arguments", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.typeDefinition().end());
    var result = parser.parse('''
      type Test2 implements Test {
        name(test: String!): String!
        test: Boolean
        next: Test2
      }
    ''');
    expect(result is Success, true);
  });
}
