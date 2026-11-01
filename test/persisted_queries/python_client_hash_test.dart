import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type Mutation { deleteUser(id: ID!): Boolean! }
type User { id: ID! name: String }
''';

PythonClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    naming: NamingConvention.python,
    reservedWords: pythonReservedWords,
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return PythonClientSerializer(parser, PythonSerializer(parser));
}

String _base(PythonClientSerializer s) => s.generateResolverBaseFile().toFileContent();

Iterable<String> _lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('persisted queries off', () {
    late PythonClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: false));

    test('the resolver base has no hashing', () {
      final base = _base(clientSerializer);
      expect(base, isNot(contains('gl_hash')));
      expect(base, isNot(contains('GraphLinkPersistedQueries')));
    });

    test('no persisted-queries file is produced', () {
      expect(clientSerializer.generatePersistedQueriesFile, throwsStateError);
    });

    test('gl_call_adapter sends the payload untouched', () {
      expect(_base(clientSerializer), contains('return await self.gl_adapter__(json.dumps(payload.to_json()))'));
    });
  });

  group('persisted queries on', () {
    late PythonClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base exposes a memoized gl_hash', () {
      expect(_lines(_base(clientSerializer)), containsAllInOrder([
        'def gl_hash(self, query: str) -> str:',
        'cached = self.gl_hashes__.get(query)',
        'digest = graph_link_sha256_hex(query)',
        'self.gl_hashes__[query] = digest',
      ]));
    });

    test('gl_call_adapter sends a hash first above the length threshold', () {
      final base = _base(clientSerializer);
      expect(base, contains('self.gl_persisted_unsupported__ or len(payload.query) <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(self.gl_hash(payload.query))'));
    });

    test('only PersistedQueryNotFound re-sends the query, PersistedQueryNotSupported stops hashing', () {
      final base = _base(clientSerializer);
      expect(base, contains('GraphLinkPersistedQueries.failure(gl_response__)'));
      expect(base, contains('gl_failure__ == GraphLinkPersistedQueries.NOT_SUPPORTED'));
      expect(base, contains('self.gl_persisted_unsupported__ = True'));
      expect(base, contains('gl_body__["extensions"] = gl_extensions__'));
    });

    test('without GET the hash-only request goes through the POST adapter', () {
      final base = _base(clientSerializer);
      expect(base, contains('await self.gl_send__(gl_hash_only__)'));
      expect(base, isNot(contains('gl_send_hash_only__')));
    });

    test('the persisted-queries runtime is generated without the GET helpers', () {
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('class GraphLinkPersistedQueries'));
      expect(file, contains('MIN_QUERY_LENGTH = 144'));
      expect(file, isNot(contains('GraphLinkGetNotSupported')));
    });
  });

  group('persisted queries with GET', () {
    late PythonClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

    test('hash-only requests try the GET adapter and fall back to POST on GraphLinkGetNotSupported', () {
      final base = _base(clientSerializer);
      expect(base, contains('await self.gl_send_hash_only__(payload, gl_hash_only__)'));
      expect(base, contains('self.gl_get_unsupported__ or payload.query.startswith("mutation")'));
      expect(base, contains('not isinstance(e, GraphLinkGetNotSupported)'));
      expect(base, contains('self.gl_get_unsupported__ = True'));
    });

    test('the GET helpers are generated', () {
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('class GraphLinkGetNotSupported'));
      expect(file, contains('class GraphLinkGetRequest'));
    });

    test('the operation classes receive the get adapter and pass it to the base', () {
      final queries = clientSerializer.getQueriesClass()!.toFileContent();
      expect(queries, contains('get_adapter: Callable[[str], Awaitable[str]]'));
      expect(_lines(queries), contains('get_adapter,'));
    });
  });

  group('operations', () {
    test('methods are async, keyword-only and snake_case', () {
      final queries = _clientSerializer(persistedQueries: false).getQueriesClass()!.toFileContent();
      expect(queries, contains('async def get_user(self, *, id: str) -> GetUserResponse:'));
      expect(queries, contains('"query getUser'));
    });

    test('the response is read from .data', () {
      final queries = _clientSerializer(persistedQueries: false).getQueriesClass()!.toFileContent();
      expect(queries, contains('.data'));
      expect(queries, contains('GetUserFullResponse.from_json'));
    });

    test('fragment names are an ordered list so the assembled query is stable', () {
      final queries = _clientSerializer(persistedQueries: false).getQueriesClass()!.toFileContent();
      expect(queries, contains('gl_fragment_names__ = ['));
    });
  });
}
