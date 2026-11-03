import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

const _types = '''
scalar Upload @glUpload
scalar Void @glVoid
scalar Download @glDownload
enum Status { ACTIVE ARCHIVED }
type Product { id: ID! name: String }
input Filter { tag: String }
input In { name: String! }
''';

const _graphql = '''
type Query { ping: String }
type Mutation { pong: String }
''';

const _rest = '''
extend type Query @glRestPrefix(path: "/p") {
  product(id: ID!, filter: Filter @glRestParam, tags: [String!] @glRestParam, x: String @glRestHeader(name: "X-X")): Product @glRest(path: "/{id}")
  cached(id: ID!): Product @glRest(path: "/c/{id}") @glCache(ttl: 30, tags: ["t"])
}
extend type Mutation @glRestPrefix(path: "/p") {
  create(input: In! @glRestBody): Product! @glRest(path: "", method: POST) @glCacheInvalidate(tags: ["t"])
  remove(id: ID!): Void @glRest(path: "/{id}", method: DELETE)
  send(id: ID!, name: String @glRestField): String @glRest(path: "/{id}/s", method: POST, response: TEXT)
  put(id: ID!, file: Upload! @glRestBody): Void @glRest(path: "/{id}/f", method: PUT)
  dl(id: ID!): Download! @glRest(path: "/{id}/dl", method: POST)
  optPart(j: In @glRestPart(encoding: JSON), m: [Upload!] @glRestPart): Product @glRest(path: "/op", method: POST)
  withDefault(n: Int = 3 @glRestParam, id: ID!): Product @glRest(path: "/d/{id}", method: POST)
}
''';

const _polymorphic = '''
interface Pet @glRestDiscriminator(field: "kind", values: {Dog: "dog", Cat: "cat"}) { id: ID! name: String! }
type Dog implements Pet { id: ID! name: String! barks: Boolean! }
type Cat implements Pet { id: ID! name: String! lives: Int }
extend type Query @glRestPrefix(path: "/q") {
  pets: [Pet!]! @glRest(path: "/pets")
}
''';

GLParser _parser(String schema) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      mode: CodeGenerationMode.client,
    )..parse('$javaJsonEncoderDecorder\n$javaClientAdapterNoParamSync\n$_types$schema');

JavaClientSerializer _client(
  GLParser g, {
  bool comma = false,
  bool bracket = false,
  JavaRestHttpAdapter rest = JavaRestHttpAdapter.jdk,
  JavaReactiveFlavor flavor = JavaReactiveFlavor.blocking,
}) =>
    JavaClientSerializer(g, JavaSerializer(g, importPrefix: ''),
        flavor: flavor, restHttpAdapter: rest, commaQueryLists: comma, bracketFormNesting: bracket);

String _generate(
  String schema, {
  bool comma = false,
  bool bracket = false,
  JavaRestHttpAdapter rest = JavaRestHttpAdapter.jdk,
  JavaReactiveFlavor flavor = JavaReactiveFlavor.blocking,
}) {
  final g = _parser(schema);
  final client = _client(g, comma: comma, bracket: bracket, rest: rest, flavor: flavor);
  final buffer = StringBuffer();
  for (final model in [client.getQueriesClass(), client.getMutationsClass(), client.generateClient()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

String _decoded(String schema) {
  final g = _parser(schema);
  final serializer = JavaSerializer(g, importPrefix: '');
  return [...g.projectedTypes.values, ...g.projectedInterfaces.values].map(serializer.serializeTypeDefinition).join('\n');
}

final _reactor = JavaReactiveFlavor.of(JavaAsyncStyle.reactor);

Map<String, String> _restFiles({
  JavaReactiveFlavor flavor = JavaReactiveFlavor.blocking,
  JavaReactiveHttpClient http = JavaReactiveHttpClient.jdk,
}) {
  final g = _parser('$_graphql$_rest');
  final client = JavaClientSerializer(g, JavaSerializer(g, importPrefix: ''), flavor: flavor, reactiveHttpClient: http);
  return client.generateRestFiles().map((name, model) => MapEntry(name, model.toFileContent()));
}

void main() {
  final mixed = _generate('$_graphql$_rest');
  final reactive = _generate('$_graphql$_rest', flavor: _reactor);

  group('operations', () {
    test('become methods of classes extending the REST resolver', () {
      expect(mixed, contains('class GraphLinkQueries extends GraphLinkRestResolver'));
      expect(mixed, contains('class GraphLinkMutations extends GraphLinkRestResolver'));
      expect(mixed, contains('public Product product(String id, Filter filter, List<String> tags, String x) {'));
      expect(mixed, contains('public void remove(String id) {'));
    });

    test('placeholders become encoded concatenations and required arguments are checked', () {
      expect(mixed, contains('"/p/" + GraphLinkRestUtils.restEncode(String.valueOf(id))'));
      expect(mixed, contains('Objects.requireNonNull(id, "id is required");'));
    });

    test('roles select helpers', () {
      expect(mixed, contains('GraphLinkRestUtils.restSpreadEntries(filter == null ? null : filter.toJson(), GraphLinkRestUtils.restNames("tag", "tag"), false, false)'));
      expect(mixed, contains('GraphLinkRestUtils.restHeader("X-X", x)'));
      expect(mixed, contains('new RestBody.Json(restEncodeJson(input.toJson()))'));
      expect(mixed, contains('new RestBody.Form(glFields__)'));
      expect(mixed, contains('new RestBody.Raw(file)'));
      expect(mixed, contains('new RestBody.Multipart(glParts__)'));
    });

    test('response kinds', () {
      expect(mixed, contains('restVoid(glRequest__'));
      expect(mixed, contains('restTextOrNull(glRequest__'));
      expect(mixed, contains('restJsonOrNull(glRequest__, Collections.emptyList()'));
      expect(mixed, contains('restJson(glRequest__, Collections.emptyList()'));
    });

    test('only cached GET queries go through restCached; mutations invalidate by tag', () {
      expect(RegExp('restCached\\(').allMatches(mixed).length, 1);
      expect(mixed, contains('invalidateByTags(Arrays.asList("t"))'));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains('public GLDownload dl(String id, DownloadProgressCallback onReceiveProgress) {'));
      expect(mixed, contains('public GLDownload dl(String id) {'));
      expect(mixed, contains('restDownload(glRequest__, onReceiveProgress'));
    });

    test('guarded optional parts are parenthesized inside the concatenation', () {
      expect(mixed, contains('(j == null ? Collections.<RestPart>emptyList() :'));
      expect(mixed, contains('(m == null ? Collections.<RestPart>emptyList() :'));
    });

    test('upload operations get a progress callback overload', () {
      expect(mixed, contains('public void put(String id, GLUpload file, UploadProgressCallback onProgress) {'));
      expect(mixed, contains('public void put(String id, GLUpload file) {'));
      expect(mixed, contains('glBody__,\n         onProgress,'));
    });

    test('a default is applied when the argument is null and is still sent', () {
      expect(mixed, contains('if (n == null) {'));
      expect(mixed, contains('n = 3;'));
      expect(mixed, contains('GraphLinkRestUtils.restEntries("n", n, false, false)'));
    });
  });

  group('reactive flavor', () {
    test('operations return Mono and REST helpers are returned, not discarded', () {
      expect(reactive, contains('public Mono<Product> product(String id, Filter filter, List<String> tags, String x) {'));
      expect(reactive, contains('public Mono<Void> remove(String id) {'));
      expect(reactive, contains('return restVoid(glRequest__'));
      expect(reactive, contains('public Mono<GLDownload> dl(String id) {'));
      expect(reactive, contains('return put(id, file, null);'));
    });

    test('the blocking and reactive request construction is identical', () {
      String requests(String out) => RegExp(r'new RestRequest\([^;]*\);').allMatches(out).map((m) => m.group(0)).join('\n');
      expect(requests(reactive), requests(mixed));
    });

    test('the REST adapter returns a Mono in the reactive runtime', () {
      final adapter = javaRestAdapterInterface(_reactor);
      expect(adapter, contains('Mono<RestResponse> execute(RestRequest request);'));
      expect(javaRestAdapterInterface(JavaReactiveFlavor.blocking), contains('RestResponse execute(RestRequest request);'));
    });
  });

  group('reactive flavors', () {
    final rxjava3 = _generate('$_graphql$_rest', flavor: JavaReactiveFlavor.of(JavaAsyncStyle.rxjava3));
    final mutiny = _generate('$_graphql$_rest', flavor: JavaReactiveFlavor.of(JavaAsyncStyle.mutiny));

    test('RxJava 3 returns Maybe for nullable results and Completable for void', () {
      expect(rxjava3, contains('public Maybe<Product> product(String id, Filter filter, List<String> tags, String x) {'));
      expect(rxjava3, contains('public Single<Product> create(In input) {'));
      expect(rxjava3, contains('public Completable remove(String id) {'));
      expect(rxjava3, contains('public Maybe<String> send(String id, String name) {'));
      expect(rxjava3, contains('public Single<GLDownload> dl(String id) {'));
    });

    test('Mutiny returns Uni for every result', () {
      expect(mutiny, contains('public Uni<Product> product(String id, Filter filter, List<String> tags, String x) {'));
      expect(mutiny, contains('public Uni<Void> remove(String id) {'));
      expect(mutiny, contains('public Uni<GLDownload> dl(String id) {'));
    });

    test('a nullable cached query returns the maybe type through restCachedOrNull in every reactive flavor', () {
      expect(reactive, contains('public Mono<Product> cached(String id) {'));
      expect(rxjava3, contains('public Maybe<Product> cached(String id) {'));
      expect(mutiny, contains('public Uni<Product> cached(String id) {'));
      for (final out in [reactive, rxjava3, mutiny]) {
        expect(out, contains('return restCachedOrNull('));
        expect(out, isNot(contains('return restCached(')));
      }
    });

    test('the blocking client keeps a single restCached', () {
      expect(mixed, contains('return restCached('));
      expect(mixed, isNot(contains('restCachedOrNull')));
    });

    test('the resolver caches the optional and converts it, never mapping to null', () {
      for (final style in [JavaAsyncStyle.reactor, JavaAsyncStyle.rxjava3, JavaAsyncStyle.mutiny]) {
        final resolver = javaRestResolver(JavaReactiveFlavor.of(style), withGetAdapter: false);
        expect(resolver, contains('restCachedOrNull('));
        expect(resolver, contains('json -> Optional.ofNullable(decode.apply(json))'));
      }
      expect(javaRestResolver(JavaReactiveFlavor.blocking, withGetAdapter: false), isNot(contains('restCachedOrNull')));
    });
  });

  group('WebClient REST adapter', () {
    final webclient = _restFiles(flavor: _reactor, http: JavaReactiveHttpClient.webclient);
    final adapter = webclient['DefaultGraphLinkRestAdapter.java']!;

    test('is generated for a reactor client with reactiveHttpClient webclient', () {
      expect(adapter, contains('private final WebClient webClient;'));
      expect(adapter, contains('public Mono<RestResponse> execute(RestRequest request)'));
      expect(adapter, isNot(contains('java.net.http')));
      expect(webclient, contains('GLDataBufferInputStream.java'));
    });

    test('hands every status back as a response instead of throwing', () {
      expect(adapter, contains('onStatus(status -> true, failure -> Mono.empty())'));
    });

    test('streams downloads off the event loop and joins buffered responses without the codec limit', () {
      expect(adapter, contains('toEntityFlux(DataBuffer.class).publishOn(Schedulers.boundedElastic())'));
      expect(adapter, contains('DataBufferUtils.join(entity.getBody())'));
      expect(adapter, isNot(contains('toEntity(byte[].class)')));
    });

    test('uploads stream through an InputStreamResource with the known length', () {
      expect(adapter, contains('new InputStreamResource(in)'));
      expect(adapter, contains('public long contentLength() { return length; }'));
      expect(adapter, contains('GLMultipartBody.withProgress(upload.getStream(), upload.getLength(), request.getOnSendProgress())'));
    });

    test('follows redirects by default and decodes gzip and deflate', () {
      expect(adapter, contains('followRedirect(true)'));
      expect(adapter, contains('new GZIPInputStream(body)'));
      expect(adapter, contains('new InflaterInputStream(body)'));
    });

    test('the JDK adapter is kept for jdk, and for the blocking client whatever the setting', () {
      final jdk = _restFiles(flavor: _reactor);
      expect(jdk['DefaultGraphLinkRestAdapter.java'], contains('private final HttpClient httpClient;'));
      expect(jdk, isNot(contains('GLDataBufferInputStream.java')));
      final blocking = _restFiles(http: JavaReactiveHttpClient.webclient);
      expect(blocking['DefaultGraphLinkRestAdapter.java'], contains('private final HttpClient httpClient;'));
      expect(blocking, isNot(contains('GLDataBufferInputStream.java')));
    });

    test('the stream helper applies backpressure one buffer at a time and cancels on close', () {
      final stream = webclient['GLDataBufferInputStream.java']!;
      expect(stream, contains('subscription.request(1);'));
      expect(stream, contains('subscriber.request(1);'));
      expect(stream, contains('subscriber.dispose();'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', comma: true, bracket: true);
      expect(out, contains('GraphLinkRestUtils.restEntries("tags", tags == null ? null : tags.stream().collect(Collectors.toList()), true, true)'));
    });

    test('they are off by default', () {
      expect(mixed, contains('GraphLinkRestUtils.restEntries("tags", tags == null ? null : tags.stream().collect(Collectors.toList()), false, false)'));
    });
  });

  group('client', () {
    test('takes the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('GraphLinkClientAdapter adapter, GLRestAdapter restAdapter,'));
      expect(mixed, contains('Objects.requireNonNull(restAdapter);'));
      expect(mixed, contains('queries = new GraphLinkQueries(adapter, restAdapter,'));
      expect(mixed, contains('mutations = new GraphLinkMutations(adapter, restAdapter,'));
      expect(mixed, contains('new DefaultGraphLinkRestAdapter(restBaseUrl)'));
    });

    test('restHttpAdapter none makes the factories take the adapter', () {
      final out = _generate('$_graphql$_rest', rest: JavaRestHttpAdapter.none);
      expect(out, isNot(contains('restBaseUrl')));
      expect(out, contains('GLRestAdapter restAdapter'));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest);
      expect(out, contains('new GraphLinkNoGraphQL()'));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('RestAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    test('an interface decodes through its discriminator values', () {
      final out = _decoded(_polymorphic);
      expect(out, contains('Object discriminator = json.get("kind");'));
      expect(out, contains('case "dog":\n            return Dog.fromJson(json);'));
      expect(out, contains('Cannot decode Pet: unknown'));
      expect(out, contains('throw new IllegalArgumentException("Dog.barks is missing or null in the response");'));
      expect(out, isNot(contains('Cat.lives is missing')));
    });
  });

  group('config', () {
    test('defaults and overrides', () {
      final c = JavaClientConfig.fromJson({'packageName': 'x'});
      expect(c.restHttpAdapter, JavaRestHttpAdapter.jdk);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      final d = JavaClientConfig.fromJson({
        'packageName': 'x',
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(d.restHttpAdapter, JavaRestHttpAdapter.none);
      expect(d.queryListStyle, RestQueryListStyle.comma);
      expect(d.formNesting, RestFormNesting.bracket);
    });
  });
}
