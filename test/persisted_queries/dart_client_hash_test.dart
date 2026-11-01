import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

DartClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return DartClientSerializer(parser, DartSerializer(parser, importPrefix: ''));
}

void main() {
  group('persisted queries off', () {
    late DartClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: false));

    test('the resolver base has no hashing', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, isNot(contains('glHash')));
      expect(base, isNot(contains('graph_link_sha256')));
    });

    test('no SHA-256 file is produced', () {
      expect(clientSerializer.generateSha256File, throwsStateError);
    });

    test('no persisted-queries file is produced', () {
      expect(clientSerializer.generatePersistedQueriesFile, throwsStateError);
    });

    test('glCallAdapter sends the payload untouched', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('return await glAdapter__(json.encode(payload.toJson()));'));
      expect(base, isNot(contains('glPersistedUnsupported__')));
      expect(base, isNot(contains('GraphLinkPersistedQueries')));
    });
  });

  group('persisted queries on', () {
    late DartClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base imports the SHA-256 file and exposes glHash', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains("import 'graph_link_sha256.dart';"));
      expect(base, contains('String glHash(String query)'));
    });

    test('glHash computes once per query string and remembers it', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('final Map<String, String> _glHashes = {};'));
      expect(base, contains('final cached = _glHashes[query];'));
      expect(base, contains('final hash = GraphLinkSha256.hex(query);'));
      expect(base, contains('_glHashes[query] = hash;'));
    });

    test('the persisted-queries file carries the protocol helpers', () {
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains("import 'dart:convert';"));
      expect(file, contains('class GraphLinkPersistedQueries'));
      expect(file, contains('static const int minQueryLength = 144;'));
    });

    test('glCallAdapter sends a hash first for queries above the length threshold', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains("import 'graph_link_persisted_queries.dart';"));
      expect(base, contains('bool glPersistedUnsupported__ = false;'));
      expect(base, contains('payload.query.length <= GraphLinkPersistedQueries.minQueryLength'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(glHash(payload.query))'));
    });

    test('glCallAdapter retries with the query only for the known failures', () {
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, contains('GraphLinkPersistedQueries.failure(glResponse__)'));
      expect(base, contains('glPersistedUnsupported__ = true;'));
      expect(base, contains("glBody__['extensions'] = glExtensions__;"));
    });

    test('the SHA-256 file carries the runtime', () {
      final file = clientSerializer.generateSha256File().toFileContent();
      expect(file, contains("import 'dart:convert';"));
      expect(file, contains('class GraphLinkSha256'));
    });
  });

  group('GET adapter', () {
    test('is absent unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      final base = clientSerializer.generateResolverBaseFile().toFileContent();
      expect(base, isNot(contains('glGetAdapter__')));
      expect(base, isNot(contains('glGetUnsupported__')));
      expect(clientSerializer.generateClient().toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.generatePersistedQueriesFile().toFileContent(), isNot(contains('GraphLinkGetNotSupported')));
    });

    group('when on', () {
      late DartClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the resolver base holds the adapter and remembers a refusal', () {
        final base = clientSerializer.generateResolverBaseFile().toFileContent();
        expect(base, contains('final Future<String> Function(String payload) glGetAdapter__;'));
        expect(base, contains('bool glGetUnsupported__ = false;'));
      });

      test('only a GraphLinkGetNotSupported falls back to POST', () {
        final base = clientSerializer.generateResolverBaseFile().toFileContent();
        expect(base, contains('e is! GraphLinkGetNotSupported'));
        expect(base, contains('rethrow;'));
        expect(base, contains('glGetUnsupported__ = true;'));
      });

      test('mutations are never sent through the GET adapter', () {
        final base = clientSerializer.generateResolverBaseFile().toFileContent();
        expect(base, contains("payload.query.startsWith('mutation')"));
      });

      test('the client requires a getAdapter and passes it down', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('required Future<String> Function(String payload) getAdapter'));
        expect(client, contains('getAdapter'));
      });

      test('the exception type is part of the persisted-queries runtime', () {
        final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
        expect(file, contains('class GraphLinkGetNotSupported'));
      });
    });
  });

  group('default adapters', () {
    test('have no getCall unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      expect(clientSerializer.generateHttpAdapterFile().toFileContent(), isNot(contains('getCall')));
      expect(clientSerializer.generateDioAdapterFile().toFileContent(), isNot(contains('getCall')));
    });

    group('when GET is on', () {
      late DartClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the http adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final http = clientSerializer.generateHttpAdapterFile().toFileContent();
        expect(http, contains("import 'graph_link_persisted_queries.dart';"));
        expect(http, contains('Future<String> getCall(String payload)'));
        expect(http, contains('http.get('));
        expect(http, contains('GraphLinkGetRequest.queryParameters(payload)'));
        expect(http, contains('response.statusCode == 405'));
        expect(http, contains("throw const GraphLinkGetNotSupported('GET is not allowed');"));
      });

      test('the dio adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
        final dio = clientSerializer.generateDioAdapterFile().toFileContent();
        expect(dio, contains("import 'graph_link_persisted_queries.dart';"));
        expect(dio, contains('Future<String> getCall(String payload)'));
        expect(dio, contains('dio.get<dynamic>(url'));
        expect(dio, contains('e is DioException && e.response?.statusCode == 405'));
        expect(dio, contains('rethrow;'));
      });

      test('withHttp builds one adapter and hands its getCall to the client', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('getAdapter: _a.getCall'));
        expect(client, contains('adapter: _a.call'));
      });
    });
  });
}
