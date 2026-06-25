import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A query argument may be named after a target-language keyword (e.g.
/// `default`). The generated method parameter must be sanitized (`default_`),
/// while the GraphQL variable / variables-map key stays the original `default`
/// so it still matches the `$default` reference in the query text.
void main() {
  test("keyword query argument: param sanitized, wire variable preserved", () {
    const text = '''
      type Person {
        id: ID!
        name: String!
      }

      type Query {
        getPerson(default: String!): Person
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

    // method parameter uses the safe identifier.
    expect(out, contains("required String default_"));
    // variables-map key stays the original (matches `\$default` in the query).
    expect(out, contains("'default':"));
  });

  test("leading underscore argument: \$_links -> param links_", () {
    const text = '''
      type Product { id: ID! name: String! }
      type Query { getProduct(_links: String!): Product }
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

    // method parameter: leading underscore moved to end.
    expect(out, contains("required String links_"));
    // variables-map key stays the original wire name.
    expect(out, contains("'_links':"));
    // should NOT have _links as a param name.
    expect(out, isNot(contains("required String _links")));
  });
}
