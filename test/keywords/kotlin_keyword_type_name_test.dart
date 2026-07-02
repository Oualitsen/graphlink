import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A GraphQL type/input/interface/enum may legally be named after a
/// target-language keyword (e.g. `object`, a hard keyword in Kotlin). Unlike
/// field names, this is a *declaration* identifier position — `data class
/// object(...)` is a syntax error — so it must be sanitized (`object_`) the
/// same way a keyword field is, while the wire name (JSON `__typename`,
/// GraphQL query text) stays the original `object`.
void main() {
  test("keyword input name is sanitized", () {
    const schema = '''
      input object {
        id: ID
      }
      type Query { get(filter: object): String }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final input = g.inputs["object"]!;
    final serializer = KotlinSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    expect(out, contains("data class object_("));
    expect(out, isNot(contains("data class object(")));
    expect(out, contains("fun fromJson(map: Map<String, Any?>): object_ = object_("));
  });

  test("keyword type name is sanitized", () {
    const schema = '''
      type object {
        id: ID!
      }
      type Query { get: object }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final type = g.types["object"]!;
    final serializer = KotlinSerializer(g, importPrefix: "");
    final out = serializer.doSerializeTypeDefinition(type);

    expect(out, contains("data class object_("));
    expect(out, isNot(contains("data class object(")));
  });

  test("keyword interface name is sanitized, including the implements clause", () {
    const schema = '''
      interface object {
        id: ID!
      }
      type Concrete implements object {
        id: ID!
      }
      type Query { get: Concrete }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final iface = g.interfaces["object"]!;
    final concrete = g.types["Concrete"]!;
    final serializer = KotlinSerializer(g, importPrefix: "");

    final ifaceOut = serializer.doSerializeTypeDefinition(iface);
    expect(ifaceOut, contains("interface object_ {"));
    expect(ifaceOut, isNot(contains("interface object {")));

    final concreteOut = serializer.doSerializeTypeDefinition(concrete);
    expect(concreteOut, contains(": object_"));
    expect(concreteOut, isNot(contains(": object ")));
  });

  test("keyword enum name is sanitized", () {
    const schema = '''
      enum object {
        active
        inactive
      }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    final enumDef = g.enums["object"]!;
    final serializer = KotlinSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(enumDef);

    expect(out, contains("enum class object_ {"));
    expect(out, isNot(contains("enum class object {")));
  });

  test("sanitized type name avoids collision with an existing type", () {
    const schema = '''
      type object {
        id: ID!
      }
      type object_ {
        id: ID!
      }
      type Query { a: object b: object_ }
    ''';

    final GLParser g = GLParser(reservedWords: kotlinReservedWords);
    g.parse(schema);

    expect(g.types["object"]!.codeName, "object_2");
    expect(g.types["object_"]!.codeName, "object_");
  });
}
