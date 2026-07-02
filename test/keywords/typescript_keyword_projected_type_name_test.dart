import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A projected type's name can be pinned to an arbitrary string via
/// `@glTypeName(name: "...")` on a query/field selection — see
/// name_generation_test.graphql. That pinned name is documented as "honoured
/// as-is and left untouched" (gl_grammar_projection_extension.dart, around
/// `_assignCollisionFreeResponseStem`), which also meant it used to skip the
/// keyword-safe pass entirely. Like declared type names (see
/// typescript_keyword_type_name_test.dart), a projected type/interface
/// *declaration* name is a binding identifier — `export interface default {
/// ... }` is a syntax error — so real generation wires
/// `parameterReservedWords: typescriptParameterReservedWords` (see
/// grammar_factory.dart) and this must be sanitized to `default_`.
void main() {
  test("keyword-pinned projected type name is sanitized", () {
    const schema = '''
      type Product {
        id: ID!
        name: String!
      }
      type Query {
        getProduct: Product
      }

      query getProductQuery @glTypeName(name: "default") {
        getProduct { id name }
      }
    ''';

    final GLParser g = GLParser(
      reservedWords: typescriptReservedWords,
      parameterReservedWords: typescriptParameterReservedWords,
      autoGenerateQueries: false,
    );
    g.parse(schema);

    final projected = g.projectedTypes["default"]!;
    final serializer = TypeScriptSerializer(g, importPrefix: "");
    final out = serializer.serializeTypeDefinition(projected);

    expect(out, contains("export interface default_ {"));
    expect(out, isNot(contains("export interface default {")));
    expect(out, contains("export namespace default_ {"));
  });
}
