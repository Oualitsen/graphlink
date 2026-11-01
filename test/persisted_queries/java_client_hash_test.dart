import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

JavaClientSerializer _clientSerializer({required bool persistedQueries, bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: persistedQueries,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return JavaClientSerializer(parser, JavaSerializer(parser, importPrefix: ''));
}

String _base(JavaClientSerializer s) => s.generateGraphLinkResolverBaseFile('com.example').toFileContent();

void main() {
  group('persisted queries off', () {
    late JavaClientSerializer clientSerializer;
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
      expect(_base(clientSerializer), contains('return glAdapter__.execute(glEncoder__.encode(payload));'));
    });
  });

  group('persisted queries on', () {
    late JavaClientSerializer clientSerializer;
    setUp(() => clientSerializer = _clientSerializer(persistedQueries: true));

    test('the resolver base exposes glHash, computed once per query string', () {
      final base = _base(clientSerializer);
      expect(base, contains('public String glHash(String query)'));
      expect(base, contains('glHashes__.get(query)'));
      expect(base, contains('GraphLinkSha256.hex(query)'));
    });

    test('glCallAdapter sends a hash first for queries above the length threshold', () {
      final base = _base(clientSerializer);
      expect(base, contains('glPersistedUnsupported__'));
      expect(base, contains('payload.getQuery().length() <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH'));
      expect(base, contains('GraphLinkPersistedQueries.extensions(glHash(payload.getQuery()))'));
    });

    test('retries with the query only for the known failures', () {
      final base = _base(clientSerializer);
      expect(base, contains('GraphLinkPersistedQueries.failure(response, glDecoder__)'));
      expect(base, contains('glPersistedUnsupported__ = true;'));
      expect(base, contains('body.put("extensions", extensions);'));
    });

    test('the sha256 and protocol files carry the runtime', () {
      expect(clientSerializer.generateSha256File().toFileContent(), contains('class GraphLinkSha256'));
      final file = clientSerializer.generatePersistedQueriesFile().toFileContent();
      expect(file, contains('final class GraphLinkPersistedQueries'));
      expect(file, contains('static final int MIN_QUERY_LENGTH = 144;'));
      expect(file, isNot(contains('GraphLinkGetNotSupported')));
    });
  });

  group('GET adapter', () {
    test('is absent unless persistedQueriesUseGet is on', () {
      final clientSerializer = _clientSerializer(persistedQueries: true);
      expect(_base(clientSerializer), isNot(contains('GetAdapter')));
      expect(clientSerializer.generateClient().toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.getQueriesClass()!.toFileContent(), isNot(contains('getAdapter')));
      expect(clientSerializer.generateGetNotSupportedFile, throwsStateError);
      expect(clientSerializer.generateGetRequestFile, throwsStateError);
      expect(() => clientSerializer.generateDefaultGetAdapterFile('java11'), throwsStateError);
    });

    group('when on', () {
      late JavaClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(persistedQueries: true, useGet: true));

      test('the resolver base holds the adapter and remembers a refusal', () {
        final base = _base(clientSerializer);
        expect(base, contains('GraphLinkClientAdapter getAdapter'));
        expect(base, contains('e instanceof GraphLinkGetNotSupported'));
        expect(base, contains('glGetUnsupported__ = true;'));
      });

      test('mutations are never sent through the GET adapter', () {
        expect(_base(clientSerializer), contains('payload.getQuery().startsWith("mutation")'));
      });

      test('the client takes a getAdapter right after the adapter and passes it down', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('GraphLinkClientAdapter adapter, GraphLinkClientAdapter getAdapter'));
        expect(client, contains('new GraphLinkQueries(adapter, getAdapter, '));
        final queries = clientSerializer.getQueriesClass()!.toFileContent();
        expect(queries, contains('GraphLinkClientAdapter getAdapter'));
        expect(queries, contains(RegExp(r'super\(\s*adapter,\s*getAdapter,')));
      });

      test('the exception is a public class in its own file', () {
        final file = clientSerializer.generateGetNotSupportedFile().toFileContent();
        expect(file, contains('public class GraphLinkGetNotSupported extends RuntimeException'));
        expect(clientSerializer.generatePersistedQueriesFile().toFileContent(), isNot(contains('GraphLinkGetNotSupported')));
      });

      test('the URL builder is a public class in its own file', () {
        final file = clientSerializer.generateGetRequestFile().toFileContent();
        expect(file, contains('public final class GraphLinkGetRequest'));
        expect(file, contains('public static String queryString('));
      });

      for (final flavor in ['java11', 'okhttp']) {
        test('the $flavor GET adapter issues a GET and maps 405 to GraphLinkGetNotSupported', () {
          final file = clientSerializer.generateDefaultGetAdapterFile(flavor).toFileContent();
          expect(file, contains('class DefaultGraphLinkGetAdapter implements GraphLinkClientAdapter'));
          expect(file, contains('GraphLinkGetRequest.queryString(payload, decoder, encoder)'));
          expect(file, contains('405'));
          expect(file, contains('throw new GraphLinkGetNotSupported("GET is not allowed");'));
        });
      }

      test('the convenience constructors hand the GET adapter to the client', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('new DefaultGraphLinkGetAdapter(url, encoder, decoder)'));
        expect(client, contains('new DefaultGraphLinkGetAdapter(url, headersProvider, encoder, decoder)'));
      });
    });
  });
}
