import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("query methods should be comma separated", () {
    final GLParser g =
        GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true);

    const text = '''
  type Person {
    id: ID!
    name: String!
  }

  type Query {
    getPerson(id: ID!, name: String!): Person
  }

''';

    g.parse(text);

    var serializer = DartSerializer(g);
    var clientSerializer = DartClientSerializer(g, serializer);

    var client = clientSerializer.generateClient("package");
    var lines =
        client.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
    expect(
        lines,
        containsAllInOrder([
          'Future<GetPersonResponse> getPerson({',
          'required String id,', // the trailing comma is what we are testing for
          'required String name'
        ]));
  });
}
