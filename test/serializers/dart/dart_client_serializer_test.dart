import 'package:retrofit_graphql/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("query methods should be comma separated", () {
    final GQGrammar g = GQGrammar(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson(id: ID!, name: String!): Person
  }

''';

    var parsed = g.parse(text);
    expect(parsed is Success, true);
    var serializer = DartSerializer(g);
    var clientSerializer = DartClientSerializer(g, serializer);

    var client = clientSerializer.generateClient("package");
    var lines = client.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
    expect(
        lines,
        containsAllInOrder([
          'Future<GetPersonResponse> getPerson({',
          'required String id,', // the trailing comma is what we are testing for
          'required String name'
        ]));
  });
}
