import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// `object` is a hard keyword in Kotlin (unlike `default`, which is fine in
/// Kotlin). A field named `object` must be emitted as `object_`, while the
/// JSON wire key stays the original `object`.
void main() {
  test("keyword field is sanitized in decl/toJson/fromJson, wire preserved", () {
    const schema = '''
      input FilterInput {
        object: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.doSerializeInputDefinition(input);

    // declared property uses the safe identifier.
    expect(out, contains("object_"));
    expect(out, isNot(contains("val object:")));

    // toJson: wire key stays `object`, value reads the safe identifier.
    expect(out, contains('"object" to object_'));
    expect(out, contains('"name" to name'));

    // fromJson: named constructor arg uses safe identifier, wire key original.
    expect(out, contains('object_ = '));
    expect(out, contains('map["object"]'));
  });

  test("sanitized name avoids collision with an existing field", () {
    const schema = '''
      input FilterInput {
        object: String
        object_: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final input = g.inputs["FilterInput"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.doSerializeInputDefinition(input);

    expect(out, contains('"object" to object_2'));
    expect(out, contains('"object_" to object_'));
  });

  test("type (data class) keyword field is sanitized, wire preserved", () {
    const schema = '''
      type Expression {
        object: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final type = g.types["Expression"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.doSerializeTypeDefinition(type);
    print(out);
    expect(out, contains("object_"));
    expect(out, isNot(contains("val object:")));
    expect(out, contains('"object" to object_'));
    expect(out, contains('object_ = '));
    expect(out, contains('map["object"]'));
  });

  test("interface property for a keyword field is sanitized", () {
    const schema = '''
      interface ExpressionInterface {
        object: String
        name: String
      }

      type Expression implements ExpressionInterface {
        object: String
        name: String
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final iface = g.interfaces["ExpressionInterface"]!;
    final serializer =
        KotlinSerializer(g, importPrefix: "", generateJsonMethods: true);
    final out = serializer.doSerializeTypeDefinition(iface);

    expect(out, contains("val object_:"));
    expect(out, isNot(contains("val object:")));
  });
}
