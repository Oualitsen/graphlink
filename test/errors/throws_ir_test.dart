import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_error_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

const _base = '''
type Article { id: ID! title: String }
input ArticleInput { title: String! }
type ArticleNotFound @glError { id: ID! }
type TitleTaken @glError { title: String! }
type NotFound @glError(value: "NOT_FOUND") { id: ID }
type Gone @glError(value: "NOT_FOUND") { id: ID }
''';

GLParser _parse(String body, {CodeGenerationMode mode = CodeGenerationMode.client}) =>
    GLParser(mode: mode)..parse('$_base$body');

void _fails(String body, Pattern message) {
  expect(() => _parse(body), throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('resolution', () {
    test('a query field lists the errors it throws, in declaration order', () {
      final g = _parse('type Query { article(id: ID!): Article @glThrows(errors: [ArticleNotFound, NotFound]) }');
      final thrown = g.thrownErrors[const GLOperationKey('article', GLQueryType.query)]!;
      expect(thrown.map((e) => e.name), ['ArticleNotFound', 'NotFound']);
      expect(thrown.first, same(g.errors['ArticleNotFound']));
    });

    test('a mutation field lists its errors', () {
      final g = _parse('''
        type Query { a: Article }
        type Mutation { create(input: ArticleInput!): Article @glThrows(errors: [TitleTaken]) }
      ''');
      expect(g.thrownErrors[const GLOperationKey('create', GLQueryType.mutation)]!.map((e) => e.name), ['TitleTaken']);
    });

    test('a field without the directive throws nothing', () {
      final g = _parse('type Query { article(id: ID!): Article }');
      expect(g.thrownErrors, isEmpty);
    });

    test('the same error may be thrown by several operations', () {
      final g = _parse('''
        type Query {
          one(id: ID!): Article @glThrows(errors: [ArticleNotFound])
          two(id: ID!): Article @glThrows(errors: [ArticleNotFound])
        }
      ''');
      expect(g.thrownErrors.length, 2);
    });

    test('server mode resolves them too', () {
      final g = _parse('type Query { article(id: ID!): Article @glThrows(errors: [ArticleNotFound]) }',
          mode: CodeGenerationMode.server);
      expect(g.thrownErrors.length, 1);
    });
  });

  group('placement', () {
    test('rejected on a field of a normal type', () {
      _fails('type Query { a: Article } type Wrapper { article: Article @glThrows(errors: [ArticleNotFound]) }',
          'root field');
    });

    test('rejected on a subscription field', () {
      _fails('''
        type Query { a: Article }
        type Subscription { added: Article @glThrows(errors: [ArticleNotFound]) }
      ''', 'subscription');
    });

    test('rejected on an input field', () {
      _fails('input Other { title: String @glThrows(errors: [ArticleNotFound]) } type Query { a: Article }', '@glThrows');
    });

    test('rejected on a type', () {
      _fails('type Query { a: Article } type Other @glThrows(errors: [ArticleNotFound]) { id: ID }', '@glThrows');
    });

    test('rejected on a custom query', () {
      _fails('''
        type Query { article(id: ID!): Article }
        query load @glThrows(errors: [ArticleNotFound]) { article(id: "1") { id } }
      ''', '@glThrows');
    });

    test('rejected on a custom mutation', () {
      _fails('''
        type Query { a: Article }
        type Mutation { create(input: ArticleInput!): Article }
        mutation make @glThrows(errors: [TitleTaken]) { create(input: {title: "x"}) { id } }
      ''', '@glThrows');
    });

    test('works on a root field of an extended Query', () {
      final g = _parse('''
        type Query { a: Article }
        extend type Query { article(id: ID!): Article @glThrows(errors: [ArticleNotFound]) }
      ''');
      expect(g.thrownErrors.keys.map((k) => k.fieldName), ['article']);
    });

    test('works with a custom root type name declared in schema', () {
      final g = _parse('''
        schema { query: Root }
        type Root { article(id: ID!): Article @glThrows(errors: [ArticleNotFound]) }
      ''');
      expect(g.thrownErrors.keys.map((k) => k.fieldName), ['article']);
    });
  });

  group('errors argument', () {
    test('is required', () {
      _fails('type Query { a: Article @glThrows }', 'errors');
    });

    test('an empty list is rejected', () {
      _fails('type Query { a: Article @glThrows(errors: []) }', 'at least one');
    });

    test('an unknown name is rejected and named', () {
      _fails('type Query { a: Article @glThrows(errors: [Nope]) }', 'Nope');
    });

    test('a type that is not an @glError is rejected', () {
      _fails('type Query { a: Article @glThrows(errors: [Article]) }', 'Article');
    });

    test('a duplicate is rejected', () {
      _fails('type Query { a: Article @glThrows(errors: [ArticleNotFound, ArticleNotFound]) }', 'ArticleNotFound');
    });

    test('two errors with the same discriminator in one list are ambiguous', () {
      _fails('type Query { a: Article @glThrows(errors: [NotFound, Gone]) }', 'ambiguous');
    });

    test('the same discriminator is fine when no single operation throws both', () {
      final g = _parse('''
        type Query {
          a: Article @glThrows(errors: [NotFound])
          b: Article @glThrows(errors: [Gone])
        }
      ''');
      expect(g.thrownErrors.length, 2);
    });

    test('an unknown argument is rejected', () {
      _fails('type Query { a: Article @glThrows(errors: [ArticleNotFound], code: "x") }', 'code');
    });
  });

  group('operations of the client', () {
    const schema = '''
      type Query {
        article(id: ID!): Article @glThrows(errors: [ArticleNotFound])
        other(id: ID!): Article
      }
      type Mutation { create(input: ArticleInput!): Article @glThrows(errors: [TitleTaken]) }
      query load { article(id: "1") { id } }
      query aliased { first: article(id: "1") { id } }
      query pair { a: article(id: "1") { id } b: other(id: "2") { id } }
      query plain { other(id: "1") { id } }
      query captured @glCaptureErrors { article(id: "1") { id } }
    ''';
    late GLParser g;
    setUpAll(() => g = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)..parse('$_base$schema'));

    GLThrownErrors? of(String name, [GLQueryType type = GLQueryType.query]) =>
        g.thrownErrorsOf(g.queries[GLOperationKey(name, type)]!);

    test('an auto-generated operation throws the errors of its root field', () {
      final thrown = of('article')!;
      expect(thrown.errors.map((e) => e.name), ['ArticleNotFound']);
      expect(thrown.responseKey, 'article');
    });

    test('a mutation throws its errors', () {
      expect(of('create', GLQueryType.mutation)!.errors.map((e) => e.name), ['TitleTaken']);
    });

    test('a custom operation with one root field throws them', () {
      expect(of('load')!.errors.map((e) => e.name), ['ArticleNotFound']);
    });

    test('an alias becomes the response key', () {
      expect(of('aliased')!.responseKey, 'first');
    });

    test('an operation with several root fields throws no typed error', () {
      expect(of('pair'), isNull);
    });

    test('a root field without the directive throws none', () {
      expect(of('other'), isNull);
      expect(of('plain'), isNull);
    });

    test('capture-errors operations throw none', () {
      expect(of('captured'), isNull);
    });
  });
}
