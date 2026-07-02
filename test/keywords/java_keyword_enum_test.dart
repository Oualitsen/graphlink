import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A GraphQL enum value named after a Java keyword (`default`) must become a
/// safe enum constant (`default_`). Because Java's default toJson/fromJson rely
/// on `name()` / `valueOf()` (which couple the constant identifier to the wire
/// string), the generated code must map explicitly so the wire value stays
/// `default` while the constant is `default_`.
void main() {
  test("keyword enum value: constant sanitized, wire string preserved", () {
    const schema = '''
      enum FilterMode {
        default
        strict
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);
    print(out);

    // enum constant: `default` keyword -> `default_`.
    expect(out, contains("default_"));
    expect(out, contains("strict"));

    // the wire string `default` must round-trip through toJson/fromJson.
    expect(out, contains('"default"'));
  });

  test("sanitized enum value avoids collision with an existing value", () {
    const schema = '''
      enum FilterMode {
        default
        default_
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    expect(out, contains("default_2"));
    expect(out, contains('"default"'));
    expect(out, contains('"default_"'));
  });

  test("keyword enum value 'return' -> return_, wire string preserved", () {
    const schema = '''
      enum Action {
        return
        cancel
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final def = g.enums["Action"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: `return` keyword -> `return_`.
    expect(out, contains("return_"));
    expect(out, contains("cancel"));

    // the wire string `return` must round-trip through toJson/fromJson.
    expect(out, contains('"return"'));
  });

  test("leading underscore enum value: _ACTIVE -> ACTIVE_", () {
    const schema = '''
      enum Status {
        _ACTIVE
        INACTIVE
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final def = g.enums["Status"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: leading underscore moved to end.
    expect(out, contains("ACTIVE_"));
    expect(out, contains("INACTIVE"));

    // the wire string `_ACTIVE` must still appear.
    expect(out, contains('"_ACTIVE"'));
  });
}
