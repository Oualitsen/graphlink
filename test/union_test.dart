import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("Union serialization", () {
    var union = GQUnionDefinition("type", ["User"]);
    expect(union.serialize(), "union type = User");
  });

  test("Union serialization with multiple types", () {
    var union = GQUnionDefinition("type", ["User", "Client"]);
    expect(union.serialize(), "union type = User | Client");
  });

  test("Parse union", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom<GQUnionDefinition>(g.unionDefinition().end());
    var result = parser.parse('''
    union type = User | Client
    ''');
    expect(result.isSuccess, true);
    expect(result.value.token, "type");
    expect(result.value.typeNames.length, 2);
  });

  test("Parse union", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom<GQUnionDefinition>(g.unionDefinition().end());
    var result = parser.parse('''
    union type = User
    ''');
    expect(result.isSuccess, true);
    expect(result.value.token, "type");
    expect(result.value.typeNames.length, 1);
  });
}
