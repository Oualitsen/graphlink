import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

String _client(GLParser parser) {
  final serializer = DartSerializer(parser, importPrefix: '');
  return DartClientSerializer(parser, serializer)
      .generateClient()
      .toFileContent();
}

GLParser _parser({
  int? maxFragmentBodySize = 8192,
  bool autoGenerateQueries = true,
}) =>
    GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: autoGenerateQueries,
      maxFragmentBodySize: maxFragmentBodySize,
    );

const _schema = '''
  type Query {
    getProduct(id: ID!): Product
    getCategory(id: ID!): Category
  }

  type Product {
    id: ID!
    name: String!
    price: Float!
  }

  type Category {
    id: ID!
    title: String!
  }
''';

void main() {
  group('oversized fragment skip', () {
    test('without size limit all-fields fragments and queries are generated',
        () {
      final p = _parser(maxFragmentBodySize: null)..parse(_schema);
      final client = _client(p);
      expect(client, contains("glFragMap__['_all_fields_Product']"));
      expect(client, contains("glFragMap__['_all_fields_Category']"));
      expect(client, contains('getProduct('));
      expect(client, contains('getCategory('));
    });

    test('with maxFragmentBodySize: 10 all fragments are skipped', () {
      final p = _parser(maxFragmentBodySize: 10)..parse(_schema);
      final client = _client(p);
      expect(client, isNot(contains('_all_fields_Product')));
      expect(client, isNot(contains('_all_fields_Category')));
    });

    test(
        'with maxFragmentBodySize: 10 auto-generated queries using oversized fragments are skipped',
        () {
      final p = _parser(maxFragmentBodySize: 10)..parse(_schema);
      final client = _client(p);
      expect(client, isNot(contains('Future<GetProductResponse> getProduct(')));
      expect(client, isNot(contains('Future<GetCategoryResponse> getCategory(')));
    });

    test('manually written queries without fragment dependencies are kept', () {
      const schema = '''
        type Query { getProduct(id: ID!): Product }
        type Product { id: ID! name: String! }
        query getProductById(\$id: ID!) { getProduct(id: \$id) { id name } }
      ''';
      final p = _parser(maxFragmentBodySize: 10)..parse(schema);
      expect(_client(p), contains('getProductById('));
    });
  });
}
