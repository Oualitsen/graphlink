import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

KotlinClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    mode: CodeGenerationMode.client,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(kotlinJsonEncoderDecoder + kotlinClientAdapterGql + _schema);
  return KotlinClientSerializer(parser, KotlinSerializer(parser, importPrefix: 'com.example'));
}

String _base(KotlinClientSerializer s) => s.generateGraphLinkResolverBaseFile('com.example').toFileContent();

void main() {
  group('persisted queries off', () {
    late KotlinClientSerializer clientSerializer;
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
      expect(_base(clientSerializer), contains('return adapter.execute(encoder.encode(payload.toJson()))'));
    });
  });

  group('persisted queries on', () {
    late KotlinClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base exposes glHash, computed once per query string', () {
      final base = _base(clientSerializer);
      expect(base, contains('fun glHash(query: String): String'));
      expect(base, contains('hashes[query]'));
      expect(base, contains('GraphLinkSha256.hex(query)'));
    });

    test('glCallAdapter sends a hash first for queries above the length threshold', () {
      final base = _base(clientSerializer);
      expect(base, contains('persistedUnsupported'));
      expect(base, contains('payload.query.length <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(glHash(payload.query))'));
    });

    test('retries with the query only for the known failures', () {
      final base = _base(clientSerializer);
      expect(base, contains('GraphLinkPersistedQueries.failure(response, decoder)'));
      expect(base, contains('persistedUnsupported = true'));
      expect(base, contains('body["extensions"] = extensions'));
    });

    test('the sha256 and protocol files carry the runtime', () {
      expect(clientSerializer.generateSha256File().toFileContent(), contains('object GraphLinkSha256'));
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('object GraphLinkPersistedQueries'));
      expect(file, contains('const val MIN_QUERY_LENGTH = 144'));
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
      late KotlinClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the resolver base holds the adapter and remembers a refusal', () {
        final base = _base(clientSerializer);
        expect(base, contains('getAdapter: GraphLinkClientAdapter?'));
        expect(base, contains('getUnsupported'));
        expect(base, contains('e !is GraphLinkGetNotSupported'));
        expect(base, contains('getUnsupported = true'));
      });

      test('mutations are never sent through the GET adapter', () {
        expect(_base(clientSerializer), contains('payload.query.startsWith("mutation")'));
      });

      test('the client takes a getAdapter right after the adapter and passes it down', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('private val getAdapter: GraphLinkClientAdapter'));
        expect(client, contains('GraphLinkQueries(adapter, getAdapter, fragmentMap'));
        final queries = clientSerializer.getQueriesClass()!.toFileContent();
        expect(queries, contains('getAdapter: GraphLinkClientAdapter'));
      });

      test('the exception type and URL builder are part of the persisted-queries runtime', () {
        final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
        expect(file, contains('class GraphLinkGetNotSupported'));
        expect(file, contains('object GraphLinkGetRequest'));
        expect(file, contains('fun queryParameters('));
      });

      test('the default GET adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final file = clientSerializer.generateDefaultGetAdapterFile().toFileContent();
        expect(file, contains('class DefaultGraphLinkGetAdapter'));
        expect(file, contains('.get()'));
        expect(file, contains('GraphLinkGetRequest.queryParameters(payload, codec, codec)'));
        expect(file, contains('response.code == 405'));
        expect(file, contains('throw GraphLinkGetNotSupported("GET is not allowed")'));
      });

      test('the convenience factories hand the GET adapter to the client', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('DefaultGraphLinkGetAdapter(url'));
      });
    });
  });
}
