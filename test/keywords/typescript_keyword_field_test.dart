import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// TypeScript permits reserved words as object/class property names
/// (`{ default: string }` compiles), so a field named `default` must be left
/// UNCHANGED. This guards against over-sanitizing TS property names. Only
/// parameter/variable positions (query arguments) would ever need rewriting.
void main() {
  test("keyword field name is preserved (no sanitization for TS properties)",
      () {
    const schema = '''
      input FilterInput {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: typescriptReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    // field keeps the original name; no `default_` rewrite.
    expect(out, contains("default"));
    expect(out, isNot(contains("default_")));
    expect(out, contains("name"));
  });

  test("type keyword field name is preserved (no sanitization for TS)", () {
    const schema = '''
      type Expression {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: typescriptReservedWords);
    g.parse(schema);

    final type = g.types["Expression"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.doSerializeTypeDefinition(type);

    expect(out, contains("default"));
    expect(out, isNot(contains("default_")));
    expect(out, contains("name"));
  });

  test("leading underscore field name is preserved (no sanitization for TS)", () {
    const schema = '''
      input ProductInput {
        _links: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: typescriptReservedWords);
    g.parse(schema);

    final input = g.inputs["ProductInput"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    // TypeScript: leading underscore is fine, no rewrite.
    expect(out, contains("_links"));
    expect(out, isNot(contains("links_")));
    expect(out, contains("name"));
  });
}
