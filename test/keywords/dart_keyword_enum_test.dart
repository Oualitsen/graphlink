import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A GraphQL enum may legally contain a value named after a target-language
/// keyword (e.g. `default`, reserved in Dart). The generated enum *constant*
/// must be sanitized (e.g. `default_`) so the code compiles, while the *wire
/// string* used in toJson/fromJson must stay the original `default`.
void main() {
  test("keyword enum value: constant sanitized, wire string preserved", () {
    const schema = '''
      enum FilterMode {
        default
        strict
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: `default` keyword -> `default_`.
    expect(out, contains("default_"));
    expect(out, contains("strict"));

    // toJson: returns the original wire string, not the sanitized identifier.
    expect(out, contains('return "default";'));
    expect(out, isNot(contains('return "default_";')));

    // fromJson: matches the original wire string, returns the safe constant.
    expect(out, contains('case "default":'));
    expect(out, contains('return default_;'));
  });

  test("sanitized enum value avoids collision with an existing value", () {
    // `default` -> `default_`, but `default_` already exists -> `default_2`.
    const schema = '''
      enum FilterMode {
        default
        default_
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final def = g.enums["FilterMode"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    expect(out, contains("default_2"));
    expect(out, contains('case "default":'));
    expect(out, contains('return default_2;'));
    expect(out, contains('case "default_":'));
    expect(out, contains('return default_;'));
  });

  test("leading underscore enum value: _ACTIVE -> ACTIVE_", () {
    const schema = '''
      enum Status {
        _ACTIVE
        INACTIVE
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final def = g.enums["Status"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(def);

    // enum constant: leading underscore moved to end.
    expect(out, contains("ACTIVE_"));
    expect(out, contains("INACTIVE"));

    // toJson: returns the original wire string, not the sanitized identifier.
    expect(out, contains('return "_ACTIVE";'));
    expect(out, isNot(contains('return "ACTIVE_";')));

    // fromJson: matches the original wire string, returns the safe constant.
    expect(out, contains('case "_ACTIVE":'));
    expect(out, contains('return ACTIVE_;'));
  });
}
