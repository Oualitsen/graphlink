import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// `object` is a hard keyword in Kotlin. An enum value named `object` must
/// become a safe constant (`object_`). Because Kotlin's default toJson/fromJson
/// rely on `name` / `valueOf` (which couple the constant identifier to the wire
/// string), the generated code must map explicitly so the wire value stays
/// `object` while the constant is `object_`.
void main() {
  test("keyword enum value: constant sanitized, wire string preserved", () {
    const schema = '''
      enum FilterMode {
        object
        strict
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: `object` keyword -> `object_`.
    print(out);
    expect(out, contains("object_"));
    expect(out, contains("strict"));

    // the wire string `object` must round-trip through toJson/fromJson.
    expect(out, contains('"object"'));
  });

  test("keyword enum value 'return' -> return_, wire string preserved", () {
    const schema = '''
      enum Action {
        return
        cancel
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final def = g.enums["Action"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: `return` keyword -> `return_`.
    expect(out, contains("return_"));
    expect(out, contains("cancel"));

    // the wire string `return` must round-trip through toJson/fromJson.
    expect(out, contains('"return"'));
  });

  test("sanitized enum value avoids collision with an existing value", () {
    const schema = '''
      enum FilterMode {
        object
        object_
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.serializeEnumDefinition(def);

    expect(out, contains("object_2"));
    expect(out, contains('"object"'));
    expect(out, contains('"object_"'));
  });

  test("leading underscore enum value: _ACTIVE -> ACTIVE_", () {
    const schema = '''
      enum Status {
        _ACTIVE
        INACTIVE
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final def = g.enums["Status"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: leading underscore moved to end.
    expect(out, contains("ACTIVE_"));
    expect(out, contains("INACTIVE"));

    // the wire string `_ACTIVE` must still appear.
    expect(out, contains('"_ACTIVE"'));
  });
}
