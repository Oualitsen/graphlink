import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
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
    )..parse(kotlinJsonEncoderDecoder + kotlinClientAdapterGql + _types + schema);

KotlinClientSerializer _client(GLParser g, {bool comma = false, bool bracket = false, KotlinWsAdapter? rest}) =>
    KotlinClientSerializer(g, KotlinSerializer(g, importPrefix: ''),
        restHttpAdapter: rest, commaQueryLists: comma, bracketFormNesting: bracket);

String _generate(String schema, {bool comma = false, bool bracket = false, KotlinWsAdapter? rest}) {
  final g = _parser(schema);
  final client = _client(g, comma: comma, bracket: bracket, rest: rest);
  final buffer = StringBuffer();
  for (final model in [client.getQueriesClass(), client.getMutationsClass(), client.generateClient()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

void main() {
  final mixed = _generate('$_graphql$_rest');

  group('operations', () {
    test('become suspend methods of classes extending the REST resolver', () {
      expect(mixed, contains('GraphLinkRestResolver('));
      expect(mixed, contains('suspend fun product(id: String'));
      expect(mixed, contains('): Product? {'));
      expect(mixed, contains('suspend fun remove(id: String): Unit'));
    });

    test('placeholders become encoded interpolations', () {
      expect(mixed, contains(r'path = "/p/${restEncode(id.toString())}"'));
    });

    test('roles select helpers', () {
      expect(mixed, contains('restSpreadEntries(filter?.toJson(), mapOf("tag" to "tag"))'));
      expect(mixed, contains('restHeader("X-X", x)'));
      expect(mixed, contains('RestJsonBody(restEncodeJson(input.toJson()))'));
      expect(mixed, contains('RestFormBody(glFields__)'));
      expect(mixed, contains('RestRawBody(file)'));
      expect(mixed, contains('RestMultipartBody(glParts__)'));
    });

    test('response kinds', () {
      expect(mixed, contains('restVoid(glRequest__)'));
      expect(mixed, contains('restTextOrNull(glRequest__)'));
      expect(mixed, contains('restJson(glRequest__, emptyList(), true)'));
    });

    test('only cached GET queries go through restCached; mutations invalidate by tag', () {
      expect(RegExp('restCached<').allMatches(mixed).length, 1);
      expect(mixed, contains('invalidateByTags(listOf("t"))'));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains('): GLDownload {'));
      expect(mixed, contains('onReceiveProgress: DownloadProgressCallback? = null'));
      expect(mixed, contains('restDownload(glRequest__, false, onReceiveProgress)!!'));
    });

    test('guarded optional parts are parenthesized inside the list sum', () {
      expect(mixed, contains('(if (j == null) emptyList<RestPart>() else'));
      expect(mixed, contains('(if (m == null) emptyList<RestPart>() else m.map'));
    });

    test('upload operations get a progress callback', () {
      expect(mixed, contains('onProgress: UploadProgressCallback? = null'));
      expect(mixed, contains('onSendProgress = onProgress'));
    });

    test('a default is a Kotlin default value and is still sent', () {
      expect(mixed, contains('n: Int? = 3'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', comma: true, bracket: true);
      expect(out, contains('restEntries("tags", tags, bracket = true, comma = true)'));
    });
  });

  group('client', () {
    test('takes the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('private val restAdapter: GLRestAdapter'));
      expect(mixed, contains('queries.restAdapter = restAdapter'));
      expect(mixed, contains('mutations.restAdapter = restAdapter'));
      expect(mixed, contains('DefaultGraphLinkRestAdapter(restBaseUrl)'));
    });

    test('restHttpAdapter none makes the factories take the adapter', () {
      final out = _generate('$_graphql$_rest', rest: KotlinWsAdapter.none);
      expect(out, isNot(contains('restBaseUrl')));
      expect(out, contains('restAdapter: GLRestAdapter'));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest);
      expect(out, contains('= GraphLinkNoGraphQL'));
      expect(out, isNot(contains('private val adapter: GraphLinkClientAdapter,')));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('RestAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    test('an interface decodes through its discriminator values', () {
      final g = _parser(_polymorphic);
      final serializer = KotlinSerializer(g, importPrefix: '');
      final out = [...g.projectedTypes.values, ...g.projectedInterfaces.values]
          .map(serializer.serializeTypeDefinition)
          .join('\n');
      expect(out, contains('val discriminator = map["kind"]'));
      expect(out, contains('"dog" -> return Dog.fromJson(map)'));
      expect(out, contains('Cannot decode Pet: unknown or missing'));
      expect(out, contains('throw IllegalArgumentException("Dog.barks is missing or null in the response")'));
      expect(out, isNot(contains('Cat.lives is missing')));
    });
  });

  group('config', () {
    test('defaults and overrides', () {
      final c = KotlinClientConfig.fromJson({'packageName': 'x'});
      expect(c.effectiveRestHttpAdapter, KotlinWsAdapter.okhttp);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      final d = KotlinClientConfig.fromJson({
        'packageName': 'x',
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(d.effectiveRestHttpAdapter, KotlinWsAdapter.none);
      expect(d.queryListStyle, RestQueryListStyle.comma);
      expect(d.formNesting, RestFormNesting.bracket);
    });
  });
}
