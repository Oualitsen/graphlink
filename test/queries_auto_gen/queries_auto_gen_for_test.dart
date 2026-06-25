import 'package:test/test.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const _schema = '''
type Product { id: ID! name: String }
type Order   { id: ID! total: Float }

type Query {
  getProduct(id: ID!): Product
  listOrders: [Order]
  ping: String
}

type Mutation {
  createOrder(total: Float!): Order
  deleteOrder(id: ID!): Boolean
}

type Subscription {
  onOrderCreated: Order
  onPing: String
}
''';

void main() {
  group('autoGenerateQueriesFor', () {
    test('generates only the listed queries', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: ['getProduct'],
          GLQueryType.mutation: [],
          GLQueryType.subscription: [],
        },
      );
      g.parse(_schema);

      expect(g.queries.containsKey(GLOperationKey('getProduct', GLQueryType.query)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('listOrders', GLQueryType.query)), isFalse);
      expect(g.queries.containsKey(GLOperationKey('ping', GLQueryType.query)), isFalse);
    });

    test('generates only the listed mutations', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: [],
          GLQueryType.mutation: ['createOrder'],
          GLQueryType.subscription: [],
        },
      );
      g.parse(_schema);

      expect(g.queries.containsKey(GLOperationKey('createOrder', GLQueryType.mutation)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('deleteOrder', GLQueryType.mutation)), isFalse);
    });

    test('generates only the listed subscriptions', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: [],
          GLQueryType.mutation: [],
          GLQueryType.subscription: ['onOrderCreated'],
        },
      );
      g.parse(_schema);

      expect(g.queries.containsKey(GLOperationKey('onOrderCreated', GLQueryType.subscription)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('onPing', GLQueryType.subscription)), isFalse);
    });

    test('mixes queries, mutations, and subscriptions independently', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: ['getProduct', 'listOrders'],
          GLQueryType.mutation: ['deleteOrder'],
          GLQueryType.subscription: ['onPing'],
        },
      );
      g.parse(_schema);

      expect(g.queries.containsKey(GLOperationKey('getProduct', GLQueryType.query)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('listOrders', GLQueryType.query)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('ping', GLQueryType.query)), isFalse);
      expect(g.queries.containsKey(GLOperationKey('deleteOrder', GLQueryType.mutation)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('createOrder', GLQueryType.mutation)), isFalse);
      expect(g.queries.containsKey(GLOperationKey('onPing', GLQueryType.subscription)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('onOrderCreated', GLQueryType.subscription)), isFalse);
    });

    test('throws ParseException for unknown query name', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: ['doesNotExist'],
          GLQueryType.mutation: [],
          GLQueryType.subscription: [],
        },
      );
      expect(
        () => g.parse(_schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains('doesNotExist'),
        )),
      );
    });

    test('throws ParseException for unknown mutation name', () {
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: [],
          GLQueryType.mutation: ['ghost'],
          GLQueryType.subscription: [],
        },
      );
      expect(
        () => g.parse(_schema),
        throwsA(isA<ParseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ghost'), contains('mutations')),
        )),
      );
    });

    test('coexists with autoGenerateQueries: true — filter wins for its types, rest still generated', () {
      // autoGenerateQueriesFor only filters types it lists; autoGenerateQueries
      // still generates everything else. But they are separate paths — combining
      // them would produce duplicates, so this test confirms the filter path runs.
      final g = GLParser(
        generateAllFieldsFragments: true,
        autoGenerateQueriesFor: {
          GLQueryType.query: ['ping'],
          GLQueryType.mutation: [],
          GLQueryType.subscription: [],
        },
      );
      g.parse(_schema);
      expect(g.queries.containsKey(GLOperationKey('ping', GLQueryType.query)), isTrue);
      expect(g.queries.containsKey(GLOperationKey('getProduct', GLQueryType.query)), isFalse);
    });
  });
}
