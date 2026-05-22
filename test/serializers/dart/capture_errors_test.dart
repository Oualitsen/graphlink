import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Prepend built-in client objects so GraphLinkError is registered, which is
// required for FullResponse type generation.
final _clientObjects = getClientObjects('dynamic', 'Map<String, dynamic>');

GLParser _parse(String schema, {bool captureErrors = false}) {
  final g = GLParser(
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
    captureErrors: captureErrors,
  );
  g.parse('$_clientObjects\n$schema');
  return g;
}

String _client(GLParser g) {
  final serializer = DartSerializer(g);
  return DartClientSerializer(g, serializer)
      .generateClient('package')
      .toFileContent();
}

// Schema used for the main test groups.
//
// Queries:
//   getUser      — @glCaptureErrors, non-null return
//   findUser     — @glCaptureErrors, nullable return
//   listUsers    — plain, non-null return
//
// Mutations:
//   createUser   — @glCaptureErrors, non-null return
//   deleteUser   — plain, non-null return
//   maybeDelete  — plain, nullable return
const _schema = '''
type User { id: ID!  name: String! }

input CreateUserInput { name: String! }

type Query {
  getUser(id: ID!): User!  @glCaptureErrors
  findUser(id: ID!): User  @glCaptureErrors
  listUsers: [User!]!
}

type Mutation {
  createUser(input: CreateUserInput!): User! @glCaptureErrors
  deleteUser(id: ID!): Boolean!
  maybeDelete(id: ID!): Boolean
}
''';

void main() {
  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — validation', () {
    test('rejects @glCaptureErrors on a subscription field', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Subscription { userAdded: User! @glCaptureErrors }
''';
      expect(() => _parse(schema), throwsA(isA<ParseException>()));
    });

    test('rejects @glCaptureErrors on a list return type', () {
      const schema = '''
type User { id: ID! }
type Query { getUsers: [User!]! @glCaptureErrors }
''';
      expect(() => _parse(schema), throwsA(isA<ParseException>()));
    });

    test('accepts @glCaptureErrors on a query with object return', () {
      const schema = '''
type User { id: ID! }
type Query { getUser: User! @glCaptureErrors }
''';
      expect(() => _parse(schema), returnsNormally);
    });

    test('accepts @glCaptureErrors on a mutation with scalar return', () {
      const schema = '''
type Mutation { deleteUser(id: ID!): Boolean! @glCaptureErrors }
type Query    { dummy: Boolean }
''';
      expect(() => _parse(schema), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // Model — @glCaptureErrors inherited by the query element
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — directive inheritance', () {
    late GLParser g;
    setUpAll(() => g = _parse(_schema));

    GLQueryDefinition _def(String name) => g.queries[name]!;

    test('annotated query element carries the @glCaptureErrors directive', () {
      expect(
        _def('getUser').elements.first.hasDirective(glCaptureErrors),
        isTrue,
      );
    });

    test('non-annotated query element does not carry @glCaptureErrors', () {
      expect(
        _def('listUsers').elements.first.hasDirective(glCaptureErrors),
        isFalse,
      );
    });

    test('annotated mutation element carries the @glCaptureErrors directive', () {
      expect(
        _def('createUser').elements.first.hasDirective(glCaptureErrors),
        isTrue,
      );
    });

    test('non-annotated mutation element does not carry @glCaptureErrors', () {
      expect(
        _def('deleteUser').elements.first.hasDirective(glCaptureErrors),
        isFalse,
      );
    });

    test('isCaptureErrors() returns true for annotated query', () {
      expect(_def('getUser').isCaptureErrors(g), isTrue);
    });

    test('isCaptureErrors() returns false for non-annotated query', () {
      expect(_def('listUsers').isCaptureErrors(g), isFalse);
    });

    test('isCaptureErrors() returns true for every operation when global flag is set', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final g2 = _parse(schema, captureErrors: true);
      expect(g2.queries['getUser']!.isCaptureErrors(g2), isTrue);
      expect(g2.queries['deleteUser']!.isCaptureErrors(g2), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Generated FullResponse classes (always produced for every operation)
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — FullResponse class generation', () {
    late GLParser g;
    setUpAll(() => g = _parse(_schema));

    GLQueryDefinition _def(String name) => g.queries[name]!;

    test('FullResponse is generated for captureErrors query', () {
      final name = _def('getUser').getFullResponseTypeDefinition(g).token;
      expect(name, equals('GetUserFullResponse'));
    });

    test('FullResponse is generated for non-captureErrors query', () {
      final name = _def('listUsers').getFullResponseTypeDefinition(g).token;
      expect(name, equals('ListUsersFullResponse'));
    });

    test('FullResponse is generated for captureErrors mutation', () {
      final name = _def('createUser').getFullResponseTypeDefinition(g).token;
      expect(name, equals('CreateUserFullResponse'));
    });

    test('FullResponse is generated for non-captureErrors mutation', () {
      final name = _def('deleteUser').getFullResponseTypeDefinition(g).token;
      expect(name, equals('DeleteUserFullResponse'));
    });

    test('FullResponse has a nullable data field typed as the regular response', () {
      final fullDef = _def('getUser').getFullResponseTypeDefinition(g);
      final dataField = fullDef.getSerializableFields(g.mode)
          .firstWhere((f) => f.name.token == 'data');
      expect(dataField.type.nullable, isTrue);
      expect(dataField.type.token, equals('GetUserResponse'));
    });

    test('FullResponse has a nullable errors field', () {
      final fullDef = _def('getUser').getFullResponseTypeDefinition(g);
      final errorsField = fullDef.getSerializableFields(g.mode)
          .firstWhere((f) => f.name.token == 'errors');
      expect(errorsField.type.nullable, isTrue);
    });

    test('regular Response class is unmodified — no errors field', () {
      final regularDef = _def('getUser').getGeneratedTypeDefinition();
      final fieldNames = regularDef.getSerializableFields(g.mode)
          .map((f) => f.name.token)
          .toList();
      expect(fieldNames, isNot(contains('errors')));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — return types
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — generated return types', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('captureErrors query returns Future<XxxFullResponse>', () {
      expect(client, contains('Future<GetUserFullResponse> getUser('));
    });

    test('captureErrors mutation returns Future<XxxFullResponse>', () {
      expect(client, contains('Future<CreateUserFullResponse> createUser('));
    });

    test('non-captureErrors query with non-null return uses no ?', () {
      expect(client, contains('Future<ListUsersResponse> listUsers('));
    });

    test('non-captureErrors mutation with non-null return uses no ?', () {
      expect(client, contains('Future<DeleteUserResponse> deleteUser('));
    });

    test('non-captureErrors mutation with nullable return adds ? to type', () {
      expect(client, contains('Future<MaybeDeleteResponse?> maybeDelete('));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — captureErrors query body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — captureErrors query body', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('cache hit returns FullResponse.fromJson with data key', () {
      expect(client, contains("GetUserFullResponse.fromJson({'data':"));
    });

    test('_parseToObjectAndCache is called with captureErrors: true', () {
      expect(client, contains('captureErrors: true'));
    });

    test('no GraphQL-error throw in captureErrors query body', () {
      // rethrow for network errors is fine; we assert no explicit GraphQL error throw.
      final start = client.indexOf('Future<GetUserFullResponse> getUser(');
      final end   = client.indexOf('Future<FindUserFullResponse> findUser(');
      final body  = client.substring(start, end);
      expect(body, isNot(contains('throw result["errors"]')));
      expect(body, isNot(contains('throw __gl_result__.errors')));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — captureErrors mutation body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — captureErrors mutation body', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('parses response as FullResponse', () {
      expect(client, contains('CreateUserFullResponse.fromJson(jsonDecode('));
    });

    test('returns FullResponse directly — no .data unwrap', () {
      final mutStart = client.indexOf('Future<CreateUserFullResponse> createUser(');
      final mutEnd = client.indexOf('Future<', mutStart + 1);
      final mutBody = client.substring(mutStart, mutEnd);
      expect(mutBody, contains('return __gl_result__'));
      expect(mutBody, isNot(contains('__gl_result__.data')));
    });

    test('does not throw on errors for captureErrors mutation', () {
      final mutStart = client.indexOf('Future<CreateUserFullResponse> createUser(');
      final mutEnd = client.indexOf('Future<', mutStart + 1);
      final mutBody = client.substring(mutStart, mutEnd);
      expect(mutBody, isNot(contains('throw')));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — non-captureErrors query body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — non-captureErrors query body (listUsers)', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('parses as FullResponse then unwraps .data!', () {
      expect(client, contains("ListUsersFullResponse.fromJson({'data':"));
      expect(client, contains('.data!'));
    });

    test('_parseToObjectAndCache called without captureErrors flag', () {
      expect(
        client,
        contains(
          '_parseToObjectAndCache(__gl_responseText__, __gl_responseMap__, ListUsersFullResponse.fromJson, __gl_remaining__).data!',
        ),
      );
    });

    test('throws on errors', () {
      final queryStart = client.indexOf('Future<ListUsersResponse> listUsers(');
      final queryEnd = client.indexOf('Future<', queryStart + 1);
      final queryBody = client.substring(queryStart, queryEnd);
      expect(queryBody, contains('throw'));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — non-captureErrors mutation body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — non-captureErrors mutation body', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('non-null return uses .data!', () {
      final mutStart = client.indexOf('Future<DeleteUserResponse> deleteUser(');
      final mutEnd = client.indexOf('Future<', mutStart + 1);
      final mutBody = client.substring(mutStart, mutEnd);
      expect(mutBody, contains('__gl_result__.data!'));
    });

    test('nullable return uses .data without !', () {
      final mutStart = client.indexOf('Future<MaybeDeleteResponse?> maybeDelete(');
      final mutEnd = client.indexOf('Future<', mutStart + 1);
      final mutBody = client.substring(mutStart, mutEnd);
      expect(mutBody, contains('return __gl_result__.data;'));
      expect(mutBody, isNot(contains('__gl_result__.data!')));
    });

    test('throws on errors', () {
      final mutStart = client.indexOf('Future<DeleteUserResponse> deleteUser(');
      final mutEnd = client.indexOf('Future<', mutStart + 1);
      final mutBody = client.substring(mutStart, mutEnd);
      expect(mutBody, contains('throw __gl_result__.errors!'));
    });
  });

  // -------------------------------------------------------------------------
  // Generated client — imports
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — imports', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('imports FullResponse types for captureErrors operations', () {
      expect(client, contains('get_user_full_response.dart'));
      expect(client, contains('create_user_full_response.dart'));
    });

    test('imports FullResponse types for non-captureErrors operations', () {
      expect(client, contains('list_users_full_response.dart'));
      expect(client, contains('delete_user_full_response.dart'));
    });
  });

  // -------------------------------------------------------------------------
  // Global captureErrors config
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — global config', () {
    test('all queries and mutations return FullResponse when captureErrors: true', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final client = _client(_parse(schema, captureErrors: true));
      expect(client, contains('Future<GetUserFullResponse> getUser('));
      expect(client, contains('Future<DeleteUserFullResponse> deleteUser('));
    });

    test('_parseToObjectAndCache always called with captureErrors: true when global flag is set', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final client = _client(_parse(schema, captureErrors: true));
      // Every _parseToObjectAndCache call must have captureErrors: true.
      // A call without the flag would look like "...fromJson, __gl_remaining__)."
      // We verify by checking no call exists that LACKS the captureErrors argument.
      expect(client, isNot(contains('fromJson, __gl_remaining__).')));
      expect(client, contains('captureErrors: true'));
    });
  });
}
