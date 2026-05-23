import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';
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
  final ts = TypeScriptSerializer(g);
  return TypeScriptClientSerializer(g, ts)
      .generateClient('')
      .toFileContent();
}

String _queries(GLParser g) {
  final ts = TypeScriptSerializer(g);
  return TypeScriptClientSerializer(g, ts).getQueriesClass('')?.toFileContent() ?? '';
}

String _mutations(GLParser g) {
  final ts = TypeScriptSerializer(g);
  return TypeScriptClientSerializer(g, ts).getMutationsClass('')?.toFileContent() ?? '';
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
      expect(g.queries['getUser']!.elements.first.hasDirective(glCaptureErrors), isTrue);
    });

    test('non-annotated query element does not carry @glCaptureErrors', () {
      expect(g.queries['listUsers']!.elements.first.hasDirective(glCaptureErrors), isFalse);
    });

    test('isCaptureErrors() returns true for annotated operation', () {
      expect(g.queries['createUser']!.isCaptureErrors(g), isTrue);
    });

    test('isCaptureErrors() returns false for non-annotated operation', () {
      expect(g.queries['deleteUser']!.isCaptureErrors(g), isFalse);
    });

    test('global captureErrors: true makes all operations captureErrors', () {
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

    test('cache hit wraps responseMap with data key and null errors', () {
      expect(queries, contains('{ data: __gl_responseMap__, errors: null }'));
    });

    test('_parseAndCache called with captureErrors=true', () {
      expect(queries, contains('_parseAndCache(__gl_responseText__, __gl_responseMap__, __gl_remaining__, true)'));
    });

    test('stale fallback also wraps with data key and null errors', () {
      final start = queries.indexOf('Promise<GetUserFullResponse>');
      final end   = queries.indexOf('Promise<FindUserFullResponse>');
      final body  = queries.substring(start, end);
      expect(body, contains('{ data: __gl_responseMap__, errors: null }'));
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

    test('cache hit returns responseMap directly (no data wrapping)', () {
      final start = queries.indexOf('Promise<ListUsersResponse>');
      final body  = queries.substring(start);
      expect(body, contains('__gl_responseMap__ as unknown as ListUsersResponse'));
      expect(body, isNot(contains('{ data: __gl_responseMap__ }')));
    });

    test('_parseAndCache called without captureErrors flag', () {
      expect(queries, contains('_parseAndCache(__gl_responseText__, __gl_responseMap__, __gl_remaining__)'));
    });
  });

  // -------------------------------------------------------------------------
  // captureErrors mutation body
  // -------------------------------------------------------------------------
  group('@glCaptureErrors — TypeScript captureErrors mutation body', () {
    late String mutations;
    setUpAll(() => mutations = _mutations(_parse(_schema)));

    test('parses result directly as FullResponse', () {
      expect(mutations, contains('JSON.parse(__gl_response__) as CreateUserFullResponse'));
    });

    test('returns result directly without unwrapping .data', () {
      final start = mutations.indexOf('Promise<CreateUserFullResponse>');
      final end   = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start, end);
      expect(body, contains("return __gl_result__"));
      expect(body, isNot(contains("__gl_result__['data']")));
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
      expect(body, contains("throw __gl_result__['errors']"));
    });

    test('returns result[data]', () {
      final start = mutations.indexOf('Promise<DeleteUserResponse>');
      final body  = mutations.substring(start);
      expect(body, contains("__gl_result__['data'] as DeleteUserResponse"));
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
      expect(queries, contains("const fullResponse: Record<string, unknown> = { 'data': dataMap };"));
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

    test('_parseAndCache always called with true when global flag is set', () {
      const schema = '''
type User { id: ID! }
type Query    { getUser: User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final queries = _queries(_parse(schema, captureErrors: true));
      expect(queries, contains('_parseAndCache(__gl_responseText__, __gl_responseMap__, __gl_remaining__, true)'));
      expect(queries, isNot(contains('_parseAndCache(__gl_responseText__, __gl_responseMap__, __gl_remaining__)')));
    });
  });
}
