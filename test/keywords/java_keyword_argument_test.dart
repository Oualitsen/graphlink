import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

const _preamble = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
''';

/// A query argument named after a Java keyword (`default`) must become a safe
/// method parameter (`default_`), while the variables-map key stays `default`
/// to match the `$default` reference in the query text.
void main() {
  test("keyword query argument: param sanitized, wire variable preserved", () {
    const text = '''
      type Person { id: ID! name: String! }
      type Query { getPerson(default: String!): Person }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: javaReservedWords,
    );
    g.parse(_preamble + text);

    final serializer = JavaSerializer(g, importPrefix: "");
    final out = JavaClientSerializer(g, serializer)
            .getQueriesClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("String default_"));
    expect(out, contains('.put("default"'));
  });

  test("leading underscore argument: \$_links -> param links_", () {
    const text = '''
      type Product { id: ID! name: String! }
      type Query { getProduct(_links: String!): Product }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: javaReservedWords,
    );
    g.parse(_preamble + text);

    final serializer = JavaSerializer(g, importPrefix: "");
    final out = JavaClientSerializer(g, serializer)
            .getQueriesClass()
            ?.toFileContent() ??
        '';

    // method parameter: leading underscore moved to end.
    expect(out, contains("String links_"));
    // variables-map key stays the original wire name.
    expect(out, contains('.put("_links"'));
  });
}
