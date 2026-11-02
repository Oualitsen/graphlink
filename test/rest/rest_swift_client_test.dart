import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
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
    )..parse(_types + schema);

SwiftClientSerializer _client(GLParser g, {bool comma = false, bool bracket = false, bool urlSession = true}) =>
    SwiftClientSerializer(g, SwiftSerializer(g, importPrefix: 'M'),
        restViaUrlSession: urlSession, commaQueryLists: comma, bracketFormNesting: bracket);

String _generate(String schema, {bool comma = false, bool bracket = false, bool urlSession = true}) {
  final g = _parser(schema);
  final client = _client(g, comma: comma, bracket: bracket, urlSession: urlSession);
  final buffer = StringBuffer();
  for (final model in [client.getQueriesClass(), client.getMutationsClass(), client.generateClient()]) {
    if (model != null) buffer.writeln(model.toFileContent());
  }
  return buffer.toString();
}

void main() {
  final mixed = _generate('$_graphql$_rest');

  group('operations', () {
    test('become async throws methods of classes extending the REST resolver', () {
      expect(mixed, contains('class GraphLinkQueries: GraphLinkRestResolver'));
      expect(mixed, contains('public func product(id: String'));
      expect(mixed, contains('async throws -> Product?'));
      expect(mixed, contains('public func remove(id: String) async throws {'));
    });

    test('placeholders become encoded interpolations', () {
      expect(mixed, contains(r'path: "/p/\(restPath(id))"'));
    });

    test('roles select helpers', () {
      expect(mixed, contains('restSpreadEntries(filter?.toJson(), [("tag", "tag")])'));
      expect(mixed, contains('restHeader("X-X", x)'));
      expect(mixed, contains('RestBody.json(restEncodeJson(input.toJson()))'));
      expect(mixed, contains('.form(glFields__)'));
      expect(mixed, contains('RestBody.raw(file)'));
      expect(mixed, contains('.multipart(glParts__)'));
    });

    test('response kinds', () {
      expect(mixed, contains('try await restVoid(glRequest__)'));
      expect(mixed, contains('try await restTextOrNull(glRequest__)'));
      expect(mixed, contains('try await restJson(glRequest__, path: [], allowEmpty: true)'));
      expect(mixed, contains('Product.fromJson'));
    });

    test('only cached GET queries go through restCached; mutations invalidate by tag', () {
      expect(RegExp(r'try await restCached\(').allMatches(mixed).length, 1);
      expect(mixed, contains('try await invalidateByTags(["t"])'));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains('-> GLDownload {'));
      expect(mixed, contains('onReceiveProgress: DownloadProgressCallback? = nil'));
      expect(mixed, contains('restDownloadRequired(glRequest__, onProgress: onReceiveProgress)'));
    });

    test('upload operations get a progress callback', () {
      expect(mixed, contains('onProgress: UploadProgressCallback? = nil'));
      expect(mixed, contains('onSendProgress: onProgress'));
    });

    test('a default is a Swift default value and is still sent', () {
      expect(mixed, contains('n: Int? = 3'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', comma: true, bracket: true);
      expect(out, contains('restEntries("tags", tags?.map { \$0 as Any? }, bracket: true, comma: true)'));
    });
  });

  group('client', () {
    test('takes the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('restAdapter: @escaping GLRestAdapter'));
      expect(mixed, contains('glQueries.restAdapter = restAdapter'));
      expect(mixed, contains('glMutations.restAdapter = restAdapter'));
    });

    test('urlsession factory takes restBaseUrl and none makes it take the adapter', () {
      expect(mixed, contains('restBaseUrl: URL'));
      final out = _generate('$_graphql$_rest', urlSession: false);
      expect(out, isNot(contains('restBaseUrl')));
      expect(out, isNot(contains('DefaultGraphLinkRestAdapter')));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest.replaceAll('extend type', 'type'));
      final client = out.substring(out.indexOf('public final class GraphLinkClient'));
      expect(client, contains('adapter: glNoGraphQL__'));
      expect(client, isNot(contains('adapter: @escaping GraphLinkClientAdapter')));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('restAdapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    test('REST types use the regular fromJson, with no REST-only decoder', () {
      final g = _parser(_polymorphic);
      final serializer = SwiftSerializer(g, importPrefix: 'M');
      final out = [...g.projectedTypes.values, ...g.projectedInterfaces.values]
          .map(serializer.serializeTypeDefinition)
          .join('\n');
      expect(out, isNot(contains('restFromJson')));
      expect(out, contains('static func fromJson'));
    });
  });

  group('config', () {
    test('defaults and overrides', () {
      final c = SwiftClientConfig.fromJson({'moduleName': 'M'});
      expect(c.effectiveRestHttpAdapter, SwiftWsAdapter.urlsession);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      final d = SwiftClientConfig.fromJson({
        'moduleName': 'M',
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(d.effectiveRestHttpAdapter, SwiftWsAdapter.none);
      expect(d.queryListStyle, RestQueryListStyle.comma);
      expect(d.formNesting, RestFormNesting.bracket);
    });
  });
}
