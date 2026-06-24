import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A GraphQL field may legally be named after a target-language keyword
/// (e.g. `default`, which is reserved in Dart). The generated *identifier* must
/// be sanitized (e.g. `default_`) so the code compiles, while the *wire name*
/// (JSON key + GraphQL query text) must stay the original `default`.
void main() {
  test("keyword field is sanitized in decl/constructor/toJson/fromJson", () {
    const schema = '''
      input FilterInput {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeInputDefinition(input);
    final lines = out.split("\n").map((e) => e.trim());

    // declared property: `default` keyword -> `default_`.
    expect(lines, contains("final String? default_;"));
    expect(lines, contains("final String? name;"));

    // constructor uses the safe identifier.
    expect(lines, contains("this.default_,"));

    // toJson: wire key stays `default`, value reads the safe identifier.
    expect(lines, contains("'default': default_,"));
    expect(lines, contains("'name': name,"));

    // fromJson: safe param name, original wire key in the json lookup.
    expect(lines, contains("default_: json['default'] as String?,"));
    expect(lines, contains("name: json['name'] as String?,"));
  });

  test("sanitized name avoids collision with an existing field", () {
    // `default` -> `default_`, but `default_` already exists -> `default_2`.
    const schema = '''
      input FilterInput {
        default: String
        default_: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeInputDefinition(input);
    final lines = out.split("\n").map((e) => e.trim());

    expect(lines, contains("final String? default_2;"));
    expect(lines, contains("final String? default_;"));
    expect(lines, contains("'default': default_2,"));
    expect(lines, contains("'default_': default_,"));
    expect(lines, contains("default_2: json['default'] as String?,"));
    expect(lines, contains("default_: json['default_'] as String?,"));
  });

  test("interface getter for a keyword field is sanitized", () {
    const schema = '''
      interface ExpressionInterface {
        field: String
        operator: String
      }

      type Expression implements ExpressionInterface {
        field: String
        operator: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: dartReservedWords);
    g.parse(schema);

    final iface = g.interfaces["ExpressionInterface"]!;
    final type = g.types["Expression"]!;
    final serializer = DartSerializer(g, importPrefix: "");

    final ifaceLines =
        serializer.serializeInterface(iface).split("\n").map((e) => e.trim());
    // `operator` is a Dart keyword -> getter must be `operator_`.
    expect(ifaceLines, contains("String? get operator_;"));
    expect(ifaceLines, contains("String? get field;"));

    // the implementing type's field matches the sanitized getter.
    final typeOut = serializer.serializeTypeDefinition(type);
    expect(typeOut, contains("String? operator_;"));
    // wire key still original.
    expect(typeOut, contains("'operator': operator_,"));
  });
}
