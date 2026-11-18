import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/django_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_openapi_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/spring_openapi_controller_serializer.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = r'''
type Greeting { text: String! }
type Query { greeting(name: String!): Greeting! @glRest(path: "/api/greeting/{name}") }
''';

GLParser _parse(String schema) => GLParser(mode: CodeGenerationMode.server)..parse(schema);

OpenApiOutput? _output(GLParser parser, Map<String, dynamic>? openapi) => buildOpenApiOutput(
      parser,
      GeneratorConfig.fromJson({
        'schemaPaths': <String>[],
        'mode': 'server',
        'serverConfig': {
          'expressApollo': <String, dynamic>{},
          if (openapi != null) 'openapi': openapi,
        },
      }),
    );

void main() {
  group('chunks', () {
    test('a big text is split on line boundaries and joins back unchanged', () {
      final text = List.generate(5000, (i) => 'line $i with some padding text').join('\n');
      final chunks = openApiChunks(text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.length <= 8000 + 40), isTrue);
      expect(chunks.join().trimRight(), text);
    });

    test('a small text is one chunk', () {
      expect(openApiChunks('a\nb'), hasLength(1));
    });
  });

  group('Spring', () {
    final parser = _parse(_schema);
    final spring = SpringOpenApiControllerSerializer(_output(parser, {'specPath': '/spec.json', 'title': r'Cost $5'})!, 'com.acme');

    test('Java maps both paths with a content type', () {
      final java = spring.serializeJava();
      expect(java, startsWith('@RestController\npublic class GraphLinkOpenApiController'));
      expect(java, contains('@GetMapping(value = "/spec.json", produces = "application/json")'));
      expect(java, contains('@GetMapping(value = "/docs", produces = "text/html")'));
      expect(java, contains('String.join('));
    });

    test('Kotlin escapes the dollar sign so it is not a string template', () {
      final kotlin = spring.serializeKotlin();
      expect(kotlin, contains(r'Cost \$5'));
      expect(kotlin, isNot(contains(r'Cost $5')));
      expect(kotlin, contains('@GetMapping(value = ["/spec.json"], produces = ["application/json"])'));
    });

    test('a spec over the 64 KB class-file limit is emitted as several literals', () {
      final fields = List.generate(900, (i) => 'field$i: String').join(' ');
      final big = _parse('type Big { $fields } type Query { big: Big @glRest(path: "/big") }');
      final output = _output(big, <String, dynamic>{})!;
      expect(output.spec.length, greaterThan(40000));
      expect(output.specChunks.length, greaterThan(1));
      expect(output.specChunks.every((c) => c.length < 9000), isTrue);
    });
  });

  group('NestJS', () {
    String module(Map<String, dynamic>? openapi) {
      final parser = _parse(_schema);
      return NestApolloServerSerializer(parser, TypeScriptSerializer(parser, importPrefix: ''), NestApolloServerConfig(),
              openApi: _output(parser, openapi))
          .serializeModule();
    }

    NestApolloServerSerializer serializer(Map<String, dynamic>? openapi) {
      final parser = _parse(_schema);
      return NestApolloServerSerializer(parser, TypeScriptSerializer(parser, importPrefix: ''), NestApolloServerConfig(),
          openApi: _output(parser, openapi));
    }

    test('the module registers the OpenAPI controller first', () {
      final text = module(<String, dynamic>{});
      expect(text, contains("import { OpenApiController } from './rest/openapi.controller.js';"));
      expect(text, matches(RegExp(r'controllers: \[\s*OpenApiController,')));
    });

    test('no controller without the section or with serve: false', () {
      expect(module(null), isNot(contains('OpenApiController')));
      expect(module({'file': 'x.json', 'serve': false}), isNot(contains('OpenApiController')));
    });

    test('the controller serves the spec and the docs on the configured paths', () {
      final controller = serializer({'specPath': '/spec.json', 'docsPath': '/explorer'}).rest.serializeOpenApiController();
      expect(controller, contains('@Controller()'));
      expect(controller, contains('@Get("/spec.json")'));
      expect(controller, contains('@Get("/explorer")'));
      expect(controller, contains('res.type("application/json").send(openApiSpec);'));
      expect(controller, contains('res.type("text/html").send(openApiDocsPage);'));
    });
  });

  group('Python', () {
    final parser = _parse(_schema);
    final py = PythonSerializer(parser, runtimeDir: 'runtime');
    final output = _output(parser, {'specPath': '/spec.json', 'docsPath': '/explorer'})!;

    test('FastAPI mounts a router before the REST router, outside its own schema', () {
      final file = PythonOpenApiSerializer(output, py).serializeFastapi();
      expect(file, contains('@router.get("/spec.json", include_in_schema=False)'));
      expect(file, contains('@router.get("/explorer", include_in_schema=False)'));
      expect(file, contains('media_type="application/json"'));
      final app = FastapiAriadneServerSerializer(parser, py, FastapiAriadneServerConfig(), openApi: output).serializeCreateApp('"/graphql"');
      expect(app, contains('app.include_router(build_openapi_router())'));
      expect(app.indexOf('build_openapi_router'), lessThan(app.indexOf('build_rest_router')));
    });

    test('FastAPI keeps its own docs and schema disabled', () {
      final app = FastapiAriadneServerSerializer(parser, py, FastapiAriadneServerConfig()).serializeCreateApp('"/graphql"');
      expect(app, contains('docs_url=None, redoc_url=None, openapi_url=None'));
      expect(app, isNot(contains('build_openapi_router')));
    });

    test('Django adds two urlpatterns without the leading slash', () {
      final file = PythonOpenApiSerializer(output, py).serializeDjango();
      expect(file, contains('path("spec.json", openapi_spec)'));
      expect(file, contains('path("explorer", openapi_docs)'));
      final app = DjangoAriadneServerSerializer(parser, py, DjangoAriadneServerConfig(), openApi: output).serializeCreateApp('"/graphql"');
      expect(app, contains('patterns.extend(build_openapi_urlpatterns())'));
    });

    test('the spec literal keeps a dollar sign and quotes intact', () {
      final withTitle = _output(parser, {'title': 'Say "hi" \$5'})!;
      expect(PythonOpenApiSerializer(withTitle, py).serializeFastapi(), contains(r'Say \\\"hi\\\" $5'));
    });
  });
}
