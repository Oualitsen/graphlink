import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A query/mutation (resolver) may legally be named after a target-language
/// keyword (e.g. `return`, which is reserved in Dart). The generated client
/// *method name* must be sanitized (`return_`) so the code compiles, while the
/// GraphQL *operation/wire name* must stay the original `return` so the request
/// still matches the schema field on the server.
void main() {
  test("keyword query name: method sanitized, wire operation name preserved",
      () {
    const text = '''
      type Person {
        id: ID!
        name: String!
      }

      type Query {
        return(id: ID!): Person
      }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: dartReservedWords,
    );
    g.parse(text);

    final serializer = DartSerializer(g, importPrefix: "");
    final clientSerializer = DartClientSerializer(g, serializer);
    final out = clientSerializer.generateClient().toFileContent();

    // method name uses the safe identifier.
    expect(out, contains("return_("));
    // the wire operation name stays the original `return` (in the query text).
    expect(out, contains("query return"));
  });

  test("keyword mutation name: method sanitized, wire operation name preserved",
      () {
    const text = '''
      type Person {
        id: ID!
        name: String!
      }

      type Mutation {
        return(id: ID!): Person
      }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: dartReservedWords,
    );
    g.parse(text);

    final serializer = DartSerializer(g, importPrefix: "");
    final clientSerializer = DartClientSerializer(g, serializer);
    final out = clientSerializer.generateClient().toFileContent();

    // method name uses the safe identifier.
    expect(out, contains("return_("));
    // the wire operation name stays the original `return` (in the query text).
    expect(out, contains("mutation return"));
  });
}
