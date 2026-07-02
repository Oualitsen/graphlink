import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// `default` is a reserved word in Java, so it cannot be used as a field name
/// or parameter. The generated identifier must be sanitized (`default_`) while
/// the JSON wire key stays the original `default`.
void main() {
  test("keyword field is sanitized in decl/toJson, wire key preserved", () {
    const schema = '''
      input FilterInput {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    // declared field uses the safe identifier.
    expect(out, contains("String default_;"));
    expect(out, contains("String name;"));

    // toJson: wire key stays `default`, value reads the safe identifier.
    expect(out, contains('map.put("default", default_)'));
    expect(out, contains('map.put("name", name)'));

    // fromJson is positional: the wire key must still be the original name.
    expect(out, contains('json.get("default")'));
  });

  test("sanitized name avoids collision with an existing field", () {
    const schema = '''
      input FilterInput {
        default: String
        default_: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    expect(out, contains("String default_2;"));
    expect(out, contains("String default_;"));
    expect(out, contains('map.put("default", default_2)'));
    expect(out, contains('map.put("default_", default_)'));
  });

  test("type (class) keyword field is sanitized, wire key preserved", () {
    const schema = '''
      type Expression {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final type = g.types["Expression"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeTypeDefinition(type);

    expect(out, contains("String default_;"));
    expect(out, contains('map.put("default", default_)'));
    expect(out, contains('json.get("default")'));
  });

  test("interface record-style accessor for a keyword field is sanitized", () {
    const schema = '''
      interface ExpressionInterface {
        default: String
        name: String
      }

      type Expression implements ExpressionInterface {
        default: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final iface = g.interfaces["ExpressionInterface"]!;
    // Record style emits the bare component name as the accessor (`default()`),
    // which must be sanitized.
    final serializer = JavaSerializer(g,
        importPrefix: "", typesAsRecords: true);
    final out = serializer.doSerializeTypeDefinition(iface);

    expect(out, contains("default_()"));
  });

  test("leading underscore: _links -> links_", () {
    const schema = '''
      input ProductInput {
        _links: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final input = g.inputs["ProductInput"]!;
    final serializer =
        JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    // property: leading underscore moved to end.
    expect(out, contains("String links_;"));
    expect(out, contains("String name;"));

    // toJson: wire key stays `_links`.
    expect(out, contains('map.put("_links", links_)'));
    expect(out, contains('map.put("name", name)'));

    // fromJson: wire key original.
    expect(out, contains('json.get("_links")'));
  });
}
