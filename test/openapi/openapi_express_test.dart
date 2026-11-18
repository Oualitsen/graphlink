import 'dart:convert';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Greeting { text: String! }
type Query { greeting(name: String!): Greeting! @glRest(path: "/api/greeting/{name}") }
''';

String _router(Map<String, dynamic>? openapi) {
  final parser = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
  final config = GeneratorConfig.fromJson({
    'schemaPaths': <String>[],
    'mode': 'server',
    'serverConfig': {
      'expressApollo': <String, dynamic>{},
      if (openapi != null) 'openapi': openapi,
    },
  });
  return ExpressApolloServerSerializer(parser, TypeScriptSerializer(parser, importPrefix: ''), ExpressApolloServerConfig())
      .serializeRestRouter(openApi: buildOpenApiOutput(parser, config));
}

void main() {
  test('without an openapi section the router serves nothing extra', () {
    final router = _router(null);
    expect(router, isNot(contains('openApiSpec')));
    expect(router, isNot(contains('/openapi.json')));
  });

  test('serve: false adds no route', () {
    expect(_router({'file': 'openapi.json', 'serve': false}), isNot(contains('openApiSpec')));
  });

  test('serves the spec and the docs page on the configured paths', () {
    final router = _router({'specPath': '/spec.json', 'docsPath': '/explorer', 'title': 'Hi'});
    expect(router, matches(RegExp(r'router\.get\(\s*"/spec\.json"')));
    expect(router, matches(RegExp(r'router\.get\(\s*"/explorer"')));
    expect(router, contains("res.type(\"application/json\").send(openApiSpec);"));
    expect(router, contains("res.type(\"text/html\").send(openApiDocsPage);"));
  });

  test('the embedded spec round-trips to the generated document', () {
    final router = _router(<String, dynamic>{});
    final literal = RegExp(r'const openApiSpec = (".*");').firstMatch(router)!.group(1)!;
    final spec = jsonDecode(jsonDecode(literal) as String) as Map<String, dynamic>;
    expect(spec['paths'], contains('/api/greeting/{name}'));
  });

  test('the spec routes come before the REST routes', () {
    final router = _router(<String, dynamic>{});
    expect(router.indexOf('"/openapi.json"'), lessThan(router.indexOf('"/api/greeting/:name"')));
  });
}
