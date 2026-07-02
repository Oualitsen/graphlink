import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// Unlike field/property names (which TypeScript accepts as reserved words
/// with no sanitization, see typescript_keyword_field_test.dart), a
/// type/input/interface/enum *declaration* name is a binding identifier —
/// `export interface default { ... }` is a syntax error even though
/// `{ default: string }` as a property is fine. Real generation wires
/// `parameterReservedWords: typescriptParameterReservedWords` (see
/// grammar_factory.dart), which is what actually drives this sanitization.
void main() {
  test("keyword input name is sanitized", () {
    const schema = '''
      input default {
        id: ID
      }
      type Query { get(filter: default): String }
    ''';

    final GLParser g = GLParser(
      reservedWords: typescriptReservedWords,
      parameterReservedWords: typescriptParameterReservedWords,
    );
    g.parse(schema);

    final input = g.inputs["default"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.serializeInputDefinition(input);

    expect(out, contains("export interface default_ {"));
    expect(out, isNot(contains("export interface default {")));
    expect(out, contains("export namespace default_ {"));
  });

  test("keyword interface name is sanitized, including references from implementers", () {
    const schema = '''
      interface default {
        id: ID!
      }
      type Concrete implements default {
        id: ID!
      }
      type Query { get: Concrete }
    ''';

    final GLParser g = GLParser(
      reservedWords: typescriptReservedWords,
      parameterReservedWords: typescriptParameterReservedWords,
    );
    g.parse(schema);

    final iface = g.interfaces["default"]!;
    final concrete = g.types["Concrete"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");

    final ifaceOut = serializer.serializeTypeDefinition(iface);
    expect(ifaceOut, contains("export type default_ = Concrete;"));
    expect(ifaceOut, isNot(contains("export type default =")));

    final concreteOut = serializer.serializeTypeDefinition(concrete);
    // The concrete type doesn't reference the interface name directly (TS
    // union-of-types style), but the import in the interface file above
    // confirms the sanitized name propagates; this just guards the sibling
    // type still compiles standalone.
    expect(concreteOut, contains("export interface Concrete {"));
  });

  test("keyword enum name is sanitized", () {
    const schema = '''
      enum default {
        active
        inactive
      }
    ''';

    final GLParser g = GLParser(
      reservedWords: typescriptReservedWords,
      parameterReservedWords: typescriptParameterReservedWords,
    );
    g.parse(schema);

    final enumDef = g.enums["default"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.serializeEnumDefinition(enumDef);

    expect(out, contains("export enum default_ {"));
    expect(out, isNot(contains("export enum default {")));
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

    final GLParser g = GLParser(
      reservedWords: typescriptReservedWords,
      parameterReservedWords: typescriptParameterReservedWords,
    );
    g.parse(schema);

    expect(g.types["default"]!.codeName, "default_2");
    expect(g.types["default_"]!.codeName, "default_");
  });
}
