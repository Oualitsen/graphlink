import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// TypeScript enum member names may be reserved words (they are treated as
/// property names), so a `default` enum value needs NO sanitization. This guards
/// against over-sanitizing TS enum members.
void main() {
  test("keyword enum value is preserved (no sanitization for TS)", () {
    const schema = '''
      enum FilterMode {
        default
        strict
      }
    ''';

    final GLParser g = GLParser(reservedWords: typescriptReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    expect(out, contains("default = 'default'"));
    expect(out, isNot(contains("default_")));
  });
}
