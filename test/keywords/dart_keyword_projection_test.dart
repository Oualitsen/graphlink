import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A projected type is derived from a query selection set, not from a declared
/// `type`/`input`. A selected field named after a target-language keyword
/// (`default`) must still be sanitized in the generated projected class, while
/// the JSON wire key stays the original `default`.
void main() {
  test("keyword field in a projected type is sanitized, wire preserved", () {
    const schema = '''
      type Query { getUser: User }
      type User {
        id: ID!
        default: String
        name: String
      }
    ''';

    const query = '''
      query getUser {
        getUser {
          id
          default
          name
        }
      }
    ''';

    final GLParser g = GLParser(
      reservedWords: dartReservedWords,
      autoGenerateQueries: false,
      generateAllFieldsFragments: false,
    );
    g.parse(schema + query);

    // discover the projected type name
    final projected = g.projectedTypes.values.first;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeTypeDefinition(projected);
    final lines = out.split("\n").map((e) => e.trim());

    // declared property: `default` keyword -> `default_`.
    expect(lines, contains("final String? default_;"));

    // toJson: wire key stays `default`, value reads the safe identifier.
    expect(lines, contains("'default': default_,"));

    // fromJson: safe param name, original wire key in the json lookup.
    expect(lines, contains("default_: json['default'] as String?,"));
  });
}
