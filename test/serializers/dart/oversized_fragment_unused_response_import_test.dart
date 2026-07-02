import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

/// [GLClientSerializer.schemaTokensFor] (the import source) and
/// [GLClientSerializer.buildOperationMethods] (the method-body source) must
/// agree on which auto-generated operations are skipped for referencing an
/// oversized fragment. Before the fix, `schemaTokensFor` iterated every
/// operation of a type unconditionally, so a skipped operation's
/// `<Op>Response` / `<Op>FullResponse` types were still imported into
/// GraphLinkQueries even though the operation's method was dropped —
/// producing an unused import in the generated file.
void main() {
  const schema = '''
    type Query {
      getBigProduct(id: ID!): BigProduct
      getSimple(id: ID!): SimpleType
    }

    type BigProduct {
      id: ID!
      name: String!
      description: String!
      price: Float!
      sku: String!
      category: String!
    }

    type SimpleType {
      id: ID!
      name: String
    }
  ''';

  late String queriesFile;

  setUp(() {
    final parser = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      maxFragmentBodySize: 60,
    )..parse(schema);

    final serializer = DartSerializer(parser, importPrefix: '');
    final queriesClass =
        DartClientSerializer(parser, serializer).getQueriesClass()!;
    queriesFile =
        "${queriesClass.imports.join('\n')}\n\n${queriesClass.body}";
  });

  test('skipped operation method is not emitted', () {
    expect(queriesFile, isNot(contains('getBigProduct(')));
  });

  test('skipped operation does not import its Response type', () {
    expect(queriesFile, isNot(contains('get_big_product_response.dart')));
  });

  test('skipped operation does not import its FullResponse type', () {
    expect(queriesFile, isNot(contains('get_big_product_full_response.dart')));
  });

  test('kept operation still imports its Response/FullResponse types', () {
    expect(queriesFile, contains('getSimple('));
    expect(queriesFile, contains('get_simple_response.dart'));
    expect(queriesFile, contains('get_simple_full_response.dart'));
  });
}
