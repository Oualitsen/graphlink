import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';


GLParser _parse(String schema, {bool captureErrors = false}) {
  final g = GLParser(
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
    captureErrors: captureErrors,
  );
  g.parse(schema);
  return g;
}

String _client(GLParser g) =>
    DartClientSerializer(g, DartSerializer(g, importPrefix: "")).generateClient().toFileContent();

const _schema = '''
type User { id: ID!  name: String! }
input CreateUserInput { name: String! }

type Query {
  getUser(id: ID!): User! @glCaptureErrors
  listUsers: [User!]!
}

type Mutation {
  createUser(input: CreateUserInput!): User! @glCaptureErrors
  deleteUser(id: ID!): Boolean!
}
''';

void main() {
  group('@glCaptureErrors — validation', () {
    test('rejects on subscription field', () {
      const schema = '''
type User { id: ID! }
type Query { getUser: User! }
type Subscription { userAdded: User! @glCaptureErrors }
''';
      expect(() => _parse(schema), throwsA(isA<ParseException>()));
    });
  });

  group('@glCaptureErrors — isCaptureErrors', () {
    late GLParser g;
    setUpAll(() => g = _parse(_schema));

    test('returns true for annotated query', () => expect(g.queries[GLOperationKey('getUser', GLQueryType.query)]!.isCaptureErrors(g), isTrue));
    test('returns false for non-annotated query', () => expect(g.queries[GLOperationKey('listUsers', GLQueryType.query)]!.isCaptureErrors(g), isFalse));

    test('returns true for all operations when global flag is set', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final g2 = _parse(schema, captureErrors: true);
      expect(g2.queries[GLOperationKey('getUser', GLQueryType.query)]!.isCaptureErrors(g2), isTrue);
      expect(g2.queries[GLOperationKey('deleteUser', GLQueryType.mutation)]!.isCaptureErrors(g2), isTrue);
    });
  });

  group('@glCaptureErrors — FullResponse type', () {
    late GLParser g;
    setUpAll(() => g = _parse(_schema));

    test('has correct name', () {
      expect(g.queries[GLOperationKey('getUser', GLQueryType.query)]!.getFullResponseTypeDefinition(g).token, equals('GetUserFullResponse'));
    });

    test('has nullable data field typed as the regular response', () {
      final dataField = g.queries[GLOperationKey('getUser', GLQueryType.query)]!
          .getFullResponseTypeDefinition(g)
          .getSerializableFields(g.mode)
          .firstWhere((f) => f.name.token == 'data');
      expect(dataField.type.nullable, isTrue);
      expect(dataField.type.token, equals('GetUserResponse'));
    });

    test('has nullable errors field', () {
      final errorsField = g.queries[GLOperationKey('getUser', GLQueryType.query)]!
          .getFullResponseTypeDefinition(g)
          .getSerializableFields(g.mode)
          .firstWhere((f) => f.name.token == 'errors');
      expect(errorsField.type.nullable, isTrue);
    });

    test('regular Response is unmodified — no errors field', () {
      final fieldNames = g.queries[GLOperationKey('getUser', GLQueryType.query)]!
          .getGeneratedTypeDefinition()
          .getSerializableFields(g.mode)
          .map((f) => f.name.token);
      expect(fieldNames, isNot(contains('errors')));
    });
  });

  group('@glCaptureErrors — generated client', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('captureErrors query returns FullResponse', () => expect(client, contains('Future<GetUserFullResponse> getUser(')));
    test('captureErrors mutation returns FullResponse', () => expect(client, contains('Future<CreateUserFullResponse> createUser(')));
    test('non-captureErrors query returns regular response', () => expect(client, contains('Future<ListUsersResponse> listUsers(')));
    test('non-captureErrors mutation returns regular response', () => expect(client, contains('Future<DeleteUserResponse> deleteUser(')));

    test('captureErrors query does not throw on errors', () {
      final start = client.indexOf('Future<GetUserFullResponse> getUser(');
      final end = client.indexOf('Future<', start + 1);
      expect(client.substring(start, end), isNot(contains('throw result["errors"]')));
    });

    test('non-captureErrors query throws on errors', () {
      final start = client.indexOf('Future<ListUsersResponse> listUsers(');
      final end = client.indexOf('Future<', start + 1);
      // The throw lives inside the base executeData helper; the non-capture path
      // is identified by calling executeData (vs executeFull for capture).
      expect(client.substring(start, end), contains('executeData'));
    });
  });

  group('@glCaptureErrors — global config', () {
    test('all operations return FullResponse when captureErrors: true', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final client = _client(_parse(schema, captureErrors: true));
      expect(client, contains('Future<GetUserFullResponse> getUser('));
      expect(client, contains('Future<DeleteUserFullResponse> deleteUser('));
    });
  });
}
