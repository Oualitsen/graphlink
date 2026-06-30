import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------


GLParser _parse(String schema, {bool captureErrors = false}) {
  final g = GLParser(
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
    captureErrors: captureErrors,
  );
  g.parse(schema);
  return g;
}

String _client(GLParser g) {
  final ts = TypeScriptSerializer(g, importPrefix: "");
  return TypeScriptClientSerializer(g, ts)
      .generateClient()
      .toFileContent();
}

String _queries(GLParser g) {
  final ts = TypeScriptSerializer(g, importPrefix: "");
  return TypeScriptClientSerializer(g, ts).getQueriesClass()?.toFileContent() ?? '';
}

String _mutations(GLParser g) {
  final ts = TypeScriptSerializer(g, importPrefix: "");
  return TypeScriptClientSerializer(g, ts).getMutationsClass()?.toFileContent() ?? '';
}

// Schema: mix of captureErrors and plain operations.
//
// Queries:
//   getUser        — @glCaptureErrors, non-null return
//   findUser       — @glCaptureErrors, nullable return
//   listUsers      — plain, non-null return
//
// Mutations:
//   createUser     — @glCaptureErrors, non-null return
//   deleteUser     — plain, non-null return
const _schema = '''
type User { id: ID!  name: String! }
input CreateUserInput { name: String! }

type Query {
  getUser(id: ID!): User! @glCaptureErrors
  findUser(id: ID!): User @glCaptureErrors
  listUsers: [User!]!
}

type Mutation {
  createUser(input: CreateUserInput!): User! @glCaptureErrors
  deleteUser(id: ID!): Boolean!
}
''';

void main() {
  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript validation', () {
    test('rejects @glCaptureErrors on a subscription field', () {
      const schema = '''
type User { id: ID! }
type Query       { getUser: User! }
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

    test('accepts @glCaptureErrors on a scalar mutation return', () {
      const schema = '''
type Query    { dummy: Boolean }
type Mutation { deleteUser(id: ID!): Boolean! @glCaptureErrors }
''';
      expect(() => _parse(schema), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // Directive inheritance
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — directive inheritance', () {
    late GLParser g;
    setUpAll(() => g = _parse(_schema));

    test('annotated query element carries @glCaptureErrors', () {
      expect(g.queries[GLOperationKey('getUser', GLQueryType.query)]!.elements.first.hasDirective(glCaptureErrors), isTrue);
    });

    test('non-annotated query element does not carry @glCaptureErrors', () {
      expect(g.queries[GLOperationKey('listUsers', GLQueryType.query)]!.elements.first.hasDirective(glCaptureErrors), isFalse);
    });

    test('isCaptureErrors() returns true for annotated operation', () {
      expect(g.queries[GLOperationKey('createUser', GLQueryType.mutation)]!.isCaptureErrors(g), isTrue);
    });

    test('isCaptureErrors() returns false for non-annotated operation', () {
      expect(g.queries[GLOperationKey('deleteUser', GLQueryType.mutation)]!.isCaptureErrors(g), isFalse);
    });

    test('global captureErrors: true makes all operations captureErrors', () {
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

  // -------------------------------------------------------------------------
  // Return types
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript return types', () {
    late String client;
    setUpAll(() => client = _client(_parse(_schema)));

    test('captureErrors query returns Promise<XxxFullResponse>', () {
      expect(client, contains('Promise<GetUserFullResponse>'));
    });

    test('captureErrors mutation returns Promise<XxxFullResponse>', () {
      expect(client, contains('Promise<CreateUserFullResponse>'));
    });

    test('non-captureErrors query returns Promise<XxxResponse>', () {
      expect(client, contains('Promise<ListUsersResponse>'));
    });

    test('non-captureErrors mutation returns Promise<XxxResponse>', () {
      expect(client, contains('Promise<DeleteUserResponse>'));
    });
  });

  // -------------------------------------------------------------------------
  // captureErrors query body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript captureErrors query body', () {
    late String queries;
    setUpAll(() => queries = _queries(_parse(_schema)));

    test('captureErrors result sets errors field to null when absent', () {
      expect(queries, contains("(gl_result__ as any)['errors'] = null;"));
    });

    test('captureErrors result is returned directly without unwrapping data', () {
      // fromJson is called on the full result — data field is NOT unwrapped.
      expect(queries, contains('GetUserFullResponse.fromJson(gl_result__ as Record<string, unknown>)'));
      expect(queries, isNot(contains("GetUserFullResponse.fromJson(gl_result__['data']")));
    });

    test('both captureErrors queries set errors to null when absent', () {
      final start = queries.indexOf('Promise<GetUserFullResponse>');
      final end   = queries.indexOf('Promise<FindUserFullResponse>');
      final body  = queries.substring(start, end);
      expect(body, contains("(gl_result__ as any)['errors'] = null;"));
    });

    test('no explicit GraphQL-error throw in captureErrors query body', () {
      final start = queries.indexOf('Promise<GetUserFullResponse>');
      final end   = queries.indexOf('Promise<FindUserFullResponse>');
      final body  = queries.substring(start, end);
      expect(body, isNot(contains("throw result['errors']")));
    });
  });

  // -------------------------------------------------------------------------
  // non-captureErrors query body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript non-captureErrors query body (listUsers)', () {
    late String queries;
    setUpAll(() => queries = _queries(_parse(_schema)));

    test('non-captureErrors result returns data field directly', () {
      final start = queries.indexOf('Promise<ListUsersResponse>');
      final body  = queries.substring(start);
      expect(body, contains("ListUsersResponse.fromJson(gl_result__['data'] as Record<string, unknown>)"));
      expect(body, isNot(contains('gl_responseMap__')));
    });

    test('non-captureErrors result throws on errors', () {
      final start = queries.indexOf('Promise<ListUsersResponse>');
      final body  = queries.substring(start);
      expect(body, contains("throw gl_result__['errors'] as GraphLinkError[];"));
    });
  });

  // -------------------------------------------------------------------------
  // captureErrors mutation body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript captureErrors mutation body', () {
    late String mutations;
    setUpAll(() => mutations = _mutations(_parse(_schema)));

    test('parses result directly as FullResponse', () {
      // Parsing now happens inside the base _executeFull helper; the FullResponse
      // type flows through its generic argument.
      expect(mutations, contains('_executeFull<CreateUserFullResponse>'));
    });

    test('returns result directly without unwrapping .data', () {
      final start = mutations.indexOf('Promise<CreateUserFullResponse>');
      final end   = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start, end);
      // fromJson is called on the full result — the data field is NOT unwrapped.
      expect(body, contains("CreateUserFullResponse.fromJson(gl_result__ as Record<string, unknown>)"));
      expect(body, isNot(contains("gl_result__['data']")));
    });

    test('no throw block in captureErrors mutation', () {
      final start = mutations.indexOf('Promise<CreateUserFullResponse>');
      final end   = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start, end);
      expect(body, isNot(contains("throw")));
    });
  });

  // -------------------------------------------------------------------------
  // non-captureErrors mutation body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript non-captureErrors mutation body', () {
    late String mutations;
    setUpAll(() => mutations = _mutations(_parse(_schema)));

    test('throws on errors', () {
      final start = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start);
      expect(body, contains("throw gl_result__['errors']"));
    });

    test('returns result[data]', () {
      final start = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start);
      expect(body, contains("DeleteUserResponse.fromJson(gl_result__['data'] as Record<string, unknown>)"));
    });
  });

  // -------------------------------------------------------------------------
  // _parseAndCache helper
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript _parseAndCache helper', () {
    late String queries;
    setUpAll(() => queries = _queries(_parse(_schema)));

    test('has captureErrors parameter with default false', () {
      expect(queries, contains('captureErrors = false'));
    });

    test('throws on errors when captureErrors is false', () {
      expect(queries, contains("errors != null && errors.length > 0"));
      expect(queries, contains("throw errors as GraphLinkError[];"));
    });

    test('constructs fullResponse map and returns it', () {
      print(queries);
      expect(queries, contains("const fullResponse: Record<string, unknown> = { 'data': result['data'] != null ? dataMap : null, 'errors': result['errors'] ?? null };"));
      expect(queries, contains('return fullResponse;'));
    });
  });

  // -------------------------------------------------------------------------
  // Global config
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript global config', () {
    test('all operations return FullResponse when captureErrors: true', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final client = _client(_parse(schema, captureErrors: true));
      expect(client, contains('Promise<GetUserFullResponse>'));
      expect(client, contains('Promise<DeleteUserFullResponse>'));
    });

    test('global captureErrors: true makes all queries set errors to null', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final queries = _queries(_parse(schema, captureErrors: true));
      expect(queries, contains("(gl_result__ as any)['errors'] = null;"));
      expect(queries, isNot(contains("throw gl_result__['errors']")));
    });
  });
}
