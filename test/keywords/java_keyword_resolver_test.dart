import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

const _preamble = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
''';

/// A query/mutation named after a Java keyword (`return`) must produce a safe
/// client method name (`return_`), while the GraphQL operation/wire name stays
/// the original `return` so the request still matches the schema field.
void main() {
  test("keyword query name: method sanitized, wire operation name preserved",
      () {
    const text = '''
      type Person { id: ID! name: String! }
      type Query { return(id: ID!): Person }
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

    // method name uses the safe identifier.
    expect(out, contains("return_("));
    // the wire operation name stays the original `return`.
    expect(out, contains('"return"'));
  });

  test("keyword mutation name: method sanitized, wire operation name preserved",
      () {
    const text = '''
      type Person { id: ID! name: String! }
      type Mutation { return(id: ID!): Person }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: javaReservedWords,
    );
    g.parse(_preamble + text);

    final serializer = JavaSerializer(g, importPrefix: "");
    final out = JavaClientSerializer(g, serializer)
            .getMutationsClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("return_("));
    expect(out, contains('"return"'));
  });
}
