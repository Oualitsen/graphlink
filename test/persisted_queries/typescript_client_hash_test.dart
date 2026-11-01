import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

TypeScriptClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return TypeScriptClientSerializer(parser, TypeScriptSerializer(parser, importPrefix: ''));
}

void main() {
  group('persisted queries off', () {
    late TypeScriptClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: false));

    test('the resolver base has no hashing', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, isNot(contains('glHash')));
      expect(base, isNot(contains('graph-link-sha256')));
      expect(base, isNot(contains('GraphLinkPersistedQueries')));
    });

    test('no SHA-256 or persisted-queries file is produced', () {
      expect(clientSerializer.generateSha256File, throwsStateError);
      expect(clientSerializer.generatePersistedQueriesFile, throwsStateError);
    });

    test('_glCallAdapter sends the payload untouched', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('return await this.gl_adapter__!(JSON.stringify(payload));'));
    });
  });

  group('persisted queries on', () {
    late TypeScriptClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base exposes glHash, computed once per query string', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains("import { GraphLinkSha256 } from './graph-link-sha256.js';"));
      expect(base, contains('glHash(query: string): string'));
      expect(base, contains('GraphLinkSha256.hex(query)'));
      expect(base, contains('this.gl_hashes__.set(query, hash);'));
    });

    test('_glCallAdapter sends a hash first for queries above the length threshold', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('this.gl_persistedUnsupported__'));
      expect(base, contains('payload.query.length <= GraphLinkPersistedQueries.minQueryLength'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(this.glHash(payload.query))'));
    });

    test('retries with the query only for the known failures', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('GraphLinkPersistedQueries.failure(response)'));
      expect(base, contains('this.gl_persistedUnsupported__ = true;'));
      expect(base, contains('body.extensions = extensions;'));
    });

    test('the sha256 and protocol files carry the runtime', () {
      expect(clientSerializer.generateSha256File().toFileContent(), contains('class GraphLinkSha256'));
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('class GraphLinkPersistedQueries'));
      expect(file, contains('static readonly minQueryLength = 144;'));
      expect(file, isNot(contains('GraphLinkGetNotSupported')));
    });
  });

  group('GET adapter', () {
    test('is absent unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, isNot(contains('gl_getAdapter__')));
      expect(clientSerializer.generateClientOnlyFile().toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.generateAdaptersFile(TypeScriptHttpAdapter.fetch)!.toFileContent(),
          isNot(contains('GetAdapter')));
    });

    group('when on', () {
      late TypeScriptClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the resolver base holds the adapter and remembers a refusal', () {
        final base = clientSerializer.generateResolverBaseFile().toFileContent();
        expect(base, contains('gl_getAdapter__'));
        expect(base, contains('gl_getUnsupported__ = false'));
        expect(base, contains('e instanceof GraphLinkGetNotSupported'));
        expect(base, contains('this.gl_getUnsupported__ = true;'));
      });

      test('mutations are never sent through the GET adapter', () {
        final base = clientSerializer.generateResolverBaseFile().toFileContent();
        expect(base, contains("payload.query.startsWith('mutation')"));
      });

      test('the client takes a getAdapter right after the adapter and passes it down', () {
        final client = clientSerializer.generateClientOnlyFile().toFileContent();
        expect(client, contains('adapter: GraphLinkAdapter, getAdapter: GraphLinkAdapter'));
        expect(client, contains('new GraphLinkQueries(adapter, getAdapter,'));
      });

      test('the exception type is part of the persisted-queries runtime', () {
        final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
        expect(file, contains('class GraphLinkGetNotSupported'));
        expect(file, contains('static queryString('));
      });
    });
  });

  group('default adapters', () {
    test('fetch and axios have no GET variant unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      for (final adapter in [TypeScriptHttpAdapter.fetch, TypeScriptHttpAdapter.axios]) {
        expect(clientSerializer.generateAdaptersFile(adapter)!.toFileContent(), isNot(contains('GetAdapter')));
      }
    });

    group('when GET is on', () {
      late TypeScriptClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the fetch adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final file = clientSerializer.generateAdaptersFile(TypeScriptHttpAdapter.fetch)!.toFileContent();
        expect(file, contains("import { GraphLinkGetNotSupported, GraphLinkGetRequest } from './graph-link-persisted-queries.js';"));
        expect(file, contains('export function createFetchGetAdapter('));
        expect(file, contains("method: 'GET'"));
        expect(file, contains('GraphLinkGetRequest.queryString(payload)'));
        expect(file, contains('response.status === 405'));
        expect(file, contains("throw new GraphLinkGetNotSupported('GET is not allowed');"));
      });

      test('the axios adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final file = clientSerializer.generateAdaptersFile(TypeScriptHttpAdapter.axios)!.toFileContent();
        expect(file, contains('export function createAxiosGetAdapter('));
        expect(file, contains('axiosInstance.get('));
        expect(file, contains('status === 405'));
        expect(file, contains('GraphLinkGetNotSupported'));
      });
    });
  });
}
