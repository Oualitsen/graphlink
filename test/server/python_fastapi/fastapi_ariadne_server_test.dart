import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

const schema = '''
directive @glValidate on FIELD_DEFINITION

type Author { id: ID! name: String! books: [Book!] @glSkipOnServer(batch: true) }
type Book { id: ID! title: String! }
input NewBook { title: String! }
type Query { getAuthor(id: ID!): Author  listBooks: [Book!]! @glValidate }
type Mutation { addBook(input: NewBook!): Book! }
type Subscription { bookAdded: Book! }
''';

FastapiAriadneServerSerializer _serializer(GLParser parser, {bool injectContext = false}) => FastapiAriadneServerSerializer(
      parser,
      PythonSerializer(parser, runtimeDir: 'runtime'),
      FastapiAriadneServerConfig(injectContext: injectContext),
    );

GLParser _parse() => GLParser(
      mode: CodeGenerationMode.server,
      naming: NamingConvention.python,
      reservedWords: pythonReservedWords,
      reservedTypeNames: pythonReservedTypeNames,
    )..parse(schema);

void main() {
  late GLParser parser;
  late FastapiAriadneServerSerializer serializer;

  setUp(() {
    parser = _parse();
    serializer = _serializer(parser);
  });

  test('a service is a Protocol of async methods, subscriptions return an async iterator', () {
    final book = serializer.serializeService(parser.services.values.firstWhere((s) => s.token == 'BookService'));
    expect(book, contains('class BookService(Protocol):'));
    expect(book, contains('async def add_book(self, input: NewBook) -> Book:'));
    expect(book, contains('def book_added(self) -> AsyncIterator[Book]:'));
  });

  test('context is only a parameter when injected', () {
    final plain = serializer.serializeService(parser.services.values.firstWhere((s) => s.token == 'AuthorService'));
    expect(plain, isNot(contains('GraphLinkContext')));
    final injected = _serializer(parser, injectContext: true)
        .serializeService(parser.services.values.firstWhere((s) => s.token == 'AuthorService'));
    expect(injected, contains('context: GraphLinkContext'));
  });

  test('a guard method exists for the validated field only', () {
    final guard = serializer.serializeGuard(parser.services.values.firstWhere((s) => s.token == 'BookService'))!;
    expect(guard, contains('async def validate_list_books(self) -> None:'));
  });

  test('resolvers bind root fields and decode arguments through from_json', () {
    final resolvers = serializer.serializeResolvers().single;
    expect(resolvers, contains('@query.field("getAuthor")'));
    expect(resolvers, contains('@mutation.field("addBook")'));
    expect(resolvers, contains('NewBook.from_json(args.get("input"))'));
    expect(resolvers, contains('@subscription.source("bookAdded")'));
    expect(resolvers, contains('async for item in book_service.book_added()'));
  });

  test('a batch mapping is served by a per-request loader', () {
    final resolvers = serializer.serializeResolvers().single;
    expect(resolvers, contains('context.loaders.author_books'));
    final loader = serializer.serializeLoader(parser.services.values.firstWhere((s) => s.token == 'AuthorSchemaMappingsService'))!;
    expect(loader, contains('def create_author_books_loader('));
    expect(loader, contains('GraphLinkLoader(load_batch)'));
  });

  test('the entry point mounts GraphQL over HTTP and WebSocket and hides the explorer', () {
    final app = serializer.serializeEntryPoint();
    expect(app, contains('Route("/graphql", graphql_app)'));
    expect(app, contains('WebSocketRoute("/graphql", graphql_app)'));
    expect(app, contains('explorer=ExplorerHttp405()'));
    expect(app, contains('max_depth_rule(max_depth)'));
  });

  test('only the root types the schema declares are bound', () {
    final queryOnly = GLParser(
      mode: CodeGenerationMode.server,
      naming: NamingConvention.python,
      reservedWords: pythonReservedWords,
      reservedTypeNames: pythonReservedTypeNames,
    )..parse('type Query { ping: Boolean! }');
    final resolvers = _serializer(queryOnly).serializeResolvers().single;
    expect(resolvers, contains('query = QueryType()'));
    expect(resolvers, isNot(contains('MutationType()')));
    expect(resolvers, isNot(contains('SubscriptionType()')));
    expect(resolvers, contains('make_executable_schema(TYPE_DEFS, query)'));
  });

  group('uploads', () {
    const uploadSchema = '''
      directive @glUpload on SCALAR
      scalar Upload @glUpload
      type Query { ping: Boolean! }
      type Mutation {
        one(file: Upload!): Boolean!
        many(files: [Upload!]!): Boolean!
        maybe(file: Upload): Boolean!
      }
    ''';

    late GLParser uploads;
    setUp(() {
      uploads = GLParser(
        mode: CodeGenerationMode.server,
        naming: NamingConvention.python,
        reservedWords: pythonReservedWords,
        reservedTypeNames: pythonReservedTypeNames,
      )..parse(uploadSchema);
    });

    test('arguments are wrapped into FileUpload', () {
      final resolvers = _serializer(uploads).serializeResolvers().single;
      expect(resolvers, contains('file = to_file_upload(args.get("file"))'));
      expect(resolvers, contains('files = [to_file_upload(e0) for e0 in args.get("files")]'));
      expect(resolvers, contains('from .file_upload import to_file_upload'));
    });

    test('the service takes FileUpload, optional or listed as declared', () {
      final service = _serializer(uploads).serializeService(uploads.services.values.firstWhere((s) => s.token == 'OneService'));
      expect(service, contains('file: FileUpload'));
      final maybe = _serializer(uploads).serializeService(uploads.services.values.firstWhere((s) => s.token == 'MaybeService'));
      expect(maybe, contains('file: Optional[FileUpload]'));
    });
  });

  group('useResolveInfo', () {
    FastapiAriadneServerSerializer withInfo(GLParser p) => FastapiAriadneServerSerializer(
          p,
          PythonSerializer(p, runtimeDir: 'runtime'),
          FastapiAriadneServerConfig(useResolveInfo: true),
        );

    test('resolver-backed methods get info, subscriptions do not', () {
      final p = _parse();
      final author = withInfo(p).serializeService(p.services.values.firstWhere((s) => s.token == 'AuthorService'));
      expect(author, contains('info: GraphQLResolveInfo'));
      final book = withInfo(p).serializeService(p.services.values.firstWhere((s) => s.token == 'BookService'));
      expect(book, contains('def book_added(self) -> AsyncIterator[Book]:'));
    });

    test('guards get info too', () {
      final p = _parse();
      final guard = withInfo(p).serializeGuard(p.services.values.firstWhere((s) => s.token == 'BookService'))!;
      expect(guard, contains('info: GraphQLResolveInfo'));
    });
  });
}
