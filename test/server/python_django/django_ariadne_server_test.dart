import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/django_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:test/test.dart';

const schema = '''
directive @glRest(method: GLRestMethod!, path: String!) on FIELD_DEFINITION
enum GLRestMethod { GET POST }
type Book { id: ID! title: String! }
type Query {
  getBook(id: ID!): Book
  restBook(id: ID!): Book @glRest(method: GET, path: "/books/{id}")
}
''';

GLParser _parse() => GLParser(
      mode: CodeGenerationMode.server,
      naming: NamingConvention.python,
      reservedWords: pythonReservedWords,
      reservedTypeNames: pythonReservedTypeNames,
    )..parse(schema);

void main() {
  late GLParser parser;
  late DjangoAriadneServerSerializer django;

  setUp(() {
    parser = _parse();
    django = DjangoAriadneServerSerializer(
      parser,
      PythonSerializer(parser, runtimeDir: 'runtime'),
      DjangoAriadneServerConfig(),
    );
  });

  test('GraphQL is a Django view, only the WebSocket goes through the ASGI wrapper', () {
    final app = django.serializeEntryPoint();
    expect(app, contains('def create_urlpatterns(services: GraphLinkServices) -> List[Any]:'));
    expect(app, contains('patterns.append(path("graphql", view))'));
    expect(app, contains('build_graphql_view('));
    expect(app, contains('patterns.extend(build_rest_urlpatterns('));
    expect(app, contains('def create_app(services: GraphLinkServices, django_app: Any) -> Any:'));
    expect(app, contains('return GraphLinkWebSocketRouter(django_app, "/graphql", graphql_app)'));
    expect(app, isNot(contains('FastAPI')));
    expect(app, isNot(contains('CORSMiddleware')));
  });

  test('the FastAPI entry point is untouched by the Django flavor', () {
    final fastapi = FastapiAriadneServerSerializer(
      parser,
      PythonSerializer(parser, runtimeDir: 'runtime'),
      FastapiAriadneServerConfig(),
    );
    final app = fastapi.serializeEntryPoint();
    expect(app, contains('def create_app(services: GraphLinkServices) -> FastAPI:'));
    expect(app, contains('build_rest_router'));
  });

  test('REST handlers take the Django request and share the route table with FastAPI', () {
    final routes = django.rest.serializeRestRoutes();
    expect(routes, contains('def build_rest_routes('));
    expect(routes, contains('request: HttpRequest'));
    expect(routes, contains('from django.http import HttpRequest, HttpResponse'));
    expect(routes, contains('RestRoute("/books/{id}", {"GET": handle(rest_rest_book)}),'));
    expect(routes, contains('RestRoute("/books", {}),'));
    expect(routes, isNot(contains('starlette')));
  });

  test('the FastAPI REST handlers take the Starlette request', () {
    final fastapi = FastapiAriadneServerSerializer(
      parser,
      PythonSerializer(parser, runtimeDir: 'runtime'),
      FastapiAriadneServerConfig(),
    );
    final routes = fastapi.rest.serializeRestRoutes();
    expect(routes, contains('request: Request'));
    expect(routes, contains('from starlette.requests import Request'));
    expect(routes, isNot(contains('django')));
  });

  group('REST only', () {
    const restOnlySchema = '''
directive @glRest(method: GLRestMethod!, path: String!) on FIELD_DEFINITION
enum GLRestMethod { GET POST }
type Book { id: ID! title: String! }
type Query { restBook(id: ID!): Book @glRest(method: GET, path: "/books/{id}") }
''';

    test('there is no GraphQL view and no WebSocket wrapper', () {
      final p = GLParser(
        mode: CodeGenerationMode.server,
        naming: NamingConvention.python,
        reservedWords: pythonReservedWords,
        reservedTypeNames: pythonReservedTypeNames,
      )..parse(restOnlySchema);
      final serializer = DjangoAriadneServerSerializer(
        p,
        PythonSerializer(p, runtimeDir: 'runtime'),
        DjangoAriadneServerConfig(),
      );
      final app = serializer.serializeEntryPoint();
      expect(app, isNot(contains('build_graphql_view')));
      expect(app, isNot(contains('GraphLinkWebSocketRouter')));
      expect(app, contains('return django_app'));
      expect(app, contains('patterns.extend(build_rest_urlpatterns('));
    });
  });
}
