import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
type Query { getUser(id: ID!): User }
type User { id: ID! name: String }
''';

class _Flavor {
  final JavaAsyncStyle style;
  final String single;
  final String flatMap;
  final String recover;
  final String just;
  final String error;
  const _Flavor(this.style, this.single, this.flatMap, this.recover, this.just, this.error);
}

const _flavors = [
  _Flavor(JavaAsyncStyle.reactor, 'Mono', '.flatMap(response -> {', '.onErrorResume(e -> {', 'Mono.just(response)', 'Mono.error(e)'),
  _Flavor(JavaAsyncStyle.rxjava3, 'Single', '.flatMap(response -> {', '.onErrorResumeNext(e -> {', 'Single.just(response)', 'Single.error(e)'),
  _Flavor(JavaAsyncStyle.mutiny, 'Uni', '.chain(response -> {', '.onFailure().recoverWithUni(e -> {', 'Uni.createFrom().item(response)', 'Uni.createFrom().failure(e)'),
];

JavaClientSerializer _clientSerializer(_Flavor flavor, {bool useGet = false}) {
  final parser = GLParser(
    generateAllFieldsFragments: true,
    autoGenerateQueries: true,
    persistedQueries: true,
    persistedQueriesUseGet: useGet,
  )..parse(_schema);
  return JavaClientSerializer(parser, JavaSerializer(parser, importPrefix: ''),
      flavor: JavaReactiveFlavor.of(flavor.style));
}

String _base(JavaClientSerializer s) => s.generateGraphLinkResolverBaseFile('com.example').toFileContent();

void main() {
  for (final flavor in _flavors) {
    group('${flavor.style.name}: persisted queries on', () {
      late JavaClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(flavor));

      test('glCallAdapter keeps returning the deferred single', () {
        expect(_base(clientSerializer), contains('protected ${flavor.single}<String> glCallAdapter(GraphLinkPayload payload)'));
      });

      test('sends in full when the query is short or the server has no APQ', () {
        final base = _base(clientSerializer);
        expect(base, contains('glPersistedUnsupported__ || payload.getQuery().length() <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH'));
        expect(base, contains('return glSend(payload);'));
      });

      test('chains the retry onto the hash-only request', () {
        final base = _base(clientSerializer);
        expect(base, contains('glSend(hashOnly)${flavor.flatMap}'));
        expect(base, contains('GraphLinkPersistedQueries.failure(response, glDecoder__)'));
        expect(base, contains('return ${flavor.just};'));
        expect(base, contains('glPersistedUnsupported__ = true;'));
        expect(base, contains('body.put("extensions", extensions);'));
      });

      test('glSend hands the encoded body to the adapter without waiting for it', () {
        expect(_base(clientSerializer),
            contains('private ${flavor.single}<String> glSend(Object body)'));
      });

      test('has no GET plumbing', () {
        expect(_base(clientSerializer), isNot(contains('GetAdapter')));
      });
    });

    group('${flavor.style.name}: GET adapter', () {
      late JavaClientSerializer clientSerializer;
      setUp(() => clientSerializer = _clientSerializer(flavor, useGet: true));

      test('falls back to POST only on GraphLinkGetNotSupported, unwrapping a CompletionException', () {
        final base = _base(clientSerializer);
        expect(base, contains('glGetAdapter__.execute(glEncoder__.encode(body))${flavor.recover}'));
        expect(base, contains('e instanceof CompletionException && e.getCause() != null'));
        expect(base, contains('!(cause instanceof GraphLinkGetNotSupported)'));
        expect(base, contains('return ${flavor.error};'));
        expect(base, contains('glGetUnsupported__ = true;'));
      });

      test('mutations are never sent through the GET adapter', () {
        expect(_base(clientSerializer), contains('payload.getQuery().startsWith("mutation")'));
      });

      test('the JDK GET adapter returns the deferred single and maps 405 to GraphLinkGetNotSupported', () {
        final file = clientSerializer.generateReactiveDefaultGetAdapterFile().toFileContent();
        expect(file, contains('public class DefaultGraphLinkGetAdapter implements GraphLinkClientAdapter'));
        expect(file, contains('public ${flavor.single}<String> execute(String payload)'));
        expect(file, contains('GraphLinkGetRequest.queryString(payload, decoder, encoder)'));
        expect(file, contains('response.statusCode() == 405'));
        expect(file, contains('throw new GraphLinkGetNotSupported("GET is not allowed");'));
      });

      test('the convenience constructors hand the GET adapter to the client', () {
        final client = clientSerializer.generateClient().toFileContent();
        expect(client, contains('new DefaultGraphLinkGetAdapter(url, encoder, decoder)'));
      });
    });
  }

  test('the WebClient GET adapter maps 405 to GraphLinkGetNotSupported', () {
    final file = _clientSerializer(_flavors.first, useGet: true).generateWebClientDefaultGetAdapterFile().toFileContent();
    expect(file, contains('public Mono<String> execute(String payload)'));
    expect(file, contains('webClient.get()'));
    expect(file, contains('status.value() == 405'));
    expect(file, contains('Mono.error(new GraphLinkGetNotSupported("GET is not allowed"))'));
  });
}
