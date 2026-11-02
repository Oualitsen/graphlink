import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
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
  withDefault(n: Int = 3 @glRestParam, id: ID!): Product @glRest(path: "/d/{id}", method: POST)
}
''';

const _polymorphic = '''
interface Pet @glRestDiscriminator(field: "kind", values: {Dog: "dog", Cat: "cat"}) { id: ID! name: String! }
type Dog implements Pet { id: ID! name: String! barks: Boolean! }
type Cat implements Pet { id: ID! name: String! lives: Int }
union Hit @glRestDiscriminator(field: "type", values: {Dog: "d", Product: "p"}) = Dog | Product
extend type Query @glRestPrefix(path: "/q") {
  pets: [Pet!]! @glRest(path: "/pets")
  hits: [Hit!]! @glRest(path: "/hits")
}
''';

String _generate(
  String schema, {
  bool commaLists = false,
  bool bracket = false,
  bool observables = false,
  TypeScriptHttpAdapter restAdapter = TypeScriptHttpAdapter.fetch,
}) {
  final g = GLParser()..parse('$_types$schema');
  final serializer = TypeScriptSerializer(g, importPrefix: '');
  final client = TypeScriptClientSerializer(
    g,
    serializer,
    observables: observables,
    restHttpAdapter: restAdapter,
    commaQueryLists: commaLists,
    bracketFormNesting: bracket,
  );
  final buffer = StringBuffer();
  for (final model in [client.generateQueriesFile(), client.generateMutationsFile(), client.generateClientOnlyFile()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

String _types_(String schema) {
  final g = GLParser()..parse('$_types$schema');
  final serializer = TypeScriptSerializer(g, importPrefix: '');
  final buffer = StringBuffer();
  for (final def in [...g.projectedTypes.values, ...g.projectedInterfaces.values]) {
    buffer.writeln(serializer.serializeTypeDefinition(def));
  }
  return buffer.toString();
}

void main() {
  final mixed = _generate('$_graphql$_rest');

  group('operations', () {
    test('become methods of the query and mutation classes extending the REST resolver', () {
      expect(mixed, contains('export class GraphLinkQueries extends GraphLinkRestResolver'));
      expect(mixed, contains('export class GraphLinkMutations extends GraphLinkRestResolver'));
      expect(mixed, contains('async product(args: '));
      expect(mixed, contains('Promise<Product | null>'));
      expect(mixed, contains('async remove(args: '));
      expect(mixed, contains('Promise<void>'));
    });

    test('placeholders become encoded interpolations', () {
      expect(mixed, contains(r'path: `/p/${restEncode(String(args.id))}`'));
    });

    test('roles select helpers', () {
      expect(mixed, contains("...restSpreadEntries(args.filter != null ? Filter.toJson(args.filter) : args.filter, { 'tag': 'tag' })"));
      expect(mixed, contains("...restEntries('tags', args.tags != null ? args.tags.map((e0) => e0) : args.tags)"));
      expect(mixed, contains("...restHeader('X-X', args.x)"));
      expect(mixed, contains("{ kind: 'json', json: JSON.stringify(In.toJson(args.input)) }"));
      expect(mixed, contains("{ kind: 'form', fields: gl_fields__ }"));
      expect(mixed, contains("{ kind: 'raw', upload: args.file }"));
      expect(mixed, contains("{ kind: 'multipart', parts: gl_parts__ }"));
    });

    test('response kinds', () {
      expect(mixed, contains('await this.restVoid__(gl_request__)'));
      expect(mixed, contains('await this.restTextOrNull__(gl_request__)'));
      expect(mixed, contains('this.restJson__(gl_request__, [], true)'));
    });

    test('only cached GET queries go through restCached__; mutations invalidate by tag', () {
      expect(RegExp('this.restCached__').allMatches(mixed).length, 1);
      expect(mixed, contains("await this._invalidateByTags(['t'])"));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains('Promise<GLDownload>'));
      expect(mixed, contains('onReceiveProgress?: DownloadProgressCallback'));
      expect(mixed, contains('(await this.restDownload__(gl_request__, false, onReceiveProgress))!'));
    });

    test('optional uploads are nullable members', () {
      expect(mixed, contains('file?: GLUpload | null;'));
    });

    test('values read after a null guard are not wrapped again', () {
      expect(mixed, contains("args.body == null ? null : { kind: 'json', json: JSON.stringify(In.toJson(args.body)) }"));
      expect(mixed, contains('...(args.m == null ? [] : [...args.m.map((e) => ({ name:'));
    });

    test('upload operations get a progress callback', () {
      expect(mixed, contains('onProgress?: UploadProgressCallback'));
      expect(mixed, contains('onSendProgress: onProgress'));
    });

    test('a default is applied before encoding and still sent', () {
      expect(mixed, contains('const gl_n__ = args.n ?? 3;'));
      expect(mixed, contains("...restEntries('n', gl_n__)"));
    });

    test('observables wrap the result in an Observable', () {
      final out = _generate('$_graphql$_rest', observables: true);
      expect(out, contains('Observable<Product | null>'));
      expect(out, contains('subscriber.next(gl_value__);'));
      expect(out, contains('subscriber.error(gl_error__)'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', commaLists: true, bracket: true);
      expect(out, contains(": args.tags, { bracket: true, comma: true })"));
    });
  });

  group('client', () {
    test('requires the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('restAdapter: GLRestAdapter'));
      expect(mixed, contains('this.queries.restAdapter = restAdapter;'));
      expect(mixed, contains('this.mutations.restAdapter = restAdapter;'));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest.replaceFirst('extend type Query', 'type Query { _x: String }\nextend type Query'));
      expect(out, contains('constructor(restAdapter: GLRestAdapter, store?: GraphLinkCacheStore)'));
      expect(out, contains('new GraphLinkQueries(glNoGraphQL__,'));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('RestAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    final types = _types_('$_polymorphic');

    test('an interface decodes through its discriminator values', () {
      expect(types, contains('const typename = json["__typename"];'));
      expect(types, contains('const discriminator = json["kind"];'));
      expect(types, contains('case "dog":'));
      expect(types, contains('case "cat":'));
      expect(types, contains('Cannot decode Pet: unknown or missing "kind" value'));
    });

    test('a union decodes through its own discriminator values', () {
      expect(types, contains('const discriminator = json["type"];'));
      expect(types, contains('case "d":'));
      expect(types, contains('case "p":'));
    });

    test('a REST-reachable type names the missing non-null field', () {
      expect(types, contains("throw new Error('Dog.barks is missing or null in the response');"));
      expect(types, isNot(contains("Cat.lives is missing")));
    });

    test('types no REST operation reaches carry no checks', () {
      final out = _types_('$_graphql');
      expect(out, isNot(contains('is missing or null in the response')));
    });
  });

  group('config', () {
    test('defaults', () {
      final c = TypeScriptClientConfig.fromJson({});
      expect(c.restHttpAdapter, isNull);
      expect(c.effectiveRestHttpAdapter, TypeScriptHttpAdapter.fetch);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      expect(c.formNesting, RestFormNesting.dot);
    });

    test('keys are read case-insensitively and the REST adapter can differ', () {
      final c = TypeScriptClientConfig.fromJson({
        'httpAdapter': 'fetch',
        'restHttpAdapter': 'axios',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(c.effectiveRestHttpAdapter, TypeScriptHttpAdapter.axios);
      expect(c.queryListStyle, RestQueryListStyle.comma);
      expect(c.formNesting, RestFormNesting.bracket);
    });
  });

  group('adapters file', () {
    test('is generated for fetch and axios and skipped for none', () {
      final g = GLParser()..parse('$_types$_graphql$_rest');
      TypeScriptClientSerializer make(TypeScriptHttpAdapter a) =>
          TypeScriptClientSerializer(g, TypeScriptSerializer(g, importPrefix: ''), restHttpAdapter: a);
      expect(make(TypeScriptHttpAdapter.fetch).generateRestAdaptersFile()!.toFileContent(), contains('createRestFetchAdapter'));
      expect(make(TypeScriptHttpAdapter.axios).generateRestAdaptersFile()!.toFileContent(), contains('createRestAxiosAdapter'));
      expect(make(TypeScriptHttpAdapter.none).generateRestAdaptersFile(), isNull);
    });
  });
}
