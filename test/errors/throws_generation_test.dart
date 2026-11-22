import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

import 'error_test_support.dart';

const _schema = '''
type Article { id: ID! }
type NotFound @glError { id: ID! }
type Gone @glError(field: "extensions.kind", value: "gone") { }
type Query {
  article(id: ID!): Article @glThrows(errors: [NotFound, Gone])
  plain(id: ID!): Article
  other(id: ID!): Article @glThrows(errors: [NotFound])
}
query pair { a: article(id: "1") { id } b: other(id: "2") { id } }
query captured @glCaptureErrors { article(id: "1") { id } }
''';

GLParser _parse({NamingConvention? naming, Set<String>? reserved}) => GLParser(
      autoGenerateQueries: true,
      generateAllFieldsFragments: true,
      naming: naming ?? NamingConvention.dart,
      reservedWords: reserved ?? const {},
    )..parse(_schema);

GLQueryDefinition _op(GLParser g, String name) => g.queries[GLOperationKey(name, GLQueryType.query)]!;

void main() {
  group('Dart', () {
    late GLParser g;
    late DartClientSerializer client;
    setUp(() {
      g = _parse();
      client = DartClientSerializer(g, DartSerializer(g, importPrefix: ''));
    });

    test('a throwing operation maps the errors list through its matchers', () {
      final out = flat(client.renderQueryMethod(_op(g, 'article')));
      expect(out, contains('catch (e) { if (e is! List<GraphLinkError>) { rethrow; }'));
      expect(out, contains("throw glDomainError(e, 'article', ["));
      expect(out, contains('GraphLinkDomainMatcher( ["extensions", "code"], "NotFound",'));
      expect(out, contains('GraphLinkDomainMatcher( ["extensions", "kind"], "gone",'));
    });

    test('an operation without @glThrows, a combined query and a capture-errors query stay untouched', () {
      for (final name in ['plain', 'pair', 'captured']) {
        expect(client.renderQueryMethod(_op(g, name)), isNot(contains('glDomainError')), reason: name);
      }
    });

    test('the resolver base only gets the matcher helper when something throws', () {
      expect(client.runtime.buildResolverBaseClass(), contains('Object glDomainError('));
      final none = GLParser()..parse('type Query { a: String }');
      expect(DartClientSerializer(none, DartSerializer(none, importPrefix: '')).runtime.buildResolverBaseClass(),
          isNot(contains('glDomainError')));
    });
  });

  group('Python', () {
    test('a throwing operation catches and resolves', () {
      final g = _parse(naming: NamingConvention.python, reserved: pythonReservedWords);
      final out = flat(PythonClientSerializer(g, PythonSerializer(g)).renderQueryMethod(_op(g, 'article')));
      expect(out, contains('except Exception as e:'));
      expect(out, contains('typed = gl_domain_error(e, "article", ['));
      expect(out, contains('if typed is None: raise'));
      expect(out, contains('raise typed from e'));
    });
  });

  group('Go', () {
    test('a throwing operation resolves the error of an inner function', () {
      final g = _parse(naming: NamingConvention.go, reserved: goReservedWords);
      final out = flat(GoClientSerializer(g, GoSerializer(g)).renderQueryMethod(_op(g, 'article')));
      expect(out, contains('glTyped__, glErr__ := func() (ArticleResponse, error) {'));
      expect(out, contains('return glZero__, glDomainError(glErr__, "article", []GraphLinkDomainMatcher{'));
      expect(out, contains('NotFoundFromJson(m, message)'));
    });
  });

  group('TypeScript', () {
    test('a throwing operation throws the resolved error', () {
      final g = _parse(naming: NamingConvention.typescript);
      final out = flat(TypeScriptClientSerializer(g, TypeScriptSerializer(g, importPrefix: '')).renderQueryMethod(_op(g, 'article')));
      expect(out, contains("throw glDomainError(gl_fullResponse__.errors, 'article', ["));
      expect(out, contains('build: (extensions, message) => NotFound.fromJson(extensions, message)'));
    });
  });
}
