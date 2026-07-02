import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A projected type's name can be pinned to an arbitrary string via
/// `@glTypeName(name: "...")` on a query/field selection — see
/// name_generation_test.graphql. That pinned name is documented as "honoured
/// as-is and left untouched" (gl_grammar_projection_extension.dart, around
/// `_assignCollisionFreeResponseStem`), which also meant it used to skip the
/// keyword-safe pass entirely: [GLGrammarKeywordExtension.assignCodeNames]
/// only sanitized `types`/`inputs`/`interfaces`/`unions`/`enums`, not
/// `projectedTypes`/`projectedInterfaces`. A schema pinning the name to a
/// reserved word (e.g. `object`, a hard keyword in Kotlin) must now generate
/// `object_`, not `object`.
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

      query getProductQuery @glTypeName(name: "object") {
        getProduct { id name }
      }
    ''';

    final GLParser g = GLParser(
        reservedWords: kotlinReservedWords, autoGenerateQueries: false);
    g.parse(schema);

    final projected = g.projectedTypes["object"]!;
    final serializer = KotlinSerializer(g, importPrefix: "");
    final out = serializer.doSerializeTypeDefinition(projected);

    expect(out, contains("data class object_("));
    expect(out, isNot(contains("data class object(")));
    expect(out, contains("fun fromJson(map: Map<String, Any?>): object_ = object_("));
  });
}
