import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/go_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type Mutation { deleteUser(id: ID!): Boolean! }
type User { id: ID! name: String }
''';

GoClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    naming: NamingConvention.go,
    reservedWords: goReservedWords,
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return GoClientSerializer(parser, GoSerializer(parser));
}

String _base(GoClientSerializer s) => s.generateResolverBaseFile().toFileContent();

Iterable<String> _lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

void main() {
  group('persisted queries off', () {
    late GoClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: false));

    test('the resolver base has no hashing', () {
      expect(_base(clientSerializer), isNot(contains('glHash')));
    });

    test('glCallAdapter sends the payload untouched', () {
      expect(_lines(_base(clientSerializer)), containsAllInOrder([
        'func (r *GraphLinkResolverBase) glCallAdapter(ctx context.Context, payload GraphLinkPayload) (string, error) {',
        'return r.glSend(ctx, payload.glBody())',
      ]));
    });
  });

  group('persisted queries on', () {
    late GoClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));
    String persisted() => clientSerializer.generatePersistedQueriesFile().toFileContent();

    test('the resolver base leaves glCallAdapter to the persisted-queries file', () {
      expect(_base(clientSerializer), isNot(contains('func (r *GraphLinkResolverBase) glCallAdapter')));
    });

    test('hashes are memoized SHA-256 digests', () {
      expect(_lines(persisted()), containsAllInOrder([
        'func (r *GraphLinkResolverBase) glHash(query string) string {',
        'if cached, ok := r.hashes.Load(query); ok {',
        'sum := sha256.Sum256([]byte(query))',
        'r.hashes.Store(query, hash)',
      ]));
    });

    test('a hash goes first above the length threshold', () {
      expect(persisted(), contains('const glPersistedMinQueryLength = 144'));
      expect(persisted(), contains('r.persistedUnsupported.Load() || len(payload.Query) <= glPersistedMinQueryLength'));
    });

    test('only PersistedQueryNotFound re-sends the query, PersistedQueryNotSupported stops hashing', () {
      expect(_lines(persisted()), containsAllInOrder([
        'failure := glPersistedFailure(response)',
        'if failure == glPersistedNotSupported {',
        'r.persistedUnsupported.Store(true)',
        'body["extensions"] = extensions',
      ]));
    });

    test('without GET the hash-only request goes through the POST adapter', () {
      expect(persisted(), contains('response, err := r.glSend(ctx, hashOnly)'));
      expect(persisted(), isNot(contains('GraphLinkGetNotSupported')));
    });
  });

  group('persisted queries with GET', () {
    late GoClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));
    String persisted() => clientSerializer.generatePersistedQueriesFile().toFileContent();

    test('hash-only requests try the GET adapter and fall back to POST on GraphLinkGetNotSupported', () {
      expect(persisted(), contains('response, err := r.glSendHashOnly(ctx, payload, hashOnly)'));
      expect(_lines(persisted()), containsAllInOrder([
        'if r.getUnsupported.Load() || strings.HasPrefix(payload.Query, "mutation") {',
        'if !errors.As(err, &notSupported) {',
        'r.getUnsupported.Store(true)',
      ]));
    });

    test('the GET helpers are generated', () {
      expect(persisted(), contains('type GraphLinkGetNotSupported struct'));
      expect(persisted(), contains('func GraphLinkGetQueryParameters'));
    });
  });

  group('operations', () {
    late String queries;
    setUp(() => queries = _clientSerializer(persistedQueries: false).getQueriesClass()!.toFileContent());

    test('methods are exported and take a context', () {
      expect(queries, contains('func (q *GraphLinkQueries) GetUser(ctx context.Context, id string) (GetUserResponse, error) {'));
    });

    test('the response is read from .Data', () {
      expect(queries, contains('glExecuteData[GetUserFullResponse]'));
      expect(queries, contains('return *glResult__.Data, nil'));
    });

    test('fragment names are an ordered slice so the assembled query is stable', () {
      expect(queries, contains('glFragmentNames__ := []string{'));
    });

    test('the query text keeps its dollar signs', () {
      expect(queries, contains(r'query getUser($id: ID!)'));
      expect(queries, isNot(contains(r'\$')));
    });
  });
}
