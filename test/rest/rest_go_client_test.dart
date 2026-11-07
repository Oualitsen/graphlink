import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
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
      naming: NamingConvention.go,
      reservedWords: goReservedWords,
    )..parse(_types + schema);

GoClientSerializer _client(GLParser g, {bool comma = false, bool bracket = false, bool http = true}) =>
    GoClientSerializer(g, GoSerializer(g),
        restHttpAdapter: http ? GoHttpAdapter.nethttp : GoHttpAdapter.none,
        commaQueryLists: comma,
        bracketFormNesting: bracket);

String _generate(String schema, {bool comma = false, bool bracket = false, bool http = true}) {
  final g = _parser(schema);
  final client = _client(g, comma: comma, bracket: bracket, http: http);
  final buffer = StringBuffer();
  for (final model in [client.getQueriesClass(), client.getMutationsClass(), client.generateClient()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

void main() {
  final mixed = _generate('$_graphql$_rest');

  group('operations', () {
    test('become methods of structs embedding the REST resolver', () {
      expect(mixed, contains('GraphLinkRestResolver'));
      expect(mixed, contains('Product(ctx context.Context, id string'));
      expect(mixed, contains('(*Product, error)'));
      expect(mixed, contains('Remove(ctx context.Context, id string) error'));
    });

    test('placeholders become encoded concatenations', () {
      expect(mixed, contains('"/p/" + restPath(id)'));
    });

    test('roles select helpers', () {
      expect(mixed, contains('restSpreadEntries(glOptions__.Filter, [][2]string{{"tag", "tag"}}, false, false)'));
      expect(mixed, contains('restHeader("X-X", glOptions__.X)'));
      expect(mixed, contains('RestJSONBody{JSON: glBodyData__}'));
      expect(mixed, contains('RestFormBody{Fields: glFields__}'));
      expect(mixed, contains('RestRawBody{Upload: file}'));
      expect(mixed, contains('RestMultipartBody{Parts: glParts__}'));
    });

    test('response kinds', () {
      expect(mixed, contains('.restVoid(ctx, glRequest__)'));
      expect(mixed, contains('.restTextOrNil(ctx, glRequest__)'));
      expect(mixed, contains('.restJSON(ctx, glRequest__, []string{}, true)'));
    });

    test('only cached GET queries go through restCached; mutations invalidate by tag', () {
      expect(RegExp(r'return restCached\[').allMatches(mixed).length, 1);
      expect(mixed, contains('invalidateByTags(ctx, []string{"t"})'));
    });

    test('downloads return *GLDownload with a receive progress option', () {
      expect(mixed, contains('(*GLDownload, error)'));
      expect(mixed, contains('OnReceiveProgress DownloadProgressCallback'));
      expect(mixed, contains('restDownload(ctx, glRequest__, false, glOptions__.OnReceiveProgress)'));
    });

    test('upload operations get a progress option', () {
      expect(mixed, contains('OnProgress UploadProgressCallback'));
      expect(mixed, contains('OnSendProgress: glOptions__.OnProgress'));
    });

    test('a default is applied when the option is nil and is still sent', () {
      expect(mixed, contains('if n == nil'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', comma: true, bracket: true);
      expect(out, contains('restEntries("tags", glOptions__.Tags, true, true)'));
    });
  });

  group('client', () {
    test('options take the REST adapter and the http factory builds it', () {
      expect(mixed, contains('RestAdapter GLRestAdapter'));
      expect(mixed, contains('RestBaseURL string'));
      expect(mixed, contains('NewGraphLinkRestHttpAdapter(opts.RestBaseURL)'));
    });

    test('restHttpAdapter none makes the factory take the adapter', () {
      final out = _generate('$_graphql$_rest', http: false);
      expect(out, isNot(contains('RestBaseURL')));
      expect(out, isNot(contains('NewGraphLinkRestHttpAdapter')));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest.replaceAll('extend type', 'type'));
      expect(out, contains('adapter = glNoGraphQL__'));
      expect(out, isNot(contains('GraphLinkClientOptions.Adapter is required')));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('RestAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    test('types validate required fields in their explicit decoder', () {
      final g = _parser(_polymorphic);
      final serializer = GoSerializer(g);
      final out = g.projectedTypes.values.map(serializer.serializeTypeDefinition).join('\n');
      expect(out, contains('func DogFromJson(m map[string]any) (Dog, error) {'));
      expect(out, contains('v.Barks, err = glBool(m["barks"])'));
      expect(out, contains('glFieldError("Dog", "barks", err)'));
      expect(out, contains('v.Lives, err = glPtr(glInt)(m["lives"])'));
    });

    test('an interface decodes through its discriminator values', () {
      final g = _parser(_polymorphic);
      final serializer = GoSerializer(g);
      final out = g.projectedInterfaces.values.map(serializer.serializeTypeDefinition).join('\n');
      expect(out, contains('glStringOf(m["kind"])'));
      expect(out, contains('case "dog":'));
      expect(out, contains('Cannot decode Pet: unknown or missing'));
    });
  });

  group('config', () {
    test('defaults and overrides', () {
      final c = GoClientConfig.fromJson({});
      expect(c.effectiveRestHttpAdapter, GoHttpAdapter.nethttp);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      final d = GoClientConfig.fromJson({
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(d.effectiveRestHttpAdapter, GoHttpAdapter.none);
      expect(d.queryListStyle, RestQueryListStyle.comma);
      expect(d.formNesting, RestFormNesting.bracket);
    });
  });
}
