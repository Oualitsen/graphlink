import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
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
  opt(file: Upload @glRestBody, id: ID!): Product @glRest(path: "/opt/{id}", method: PUT)
  optJson(body: In @glRestBody): Product @glRest(path: "/oj", method: POST)
  optPart(j: In @glRestPart(encoding: JSON), m: [Upload!] @glRestPart): Product @glRest(path: "/op", method: POST)
  parts(files: [Upload!]! @glRestPart): Product @glRest(path: "/parts", method: POST)
}
''';

String _generate(String schema,
    {bool commaLists = false, bool bracket = false, DartHttpAdapter? restAdapter, DartHttpAdapter adapter = DartHttpAdapter.http}) {
  final g = GLParser()..parse('$_types$schema');
  final serializer = DartSerializer(g, importPrefix: '');
  final client = DartClientSerializer(g, serializer,
      httpAdapter: adapter, restHttpAdapter: restAdapter, commaQueryLists: commaLists, bracketFormNesting: bracket);
  final buffer = StringBuffer();
  for (final model in [client.getQueriesClass(), client.getMutationsClass(), client.generateClientOnlyFile()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

void main() {
  final mixed = _generate('$_graphql$_rest');

  group('operations', () {
    test('become methods of the query and mutation classes with the REST mixin', () {
      expect(mixed, contains('class GraphLinkQueries extends GraphLinkResolverBase with GraphLinkRestResolver'));
      expect(mixed, contains('class GraphLinkMutations extends GraphLinkResolverBase with GraphLinkRestResolver'));
      expect(mixed, contains('Future<Product?> product({'));
      expect(mixed, contains('Future<void> remove({'));
    });

    test('placeholders become encoded interpolations', () {
      expect(mixed, contains(r"path: '/p/${Uri.encodeComponent(id.toString())}'"));
    });

    test('roles select helpers', () {
      expect(mixed, contains("...restSpreadEntries(filter?.toJson(), {'tag': 'tag'})"));
      expect(mixed, contains("...restEntries('tags', tags)"));
      expect(mixed, contains("if (x != null) 'X-X': restHeaderValue(x)"));
      expect(mixed, contains('RestJsonBody(jsonEncode(input.toJson()))'));
      expect(mixed, contains('RestFormBody(glFields__)'));
      expect(mixed, contains('RestRawBody(file)'));
      expect(mixed, contains('RestMultipartBody(glParts__)'));
    });

    test('response kinds', () {
      expect(mixed, contains('await restVoid__(glRequest__)'));
      expect(mixed, contains('await restTextOrNull__(glRequest__)'));
      expect(mixed, contains('restJson__(glRequest__, [], true)'));
    });

    test('only cached GET queries go through restCached__; mutations invalidate by tag', () {
      expect(RegExp('restCached__').allMatches(mixed).length, 1);
      expect(mixed, contains('await invalidateByTags(["t"])'));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains('Future<GLDownload> dl({'));
      expect(mixed, contains('DownloadProgressCallback? onReceiveProgress'));
      expect(mixed, contains('(await restDownload__(glRequest__, false, onReceiveProgress))!'));
    });

    test('optional uploads are nullable parameters', () {
      expect(mixed, contains('GLUpload? file'));
    });

    test('values read after a null guard use no null-aware access', () {
      expect(mixed, contains('RestJsonBody(jsonEncode(body.toJson()))'));
      expect(mixed, isNot(contains('body?.toJson()')));
      expect(mixed, contains('jsonEncode(j.toJson())'));
      expect(mixed, contains('...m.map((e) => RestPart.file'));
    });

    test('upload operations get a progress callback', () {
      expect(mixed, contains('UploadProgressCallback? onProgress'));
      expect(mixed, contains('onSendProgress: onProgress'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', commaLists: true, bracket: true);
      expect(out, contains("...restEntries('tags', tags, bracket: true, comma: true)"));
    });
  });

  group('client', () {
    test('requires the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('required GLRestAdapter restAdapter'));
      expect(mixed, contains('queries.restAdapter = restAdapter;'));
      expect(mixed, contains('mutations.restAdapter = restAdapter;'));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest.replaceFirst('extend type Query', 'type Query { _x: String }\nextend type Query'));
      expect(out, contains('adapter = glNoGraphQL__'));
      expect(out, isNot(contains('required Future<String> Function(String payload) adapter')));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('RestAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('rest adapter selection', () {
    test('withHttp builds the REST adapter from restBaseUrl by default', () {
      expect(mixed, contains('required String restBaseUrl'));
      expect(mixed, contains('GraphLinkRestHttpAdapter(baseUrl: restBaseUrl, headersProvider: headersProvider).call'));
    });

    test('restHttpAdapter dio uses the Dio REST adapter', () {
      final out = _generate('$_graphql$_rest', restAdapter: DartHttpAdapter.dio);
      expect(out, contains('GraphLinkRestDioAdapter(baseUrl: restBaseUrl'));
    });

    test('restHttpAdapter none makes withHttp take the adapter', () {
      final out = _generate('$_graphql$_rest', restAdapter: DartHttpAdapter.none);
      expect(out, isNot(contains('restBaseUrl')));
      expect(out, contains('restAdapter: restAdapter'));
    });

    test('the REST adapter follows httpAdapter unless overridden', () {
      final out = _generate('$_graphql$_rest', adapter: DartHttpAdapter.dio);
      expect(out, contains('GraphLinkRestDioAdapter'));
    });
  });

  group('config', () {
    test('defaults', () {
      final c = DartClientConfig.fromJson({});
      expect(c.restHttpAdapter, isNull);
      expect(c.effectiveRestHttpAdapter, DartHttpAdapter.http);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      expect(c.formNesting, RestFormNesting.dot);
    });

    test('keys are read case-insensitively', () {
      final c = DartClientConfig.fromJson({
        'httpAdapter': 'dio',
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(c.effectiveRestHttpAdapter, DartHttpAdapter.none);
      expect(c.queryListStyle, RestQueryListStyle.comma);
      expect(c.formNesting, RestFormNesting.bracket);
    });
  });
}
