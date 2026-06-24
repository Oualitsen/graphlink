import 'package:graphlink/src/serializers/client_serializers/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// TypeScript passes query arguments as an object (`args: { default: string }`)
/// accessed via `args.default`. Reserved words are legal as property names and
/// in member access, so a `default` argument needs NO sanitization. This guards
/// against over-sanitizing TS parameters.
void main() {
  test("keyword query argument name is preserved (no sanitization for TS)", () {
    const text = '''
      type Person { id: ID! name: String! }
      type Query { getPerson(default: String!): Person }
    ''';

    final GLParser g = GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      reservedWords: typescriptReservedWords,
    );
    g.parse(text);

    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = TypeScriptClientSerializer(g, serializer)
            .getQueriesClass()
            ?.toFileContent() ??
        '';

    expect(out, contains("default"));
    expect(out, isNot(contains("default_")));
  });
}
