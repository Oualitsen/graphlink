import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
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
      naming: NamingConvention.python,
      reservedWords: pythonReservedWords,
    )..parse(_types + schema);

PythonClientSerializer _client(
  GLParser g, {
  bool comma = false,
  bool bracket = false,
  PythonHttpAdapter rest = PythonHttpAdapter.httpx,
}) =>
    PythonClientSerializer(g, PythonSerializer(g),
        restHttpAdapter: rest, commaQueryLists: comma, bracketFormNesting: bracket);

String _generate(
  String schema, {
  bool comma = false,
  bool bracket = false,
  PythonHttpAdapter rest = PythonHttpAdapter.httpx,
}) {
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
    test('become async methods of classes extending the REST resolver', () {
      expect(mixed, contains('class GraphLinkQueries(GraphLinkRestResolver):'));
      expect(mixed, contains('async def product(self, *, id: str'));
      expect(mixed, contains(') -> Optional[Product]:'));
      expect(mixed, contains('async def remove(self, *, id: str) -> None:'));
    });

    test('placeholders become encoded interpolations', () {
      expect(mixed, contains(r'path=f"/p/{rest_encode(rest_text(id))}"'));
    });

    test('roles select helpers', () {
      expect(mixed, contains('rest_spread_entries((None if filter is None else filter.to_json())'));
      expect(mixed, contains('**rest_header("X-X", x)'));
      expect(mixed, contains('RestJsonBody(rest_encode_json(input.to_json()))'));
      expect(mixed, contains('RestFormBody(gl_fields__)'));
      expect(mixed, contains('RestRawBody(file)'));
      expect(mixed, contains('RestMultipartBody(gl_parts__)'));
    });

    test('response kinds', () {
      expect(mixed, contains('await self.rest_void__(gl_request__)'));
      expect(mixed, contains('await self.rest_text_or_null__(gl_request__)'));
      expect(mixed, contains('await self.rest_json__(gl_request__, [], True)'));
    });

    test('only cached GET queries go through rest_cached__; mutations invalidate by tag', () {
      expect(RegExp(r'self\.rest_cached__\(').allMatches(mixed).length, 1);
      expect(mixed, contains('await self.invalidate_by_tags(["t"])'));
    });

    test('downloads return GLDownload with a receive progress callback', () {
      expect(mixed, contains(') -> GLDownload:'));
      expect(mixed, contains('on_receive_progress: Optional[DownloadProgressCallback] = None'));
      expect(mixed, contains('await self.rest_download__(gl_request__, False, on_receive_progress)'));
    });

    test('optional parts are guarded', () {
      expect(mixed, contains('[] if j is None else [RestPart(name="j"'));
      expect(mixed, contains('[] if m is None else [RestPart(name="m", file=e) for e in m]'));
    });

    test('upload operations get a progress callback', () {
      expect(mixed, contains('on_progress: Optional[UploadProgressCallback] = None'));
      expect(mixed, contains('on_send_progress=on_progress'));
    });

    test('a default is a Python default value and is still sent', () {
      expect(mixed, contains('n: Optional[int] = 3'));
    });
  });

  group('list options', () {
    test('comma and bracket options are forwarded to the runtime helpers', () {
      final out = _generate('$_graphql$_rest', comma: true, bracket: true);
      expect(out, contains('rest_entries("tags", tags, bracket=True, comma=True)'));
    });
  });

  group('client', () {
    test('takes the REST adapter and wires it to the groups that have REST operations', () {
      expect(mixed, contains('rest_adapter: GLRestAdapter'));
      expect(mixed, contains('rest_adapter=rest_adapter'));
      expect(mixed, contains('GraphLinkRestHttpxAdapter(base_url=rest_base_url'));
    });

    test('restHttpAdapter none makes with_http take the adapter', () {
      final out = _generate('$_graphql$_rest', rest: PythonHttpAdapter.none);
      expect(out, isNot(contains('rest_base_url')));
      expect(out, isNot(contains('GraphLinkRestHttpxAdapter')));
    });

    test('a REST-only schema needs no GraphQL adapter', () {
      final out = _generate(_rest.replaceAll('extend type', 'type'));
      final client = out.substring(out.indexOf('class GraphLinkClient'));
      expect(client, contains('gl_no_graphql__,'));
      expect(client, isNot(contains('adapter: Callable[[str], Awaitable[str]]')));
    });

    test('a schema without REST operations is untouched', () {
      final out = _generate(_graphql);
      expect(out, isNot(contains('rest_adapter')));
      expect(out, isNot(contains('GraphLinkRestResolver')));
    });
  });

  group('decoding', () {
    test('an interface decodes through its discriminator values', () {
      final g = _parser(_polymorphic);
      final serializer = PythonSerializer(g);
      final out = [...g.projectedTypes.values, ...g.projectedInterfaces.values]
          .map(serializer.serializeTypeDefinition)
          .join('\n');
      expect(out, contains('discriminator = json.get("kind")'));
      expect(out, contains('"dog": Dog'));
      expect(out, contains('Cannot decode Pet: unknown or missing'));
    });
  });

  group('config', () {
    test('defaults and overrides', () {
      final c = PythonClientConfig.fromJson({});
      expect(c.effectiveRestHttpAdapter, PythonHttpAdapter.httpx);
      expect(c.queryListStyle, RestQueryListStyle.repeat);
      final d = PythonClientConfig.fromJson({
        'restHttpAdapter': 'none',
        'queryListStyle': 'COMMA',
        'formNesting': 'BRACKET',
      });
      expect(d.effectiveRestHttpAdapter, PythonHttpAdapter.none);
      expect(d.queryListStyle, RestQueryListStyle.comma);
      expect(d.formNesting, RestFormNesting.bracket);
    });
  });
}
