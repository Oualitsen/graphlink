import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("non nullable type test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.typeTokenDefinition().end());
    var result = parser.parse('''
      String!
    ''');
    expect(result is Success, true);
    expect(result.value.nullable, false);
    var serializer = DartSerializer(g);

    expect(serializer.serializeType(result.value, false), "String");
  });

  test("nullable type test", () {
    final GQGrammar g = GQGrammar();

    var parser = g.buildFrom(g.simpleTypeTokenDefinition().end());
    var result = parser.parse('''
      String
    ''');
    expect(result is Success, true);
    expect(result.value.nullable, true);
    var serializer = DartSerializer(g);
    expect(serializer.serializeType(result.value, false) , "String?");
  });
}
