import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  directive @glValidate on FIELD_DEFINITION
  scalar Void @glVoid

  type Author { id: ID! name: String! books: [Book!] @glSkipOnServer(batch: true) }
  type Book { id: ID! title: String! }
  input NewBook { title: String! }

  type Query {
    getAuthor(id: ID!): Author
    listBooks: [Book!]! @glValidate
    item(id: ID!): Book @glRest(path: "/items/{id}")
    remove(id: ID!): Void @glRest(path: "/items/{id}", method: DELETE)
  }
  type Mutation { addBook(input: NewBook!): Book! }
  type Subscription { bookAdded: Book! }
''';

const _queryOnly = 'type Query { ping: Boolean! }';

GLParser _parse(String schema) => GLParser(mode: CodeGenerationMode.server)..parse(schema);

NestApolloServerSerializer _serializer(GLParser parser, {NestApolloServerConfig? config}) => NestApolloServerSerializer(
      parser,
      TypeScriptSerializer(parser, importPrefix: ''),
      config ?? NestApolloServerConfig(),
    );

void main() {
  late GLParser parser;
  late NestApolloServerSerializer serializer;

  setUp(() {
    parser = _parse(_schema);
    serializer = _serializer(parser);
  });

  test('a service is an abstract class, so it is its own injection token', () {
    final service = serializer.serializeService(parser.services.values.firstWhere((s) => s.token == 'BookService'));
    expect(service, contains('export abstract class BookService {'));
    expect(service, contains('abstract addBook(input: NewBook): Promise<Book>;'));
    expect(service, contains('abstract bookAdded(): AsyncIterable<Book>;'));
    expect(service, isNot(contains('interface')));
  });

  test('a guard is an abstract class with a method for the validated field only', () {
    final guard = serializer.serializeGuard(parser.services.values.firstWhere((s) => s.token == 'BookService'))!;
    expect(guard, contains('export abstract class BookGuard {'));
    expect(guard, contains('abstract validateListBooks(): Promise<void>;'));
  });

  group('root resolver', () {
    late String resolver;
    setUp(() => resolver = serializer.serializeResolverFiles()['book-service.resolver.ts']!);

    test('is a Nest resolver whose collaborators are constructor-injected through their tokens', () {
      expect(resolver, contains('@Resolver()'));
      expect(resolver, contains('export class BookServiceResolver {'));
      expect(resolver, contains('@Inject(BookService) private readonly bookService: BookService'));
      expect(resolver, contains('@Inject(BookGuard) private readonly bookGuard: BookGuard'));
    });

    test('binds each root field with the matching decorator', () {
      expect(resolver, contains('@Query("listBooks")'));
      expect(resolver, contains('@Mutation("addBook")'));
      expect(resolver, contains('@Subscription("bookAdded"'));
      expect(resolver, contains('@Args("input") input: NewBook'));
    });

    test('runs the guard before the service', () {
      expect(resolver, contains('await this.bookGuard.validateListBooks();'));
      expect(resolver.indexOf('validateListBooks'), lessThan(resolver.indexOf('this.bookService.listBooks()')));
    });

    test('does not resolve @glRest operations as GraphQL fields', () {
      expect(resolver, isNot(contains('"item"')));
    });
  });

  test('a batch mapping is a @ResolveField reading the per-request loader', () {
    final fields = serializer.serializeResolverFiles()['author-fields.resolver.ts']!;
    expect(fields, contains('@Resolver("Author")'));
    expect(fields, contains('@ResolveField("books")'));
    expect(fields, contains('context.loaders.authorBooks.load(parent)'));
  });

  group('rest controllers', () {
    test('one controller per service with injected service and route decorators', () {
      final controllers = {
        for (final service in serializer.rest.restServices) service.token: serializer.rest.serializeController(service),
      };
      expect(controllers.keys, containsAll(['BookService', 'RemoveService']));
      final item = controllers['BookService']!;
      expect(item, contains('@Controller()'));
      expect(item, contains('@Inject(BookService) private readonly bookService: BookService'));
      expect(item, contains('@Get("/items/:id")'));
      expect(item, contains('@Req() req: Request, @Res() res: Response'));
      expect(controllers['RemoveService'], contains('@Delete("/items/:id")'));
    });

    test('the fallback answers 405 for a path served under other methods and 404 below the prefix', () {
      final fallback = serializer.rest.serializeFallbackController();
      expect(fallback, contains('@All("/items/:id")'));
      expect(fallback, contains('sendMethodNotAllowed(res, ["GET", "DELETE"])'));
      expect(fallback, contains('@All("/items")'));
      expect(fallback, contains('@All("/items/*splat")'));
    });

    test('the fallback is registered after every real controller', () {
      expect(serializer.rest.controllerClassNames.last, 'RestFallbackController');
    });
  });

  group('module', () {
    late String module;
    setUp(() => module = serializer.serializeModule());

    test('is a dynamic module taking the modules that provide the services', () {
      expect(module, contains('export class GraphLinkModule implements NestModule {'));
      expect(module, contains('static forRoot(options: GraphLinkModuleOptions = {}): DynamicModule'));
      expect(module, contains('...(options.imports ?? [])'));
    });

    test('registers resolvers, controllers and the exception filter as providers', () {
      expect(module, contains('BookServiceResolver,'));
      expect(module, contains('AuthorFieldsResolver,'));
      expect(module, contains('{ provide: APP_FILTER, useClass: GraphLinkExceptionFilter }'));
    });

    test('hosts GraphQL through the Apollo driver, schema first, and limits query depth', () {
      expect(module, contains('GraphQLModule.forRootAsync<ApolloDriverConfig>'));
      expect(module, contains('driver: ApolloDriver'));
      expect(module, contains('includeStacktraceInErrorResponses: false'));
      expect(module, contains('queryDepthGuard('));
      expect(module, contains('subscribeErrors(payload?.query, maxQueryDepth)'));
    });

    test('creates the loaders from the injected services for every request', () {
      expect(module, contains('inject: ['));
      expect(module, contains('context.loaders = createLoaders(context);'));
    });
  });

  test('a schema without subscriptions or REST binds neither', () {
    final plain = _parse(_queryOnly);
    final module = _serializer(plain).serializeModule();
    expect(module, isNot(contains('subscriptions:')));
    expect(module, isNot(contains('RestFallbackController')));
    expect(module, isNot(contains('inject: [\n')));
  });

  test('a REST-only schema generates no GraphQL module, resolvers or request guards', () {
    final restOnly = _parse('''
      type Item { id: ID! }
      type Query { item(id: ID!): Item @glRest(path: "/items/{id}") }
    ''');
    final restOnlySerializer = _serializer(restOnly);
    final module = restOnlySerializer.serializeModule();
    expect(module, isNot(contains('GraphQLModule')));
    expect(module, isNot(contains('MiddlewareConsumer')));
    expect(module, contains('RestFallbackController'));
    expect(restOnlySerializer.serializeResolverFiles(), isEmpty);
    expect(restOnlySerializer.serializeExceptionFilter(), isNot(contains('graphqlErrorBody')));
  });

  test('the exception filter answers GraphQL errors on the GraphQL path and REST errors elsewhere', () {
    final filter = serializer.serializeExceptionFilter();
    expect(filter, contains('@Catch()'));
    expect(filter, contains("if (host.getType<string>() === 'graphql') return error;"));
    expect(filter, contains('if (req.path === graphqlPath)'));
    expect(filter, contains('sendError(res, restErrorStatus(error));'));
  });

  test('the interceptor is an abstract class, injected by its token', () {
    final intercepted = _parse('''
      enum Roles { ADMIN }
      type Query { secret: String! @glIntercept }
    ''');
    final out = _serializer(intercepted).serializeInterceptorInterface()!;
    expect(out, contains('export abstract class GraphLinkInterceptor {'));
    expect(out, contains('abstract runBefore('));
  });

  group('config', () {
    test('nestApollo selects the NestJS target', () {
      final config = ServerLanguageConfig.fromJson({
        'nestApollo': {'port': 3001, 'graphqlPath': '/gql', 'injectContext': true, 'useResolveInfo': true},
      });
      expect(config, isA<NestApolloServerConfig>());
      final nest = config as NestApolloServerConfig;
      expect(nest.port, 3001);
      expect(nest.graphqlPath, '/gql');
      expect(nest.injectContext, isTrue);
      expect(nest.useResolveInfo, isTrue);
      expect(nest.generateEntryPoint, isTrue);
    });

    test('defaults to port 3000 on /graphql', () {
      final nest = ServerLanguageConfig.fromJson({'nestApollo': <String, dynamic>{}}) as NestApolloServerConfig;
      expect(nest.port, 3000);
      expect(nest.graphqlPath, '/graphql');
    });

    test('the error for an unknown server lists nestApollo', () {
      expect(() => ServerLanguageConfig.fromJson({}), throwsA(predicate((e) => e.toString().contains('nestApollo'))));
    });
  });
}
