import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A GraphQL type/input/interface/enum may legally be named after a
/// target-language keyword (e.g. `default`, reserved in Java). Unlike field
/// names, this is a *declaration* identifier position — `public class default
/// { ... }` is a syntax error — so it must be sanitized (`default_`) the same
/// way a keyword field is, while the wire name (JSON `__typename`, GraphQL
/// query text) stays the original `default`.
void main() {
  test("keyword input name is sanitized", () {
    const schema = '''
      input default {
        id: ID
      }
      type Query { get(filter: default): String }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final input = g.inputs["default"]!;
    final serializer = JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeInputDefinition(input);

    expect(out, contains("class default_ {"));
    expect(out, isNot(contains("class default {")));
    expect(out, contains("public static default_ fromJson"));
  });

  test("keyword type name is sanitized", () {
    const schema = '''
      type default {
        id: ID!
      }
      type Query { get: default }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final type = g.types["default"]!;
    final serializer = JavaSerializer(g, importPrefix: "");
    final out = serializer.doSerializeTypeDefinition(type);

    expect(out, contains("class default_ {"));
    expect(out, isNot(contains("class default {")));
  });

  test("keyword interface name is sanitized, including the implements clause", () {
    const schema = '''
      interface default {
        id: ID!
      }
      type Concrete implements default {
        id: ID!
      }
      type Query { get: Concrete }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final iface = g.interfaces["default"]!;
    final concrete = g.types["Concrete"]!;
    final serializer = JavaSerializer(g, importPrefix: "");

    final ifaceOut = serializer.doSerializeTypeDefinition(iface);
    expect(ifaceOut, contains("interface default_ "));
    expect(ifaceOut, isNot(contains("interface default ")));

    final concreteOut = serializer.doSerializeTypeDefinition(concrete);
    expect(concreteOut, contains("implements default_"));
    expect(concreteOut, isNot(contains("implements default ")));
  });

  test("keyword enum name is sanitized", () {
    const schema = '''
      enum default {
        active
        inactive
      }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    final enumDef = g.enums["default"]!;
    final serializer = JavaSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(enumDef);

    expect(out, contains("enum default_ {"));
    expect(out, isNot(contains("enum default {")));
  });

  test("sanitized type name avoids collision with an existing type", () {
    const schema = '''
      type default {
        id: ID!
      }
      type default_ {
        id: ID!
      }
      type Query { a: default b: default_ }
    ''';

    final GLParser g = GLParser(reservedWords: javaReservedWords);
    g.parse(schema);

    expect(g.types["default"]!.codeName, "default_2");
    expect(g.types["default_"]!.codeName, "default_");
  });
}
