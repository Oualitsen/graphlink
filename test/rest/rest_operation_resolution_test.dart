import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = 'type Product { id: ID! name: String }\ninput PatchInput { name: String }\n';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

GLRestOperation _op(GLParser g, String name, GLQueryType type) =>
    g.restOperations[GLOperationKey(name, type)]!;

void main() {
  group('method and path', () {
    test('a query defaults to GET', () {
      final g = _parse('type Query { products: [Product!]! @glRest(path: "/products") }');
      expect(_op(g, 'products', GLQueryType.query).method, RestMethod.get);
      expect(_op(g, 'products', GLQueryType.query).path, '/products');
    });

    test('a mutation defaults to POST', () {
      final g = _parse('type Mutation { create(input: PatchInput! @glRestBody): Product @glRest(path: "/products") }');
      expect(_op(g, 'create', GLQueryType.mutation).method, RestMethod.post);
    });

    test('method can be overridden on the field', () {
      final g = _parse('''
        type Mutation {
          put(id: ID!): Product @glRest(path: "/products/{id}", method: PUT)
          remove(id: ID!): Product @glRest(path: "/products/{id}", method: DELETE)
        }''');
      expect(_op(g, 'put', GLQueryType.mutation).method, RestMethod.put);
      expect(_op(g, 'remove', GLQueryType.mutation).method, RestMethod.delete);
    });

    test('operations without any REST directive stay GraphQL', () {
      final g = _parse('type Query { graphqlOnly: Product  rest: Product @glRest(path: "/p") }');
      expect(g.restOperations.keys.map((k) => k.fieldName), ['rest']);
    });

    test('path is normalized: leading slash added, trailing slash dropped', () {
      final g = _parse('type Query { a: Product @glRest(path: "products/") }');
      expect(_op(g, 'a', GLQueryType.query).path, '/products');
    });

    test('a query and a mutation may share a name', () {
      final g = _parse('''
        type Query { item: Product @glRest(path: "/item") }
        type Mutation { item: Product @glRest(path: "/item") }''');
      expect(g.restOperations.length, 2);
    });
  });

  group('placeholders', () {
    test('are collected in path order', () {
      final g = _parse('type Query { p(shopId: ID!, id: ID!): Product @glRest(path: "/shops/{shopId}/products/{id}") }');
      expect(_op(g, 'p', GLQueryType.query).placeholders, ['shopId', 'id']);
    });
  });

  group('prefix', () {
    test('joins with exactly one slash', () {
      final g = _parse('''
        extend type Query @glRestPrefix(path: "/service/") { a: Product @glRest(path: "/x") }
        type Query { b: Product @glRest(path: "/b") }''');
      expect(_op(g, 'a', GLQueryType.query).path, '/service/x');
    });

    test('a field without @glRest uses the prefix alone', () {
      final g = _parse('''
        extend type Query @glRestPrefix(path: "/products") { products: [Product!]! }
        type Query { other: Product @glRest(path: "/o") }''');
      expect(_op(g, 'products', GLQueryType.query).path, '/products');
    });

    test('field path is appended to the prefix', () {
      final g = _parse('''
        extend type Query @glRestPrefix(path: "/products") { product(id: ID!): Product @glRest(path: "/{id}") }
        type Query { other: Product @glRest(path: "/o") }''');
      expect(_op(g, 'product', GLQueryType.query).path, '/products/{id}');
    });

    test('placeholders of the prefix and of the field are both collected', () {
      final g = _parse('''
        extend type Query @glRestPrefix(path: "/shops/{shopId}") { product(shopId: ID!, id: ID!): Product @glRest(path: "/{id}") }
        type Query { other: Product @glRest(path: "/o") }''');
      expect(_op(g, 'product', GLQueryType.query).placeholders, ['shopId', 'id']);
    });

    test('prefix method applies to the block, the field can override it', () {
      final g = _parse('''
        extend type Mutation @glRestPrefix(path: "/products", method: PUT) {
          rename(id: ID!): Product @glRest(path: "/{id}/name")
          create: Product @glRest(method: POST)
        }
        type Mutation { other: Product @glRest(path: "/o") }''');
      expect(_op(g, 'rename', GLQueryType.mutation).method, RestMethod.put);
      expect(_op(g, 'create', GLQueryType.mutation).method, RestMethod.post);
      expect(_op(g, 'other', GLQueryType.mutation).method, RestMethod.post);
    });
  });

  group('errors', () {
    void expectError(String schema, Pattern message) {
      expect(() => _parse(schema),
          throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
    }

    test('unknown method', () {
      expectError('type Query { a: Product @glRest(path: "/a", method: FETCH) }', 'FETCH');
    });

    test('@glRest without a path and without a prefix', () {
      expectError('type Query { a: Product @glRest }', 'path');
    });

    test('@glRest on a subscription', () {
      expectError('type Subscription { a: Product @glRest(path: "/a") }', 'subscription');
    });

    test('@glRest outside the Query and Mutation types', () {
      expectError('type Order { product: Product @glRest(path: "/a") }\ntype Query { x: Order }', 'Query');
    });

    test('@glRestPrefix on a type that is not Query or Mutation', () {
      expectError('extend type Product @glRestPrefix(path: "/a") { extra: String }', 'Query');
    });
  });
}
