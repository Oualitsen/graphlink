import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

const _preamble = '''
$kotlinJsonEncoderDecoder
$kotlinClientAdapterGql
''';

/// A query argument named after a Kotlin hard keyword (`object`) must become a
/// safe parameter (`object_`), while the variables-map key stays `object` to
/// match the `$object` reference in the query text.
void main() {
  test("keyword query argument: param sanitized, wire variable preserved", () {
    const text = '''
      type Person { id: ID! name: String! }
      type Query { getPerson(object: String!): Person }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: kotlinReservedWords,
    );
    g.parse(_preamble + text);

    final serializer =
        KotlinSerializer(g, importPrefix: 'com.example', generateJsonMethods: true);
    final out = KotlinClientSerializer(g, serializer)
            .getQueriesClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("object_: String"));
    expect(out, contains('"object" to'));
  });
}
