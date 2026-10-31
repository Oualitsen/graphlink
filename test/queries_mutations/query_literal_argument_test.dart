import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
enum Status { ACTIVE INACTIVE }
input Filter { limit: Int! status: Status }
type User { id: ID! username: String email: String }
type Query {
  findById(id: ID!): User
  list(status: Status!, limit: Int!): [User!]!
  search(filter: Filter!): [User!]!
  tagged(tags: [String!]!): [User!]!
}
''';

GLParser _parse(String operations) => GLParser()..parse('$_schema\n$operations');

Matcher _rejectsWith(String fragment) => throwsA(
    isA<ParseException>().having((e) => e.message, 'message', contains(fragment)));

void main() {
  group('literal arguments in a query', () {
    test('need no variable declaration', () {
      final g = _parse('query findUser0 { findById(id: "0") { id username email } }');
      final query = g.queries[const GLOperationKey('findUser0', GLQueryType.query)]!;
      expect(query.arguments, isEmpty);
    });

    test('can be mixed with variables', () {
      final g = _parse(r'query mixed($limit: Int!) { list(status: ACTIVE, limit: $limit) { id } }');
      final query = g.queries[const GLOperationKey('mixed', GLQueryType.query)]!;
      expect(query.arguments.map((a) => a.token), [r'$limit']);
    });

    test('accept an enum, an input object and a list', () {
      expect(
        () => _parse('''
          query a { list(status: INACTIVE, limit: 5) { id } }
          query b { search(filter: {limit: 3, status: ACTIVE}) { id } }
          query c { tagged(tags: ["x", "y"]) { id } }
        '''),
        returnsNormally,
      );
    });

    test('reject an argument the field does not declare', () {
      expect(
        () => _parse('query q { findById(idd: "0") { id } }'),
        _rejectsWith("Unknown argument 'idd'"),
      );
    });

    test('reject a value of the wrong scalar kind', () {
      expect(() => _parse('query q { findById(id: true) { id } }'), _rejectsWith("'ID'"));
      expect(() => _parse('query q { list(status: ACTIVE, limit: "5") { id } }'), _rejectsWith("'Int'"));
    });

    test('reject an undeclared enum value', () {
      expect(
        () => _parse('query q { list(status: BOGUS, limit: 5) { id } }'),
        _rejectsWith('BOGUS'),
      );
    });

    test('reject an input object missing a required field', () {
      expect(
        () => _parse('query q { search(filter: {status: ACTIVE}) { id } }'),
        _rejectsWith("'limit'"),
      );
    });

    test('reject null for a non-null argument', () {
      expect(() => _parse('query q { findById(id: null) { id } }'), _rejectsWith('null'));
    });

    test('name the argument in the error', () {
      expect(
        () => _parse('query q { list(status: ACTIVE, limit: "5") { id } }'),
        _rejectsWith("Argument 'limit' of 'list'"),
      );
    });
  });

  group('dollar signs inside literals', () {
    String serialize(String operation, {bool escapeDolar = true}) {
      final g = GLParser()..parse(r'''
        type Query { search(name: String!, limit: Int!): [User!]!  byFilter(f: Filter!): [User!]! }
        input Filter { a: String! b: String! }
        type User { id: ID! }
      ''' + '\n$operation');
      final query = g.queries.values.first;
      return GLGraphqlSerializer(g, escapeDolar).serializeQueryDefinition(query);
    }

    test('are not mistaken for variables', () {
      final g = GLParser()..parse(r'''
        type Query { search(name: String!, limit: Int!): [User!]! }
        type User { id: ID! }
        query q { search(name: "$a and $b", limit: 5) { id } }
      ''');
      expect(g.queries.values.first.arguments, isEmpty);
    });

    test('every one is escaped when the target needs it', () {
      expect(
        serialize(r'query q { search(name: "$a and $b", limit: 5) { id } }'),
        contains(r'name: "\$a and \$b"'),
      );
    });

    test('every one is escaped inside an input object literal', () {
      expect(
        serialize(r'query q { byFilter(f: {a: "$x", b: "$y"}) { id } }'),
        contains(r'{a: "\$x", b: "\$y"}'),
      );
    });

    test('are left alone when the target does not need escaping', () {
      expect(
        serialize(r'query q { search(name: "$a and $b", limit: 5) { id } }', escapeDolar: false),
        contains(r'name: "$a and $b"'),
      );
    });
  });
}
