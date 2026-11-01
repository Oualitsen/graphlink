import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

SwiftClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return SwiftClientSerializer(parser, SwiftSerializer(parser, importPrefix: 'GraphLinkGenerated'));
}

String _base(SwiftClientSerializer s) => s.generateResolverBaseFile().toFileContent();

void main() {
  group('persisted queries off', () {
    late SwiftClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: false));

    test('the resolver base has no hashing', () {
      final base = _base(clientSerializer);
      expect(base, isNot(contains('glHash')));
      expect(base, isNot(contains('GraphLinkPersistedQueries')));
    });

    test('no SHA-256 or persisted-queries file is produced', () {
      expect(clientSerializer.generateSha256File, throwsStateError);
      expect(clientSerializer.generatePersistedQueriesFile, throwsStateError);
    });

    test('glCallAdapter sends the payload untouched', () {
      expect(_base(clientSerializer), contains('return try await adapter(body)'));
    });
  });

  group('persisted queries on', () {
    late SwiftClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base exposes glHash, memoized in the shared state', () {
      final base = _base(clientSerializer);
      expect(base, contains('func glHash(_ query: String) -> String'));
      expect(base, contains('persisted.hash(for: query)'));
    });

    test('glCallAdapter sends a hash first for queries above the length threshold', () {
      final base = _base(clientSerializer);
      expect(base, contains('persisted.unsupported'));
      expect(base, contains('payload.query.utf8.count <= GraphLinkPersistedQueries.minQueryLength'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(glHash(payload.query))'));
    });

    test('retries with the query only for the known failures', () {
      final base = _base(clientSerializer);
      expect(base, contains('GraphLinkPersistedQueries.failure(response)'));
      expect(base, contains('persisted.unsupported = true'));
      expect(base, contains('body["extensions"] = extensions'));
    });

    test('the sha256 and protocol files carry the runtime', () {
      expect(clientSerializer.generateSha256File().toFileContent(), contains('enum GraphLinkSha256'));
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('enum GraphLinkPersistedQueries'));
      expect(file, contains('static let minQueryLength = 144'));
      expect(file, contains('final class GraphLinkPersistedQueryState'));
      expect(file, isNot(contains('GraphLinkGetNotSupported')));
    });
  });

  group('GET adapter', () {
    test('is absent unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      expect(_base(clientSerializer), isNot(contains('getAdapter')));
      expect(clientSerializer.generateClient().toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.getQueriesClass()!.toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.generatePersistedQueriesFile().toFileContent(), isNot(contains('GetNotSupported')));
      expect(clientSerializer.generateDefaultGetAdapterFile, throwsStateError);
    });

    group('when on', () {
      late SwiftClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the resolver base holds the adapter and remembers a refusal', () {
        final base = _base(clientSerializer);
        expect(base, contains('getAdapter: GraphLinkClientAdapter? = nil'));
        expect(base, contains('catch is GraphLinkGetNotSupported'));
        expect(base, contains('persisted.getUnsupported = true'));
      });

      test('mutations are never sent through the GET adapter', () {
        expect(_base(clientSerializer), contains('payload.query.hasPrefix("mutation")'));
      });

      test('the client takes a getAdapter right after the adapter and passes it down', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('adapter: @escaping GraphLinkClientAdapter, getAdapter: @escaping GraphLinkClientAdapter'));
        expect(client, contains('GraphLinkQueries(adapter: adapter, getAdapter: getAdapter, fragmentMap'));
        final queries = clientSerializer.getQueriesClass()!.toFileContent();
        expect(queries, contains('getAdapter: @escaping GraphLinkClientAdapter'));
        expect(queries, contains('getAdapter: getAdapter,'));
      });

      test('the exception type and URL builder are part of the persisted-queries runtime', () {
        final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
        expect(file, contains('struct GraphLinkGetNotSupported: Error'));
        expect(file, contains('enum GraphLinkGetRequest'));
        expect(file, contains('static func queryString('));
      });

      test('the default GET adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final file = clientSerializer.generateDefaultGetAdapterFile().toFileContent();
        expect(file, contains('struct DefaultGraphLinkURLSessionGetAdapter'));
        expect(file, contains('request.httpMethod = "GET"'));
        expect(file, contains('GraphLinkGetRequest.queryString(payload)'));
        expect(file, contains('statusCode == 405'));
        expect(file, contains('throw GraphLinkGetNotSupported(message: "GET is not allowed")'));
      });

      test('the convenience factory hands the GET adapter to the client', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('DefaultGraphLinkURLSessionGetAdapter(url: url, headersProvider: headersProvider)'));
        expect(client, contains('getAdapter: getAdapter.execute'));
      });
    });
  });
}
