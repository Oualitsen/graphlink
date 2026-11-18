import 'dart:convert';
import 'dart:io';

import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/generators/openapi_generator.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/openapi_constants.dart';
import 'package:test/test.dart';

const _rest = 'type Item { id: ID! } type Query { item: Item @glRest(path: "/item") }';
const _graphqlOnly = 'type Item { id: ID! } type Query { item: Item }';

GeneratorConfig _config(Map<String, dynamic>? openapi, {String outputDir = 'out'}) => GeneratorConfig.fromJson({
      'schemaPaths': <String>[],
      'mode': 'server',
      'outputDir': outputDir,
      'serverConfig': {
        'expressApollo': <String, dynamic>{},
        if (openapi != null) 'openapi': openapi,
      },
    });

OpenApiOutput? _output(String schema, Map<String, dynamic>? openapi) =>
    buildOpenApiOutput(GLParser()..parse(schema), _config(openapi));

void main() {
  group('buildOpenApiOutput', () {
    test('nothing without an openapi section', () {
      expect(_output(_rest, null), isNull);
    });

    test('a configured section with no REST operation is ignored', () {
      expect(_output(_graphqlOnly, <String, dynamic>{}), isNull);
      expect(_output(_graphqlOnly, {'file': 'openapi.json', 'serve': true}), isNull);
    });

    test('the spec is valid JSON and the docs page points at the spec path', () {
      final out = _output(_rest, {'specPath': '/spec.json', 'title': 'Shop'})!;
      expect(jsonDecode(out.spec)['paths'], contains('/item'));
      expect(out.docsPage, contains("url: '/spec.json'"));
      expect(out.docsPage, contains('<title>Shop</title>'));
      expect(out.serve, isTrue);
    });
  });

  group('docs page', () {
    test('pins the swagger-ui version', () {
      final page = openApiDocsPage(title: '', specPath: '/openapi.json');
      expect(page, contains('swagger-ui-dist@$swaggerUiVersion/'));
      expect(page, isNot(contains('@latest')));
    });

    test('escapes the title and the spec path', () {
      final page = openApiDocsPage(title: '<b>&"', specPath: "/it's</script>");
      expect(page, contains('<title>&lt;b&gt;&amp;&quot;</title>'));
      expect(page, contains(r"url: '/it\'s<\/script>'"));
    });
  });

  group('writeOpenApiFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('openapi_gen'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes plain JSON at its own path, independent of outputDir, without a generated header', () async {
      final path = '${dir.path}/src/main/resources/static/openapi.json';
      final out = _output(_rest, {'file': path});
      final written = await writeOpenApiFile(out);
      expect(written, {path});
      final text = File(written.single).readAsStringSync();
      expect(jsonDecode(text)['openapi'], '3.1.0');
    });

    test('writes nothing without a file key, without a section, or without REST', () async {
      expect(await writeOpenApiFile(_output(_rest, <String, dynamic>{})), isEmpty);
      expect(await writeOpenApiFile(_output(_rest, null)), isEmpty);
      expect(await writeOpenApiFile(_output(_graphqlOnly, {'file': '${dir.path}/openapi.json'})), isEmpty);
      expect(dir.listSync(), isEmpty);
    });
  });
}
