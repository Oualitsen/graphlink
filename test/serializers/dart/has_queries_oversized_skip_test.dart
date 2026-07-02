import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';

/// When every auto-generated query is skipped because its all-fields fragment
/// exceeds [maxFragmentBodySize], [GLParser.hasQueries] must return false.
/// Returning true causes the generated client to import a queries file that
/// would be empty, producing a compile error.
void main() {
  const schema = '''
    type Query { getProduct(id: ID!): Product }
    type Product { id: ID! name: String! price: Float! }
  ''';

  late GLParser parser;
  late String client;

  setUp(() {
    parser = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      maxFragmentBodySize: 10,
    )..parse(schema);

    final serializer = DartSerializer(parser, importPrefix: '');
    client = DartClientSerializer(parser, serializer)
        .generateClient()
        .toFileContent();
  });

  test('all auto-generated queries are skipped (no methods emitted)', () {
    expect(client, isNot(contains('getProduct(')));
  });

  test('hasQueries returns false when all queries were skipped', () {
    expect(parser.hasQueries, isFalse);
  });

  test('generated client does not import graph_link_queries.dart', () {
    expect(client, isNot(contains("import 'graph_link_queries.dart'")));
  });
}
