import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';

const _base = '''
enum Reason { gone banned }
scalar DateTime
type Article { id: ID! title: String }
input ArticleInput { title: String! }
interface Node { id: ID! }
''';

GLParser _parse(String body, {CodeGenerationMode mode = CodeGenerationMode.client}) =>
    GLParser(mode: mode)..parse('$_base$body');

void _fails(String body, Pattern message) {
  expect(() => _parse(body), throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('declaration', () {
    test('defaults: GraphQL discriminator is extensions.code equal to the type name', () {
      final g = _parse('''
        type ArticleNotFound @glError { id: ID! }
        type Query { article(id: ID!): Article }
      ''');
      final error = g.errors['ArticleNotFound']!;
      expect(error.field, ['extensions', 'code']);
      expect(error.value, 'ArticleNotFound');
      expect(error.status, isNull);
      expect(error.type.fields.map((f) => f.name.token), ['id']);
    });

    test('field, value and status are read from the directive', () {
      final g = _parse('''
        type RepoNotFound @glError(field: "type", value: "NOT_FOUND", status: 404) { id: ID }
        type Query { article(id: ID!): Article }
      ''');
      final error = g.errors['RepoNotFound']!;
      expect(error.field, ['type']);
      expect(error.value, 'NOT_FOUND');
      expect(error.status, 404);
    });

    test('a dotted field becomes a path', () {
      final g = _parse('type NotFound @glError(field: "extensions.problem.type") { id: ID }');
      expect(g.errors['NotFound']!.field, ['extensions', 'problem', 'type']);
    });

    test('status alone is accepted', () {
      final g = _parse('type Gone @glError(status: 410) { }');
      expect(g.errors['Gone']!.status, 410);
    });

    test('an error without fields is allowed', () {
      final g = _parse('type Forbidden @glError { }');
      expect(g.errors['Forbidden']!.type.fields, isEmpty);
    });

    test('fields may be scalars, enums, custom scalars and lists of them', () {
      final g = _parse('type Banned @glError { reason: Reason! at: DateTime tags: [String!] }');
      expect(g.errors['Banned']!.type.fields.map((f) => f.name.token).toSet(), {'reason', 'at', 'tags'});
    });
  });

  group('placement in the IR', () {
    test('error types are not under types, other types are', () {
      final g = _parse('''
        type ArticleNotFound @glError { id: ID! }
        type Query { article(id: ID!): Article }
      ''');
      expect(g.types.containsKey('ArticleNotFound'), isFalse);
      expect(g.types.containsKey('Article'), isTrue);
      expect(g.errors.keys, ['ArticleNotFound']);
    });

    test('error types are not interfaces, inputs or projected types either', () {
      final g = _parse('type ArticleNotFound @glError { id: ID! }');
      expect(g.interfaces.containsKey('ArticleNotFound'), isFalse);
      expect(g.inputs.containsKey('ArticleNotFound'), isFalse);
      expect(g.projectedTypes.keys.where((k) => k.contains('ArticleNotFound')), isEmpty);
    });

    test('server mode does not serve them either', () {
      final g = _parse('type ArticleNotFound @glError { id: ID! }', mode: CodeGenerationMode.server);
      expect(g.types.containsKey('ArticleNotFound'), isFalse);
      expect(g.errors.containsKey('ArticleNotFound'), isTrue);
    });

    test('a schema without errors has an empty map', () {
      expect(_parse('type Query { a: Article }').errors, isEmpty);
    });
  });

  group('an error is never a normal type', () {
    const error = 'type ArticleNotFound @glError { id: ID! }\n';

    test('as a field type of an object type', () {
      _fails('${error}type Wrapper { failure: ArticleNotFound }', 'ArticleNotFound');
    });

    test('as a list element of a field', () {
      _fails('${error}type Wrapper { failures: [ArticleNotFound!]! }', '@glError');
    });

    test('as a query return type', () {
      _fails('${error}type Query { article(id: ID!): ArticleNotFound }', 'ArticleNotFound');
    });

    test('as a mutation return type', () {
      _fails('${error}type Mutation { remove(id: ID!): ArticleNotFound }', 'Mutation.remove');
    });

    test('as a field argument type', () {
      _fails('${error}type Query { article(failure: ArticleNotFound): Article }', 'an argument type');
    });

    test('as an input field type', () {
      _fails('${error}input Holder { failure: ArticleNotFound }', 'an input field type');
    });

    test('as an interface field type', () {
      _fails('${error}interface Holder { failure: ArticleNotFound }', 'ArticleNotFound');
    });

    test('as a union member', () {
      _fails('${error}union ArticleResult = Article | ArticleNotFound', 'member of union ArticleResult');
    });

    test('as an interface implementer', () {
      _fails('type Missing implements Node @glError { id: ID! }', 'implement');
    });

    test('inside an @glExternal type', () {
      _fails('${error}type Ext @glExternal(glClass: "com.acme.Ext") { failure: ArticleNotFound }', 'ArticleNotFound');
    });

    test('the message says what to do', () {
      _fails('${error}type Wrapper { failure: ArticleNotFound }', 'cannot be used as a field type');
    });
  });

  group('extensions of an error type', () {
    test('fields added by extend type join the error and stay out of types', () {
      final g = _parse('type ArticleNotFound @glError { id: ID! }\nextend type ArticleNotFound { hint: String }');
      expect(g.types.containsKey('ArticleNotFound'), isFalse);
      expect(g.errors['ArticleNotFound']!.type.fields.map((f) => f.name.token), containsAll(['id', 'hint']));
    });

    test('an extension field that clashes with the base exception is rejected', () {
      _fails('type ArticleNotFound @glError { id: ID! }\nextend type ArticleNotFound { message: String }', 'message');
    });

    test('an extension field of an object type is rejected', () {
      _fails('type ArticleNotFound @glError { id: ID! }\nextend type ArticleNotFound { article: Article }', 'scalar');
    });

    test('an extension declared before the base type still joins the error', () {
      final g = _parse('extend type NotFound { hint: String }\ntype NotFound @glError { id: ID! }');
      expect(g.types.containsKey('NotFound'), isFalse);
      expect(g.errors['NotFound']!.type.fields.map((f) => f.name.token), containsAll(['id', 'hint']));
    });

    test('an extension without a base type is an error when it carries @glError', () {
      final g = _parse('extend type NotFound @glError { id: ID! }');
      expect(g.types.containsKey('NotFound'), isFalse);
      expect(g.errors['NotFound']!.type.fields.map((f) => f.name.token), ['id']);
    });

    test('@glError added by an extension makes the type an error', () {
      final g = _parse('type Missing { id: ID! }\nextend type Missing @glError');
      expect(g.errors.containsKey('Missing'), isTrue);
      expect(g.types.containsKey('Missing'), isFalse);
    });
  });

  group('placement of the directive', () {
    test('on an input is rejected', () {
      _fails('input Bad @glError { id: ID }', '@glError');
    });

    test('on an interface is rejected', () {
      _fails('interface Bad @glError { id: ID }', '@glError');
    });

    test('on an enum is rejected', () {
      _fails('enum Bad @glError { A B }', '@glError');
    });

    test('on a field is rejected', () {
      _fails('type Holder { id: ID @glError }', '@glError');
    });
  });

  group('fields of an error', () {
    test('object types are rejected', () {
      _fails('type Bad @glError { article: Article }', 'Bad.article');
    });

    test('unknown types are rejected', () {
      _fails('type Bad @glError { who: Nobody }', 'Nobody');
    });

    test('default values are rejected', () {
      _fails('type Bad @glError { retries: Int = 3 }', 'Bad.retries');
    });

    test('arguments on an error field are rejected', () {
      _fails('type Bad @glError { id(format: String): ID }', 'Bad.id');
    });

    for (final name in ['message', 'path', 'extensions', 'cause', 'stack', 'stackTrace', 'stack_trace', 'args', 'name', 'localizedMessage', 'hashCode']) {
      test("'$name' clashes with the base exception", () {
        _fails('type Bad @glError { $name: String }', "'$name'");
      });
    }
  });

  group('arguments', () {
    test('an empty field is rejected', () {
      _fails('type Bad @glError(field: "") { id: ID }', 'field');
    });

    test('a path with an empty segment is rejected', () {
      _fails('type Bad @glError(field: "extensions..code") { id: ID }', 'field');
    });

    test('an empty value is rejected', () {
      _fails('type Bad @glError(value: "") { id: ID }', 'value');
    });

    test('a status outside 100..599 is rejected', () {
      _fails('type Bad @glError(status: 99) { id: ID }', 'status');
      _fails('type Bad @glError(status: 600) { id: ID }', 'status');
    });

    test('an unknown argument is rejected', () {
      _fails('type Bad @glError(code: "X") { id: ID }', 'code');
    });
  });

  group('identifiers', () {
    test('naming convention and reserved words apply to error types and fields', () {
      final g = GLParser(naming: NamingConvention.python, reservedWords: pythonReservedWords)
        ..parse('type article_gone @glError { class: String firstName: String }');
      final type = g.errors['article_gone']!.type;
      expect(type.codeName, 'ArticleGone');
      expect(type.fields.map((f) => f.codeName).toSet(), {'class_', 'first_name'});
    });
  });
}
