import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A projected type's name can be pinned to an arbitrary string via
/// `@glTypeName(name: "...")` on a query/field selection — see
/// name_generation_test.graphql. That pinned name is documented as "honoured
/// as-is and left untouched" (gl_grammar_projection_extension.dart, around
/// `_assignCollisionFreeResponseStem`), which also means it currently skips
/// the keyword-safe pass entirely: [GLGrammarKeywordExtension.assignCodeNames]
/// only sanitizes `types`/`inputs`/`interfaces`/`unions`/`enums`, not
/// `projectedTypes`/`projectedInterfaces`. A schema pinning the name to a
/// reserved word (e.g. `class`) currently generates `class class { ... }`,
/// which is invalid Dart.
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

      query getProductQuery @glTypeName(name: "class") {
        getProduct { id name }
      }
    ''';

    final GLParser g =
        GLParser(reservedWords: dartReservedWords, autoGenerateQueries: false);
    g.parse(schema);

    final projected = g.projectedTypes["class"]!;
    final serializer = DartSerializer(g, importPrefix: "");
    final out = serializer.serializeTypeDefinition(projected);

    expect(out, contains("class class_ {"));
    expect(out, isNot(contains("class class {")));
    expect(out, contains("static class_ fromJson"));
  });
}
