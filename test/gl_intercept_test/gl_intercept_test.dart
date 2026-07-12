import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

void main() {
  test('field with no @glIntercept is not intercepted', () {
    const schema = '''
    type Query {
      articles: [Article]
    }
    type Article {
      id: ID!
    }
    ''';
    final g = GLParser();
    g.parse(schema);

    final field = g.types['Query']!.getFieldByName('articles')!;
    expect(g.isIntercepted(field, GLQueryType.query), isFalse);
    expect(g.usesInterceptor, isFalse);
  });

  test('field-level @glIntercept(tag: "auth") resolves that tag', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
    }
    type Article {
      id: ID!
    }
    ''';
    final g = GLParser();
    g.parse(schema);

    final field = g.types['Query']!.getFieldByName('getArticle')!;
    expect(g.isIntercepted(field, GLQueryType.query), isTrue);
    expect(g.interceptTag(field, GLQueryType.query), equals('auth'));
    expect(g.usesInterceptor, isTrue);
    expect(g.distinctInterceptTags, equals(['auth']));
  });

  test('bare @glIntercept (no tag) is intercepted with a null tag', () {
    const schema = '''
    type Query {
      adminStats: Stats @glIntercept
    }
    type Stats {
      count: Int!
    }
    ''';
    final g = GLParser();
    g.parse(schema);

    final field = g.types['Query']!.getFieldByName('adminStats')!;
    expect(g.isIntercepted(field, GLQueryType.query), isTrue);
    expect(g.interceptTag(field, GLQueryType.query), isNull);
    expect(g.distinctInterceptTags, isEmpty,
        reason: 'bare usages contribute no tag to the distinct tag list');
  });

  test(
      'object-level @glIntercept on an extend block only applies to fields '
      'declared in that block, not the whole merged type', () {
    const schema = '''
    type Mutation {
      login(input: String!): String
    }

    extend type Mutation @glIntercept(tag: "auth") {
      createArticle(input: String!): String
      deleteArticle(id: ID!): Boolean
    }
    ''';
    final g = GLParser();
    g.parse(schema);

    final login = g.types['Mutation']!.getFieldByName('login')!;
    final createArticle = g.types['Mutation']!.getFieldByName('createArticle')!;
    final deleteArticle = g.types['Mutation']!.getFieldByName('deleteArticle')!;

    expect(g.isIntercepted(login, GLQueryType.mutation), isFalse,
        reason: 'login is declared in the plain (unannotated) block');
    expect(g.isIntercepted(createArticle, GLQueryType.mutation), isTrue);
    expect(g.interceptTag(createArticle, GLQueryType.mutation), equals('auth'));
    expect(g.isIntercepted(deleteArticle, GLQueryType.mutation), isTrue);
    expect(g.interceptTag(deleteArticle, GLQueryType.mutation), equals('auth'));
  });

  test('most-specific-wins: a field-level tag overrides its block-level tag',
      () {
    const schema = '''
    type Mutation {
      login(input: String!): String
    }

    extend type Mutation @glIntercept(tag: "auth") {
      createArticle(input: String!): String @glIntercept(tag: "admin")
      deleteArticle(id: ID!): Boolean
    }
    ''';
    final g = GLParser();
    g.parse(schema);

    final createArticle = g.types['Mutation']!.getFieldByName('createArticle')!;
    final deleteArticle = g.types['Mutation']!.getFieldByName('deleteArticle')!;

    // exactly one runBefore call per resolver: the more specific field-level
    // tag wins outright, it does not stack with the block-level tag.
    expect(g.interceptTag(createArticle, GLQueryType.mutation), equals('admin'));
    expect(g.interceptTag(deleteArticle, GLQueryType.mutation), equals('auth'));
  });

  test('distinctInterceptTags is stable-ordered and deduplicated', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
      adminStats: Stats @glIntercept(tag: "admin")
    }

    extend type Mutation @glIntercept(tag: "auth") {
      createArticle(input: String!): String
    }

    type Article { id: ID! }
    type Stats { count: Int! }
    ''';
    final g = GLParser();
    g.parse(schema);

    expect(g.distinctInterceptTags, equals(['auth', 'admin']));
  });

  test('tag must be a non-blank string', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "   ")
    }
    type Article { id: ID! }
    ''';
    final g = GLParser();
    expect(() => g.parse(schema), throwsA(isA<ParseException>()));
  });

  test(
      'two distinct tags that sanitize to the same GlInterceptTag enum '
      'member raise a validation error', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "read-x")
      getOther(id: ID!): Article @glIntercept(tag: "read_x")
    }
    type Article { id: ID! }
    ''';
    final g = GLParser(naming: NamingConvention.typescript);
    expect(
      () => g.parse(schema),
      throwsA(isA<ParseException>().having(
        (e) => e.message,
        'message',
        contains('ReadX'),
      )),
    );
  });

  test('distinct tags that do not collide pass validation under a naming convention', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
      adminStats: Stats @glIntercept(tag: "admin")
    }
    type Article { id: ID! }
    type Stats { count: Int! }
    ''';
    final g = GLParser(naming: NamingConvention.java);
    g.parse(schema);

    expect(g.interceptTagEnumMembers, equals({'auth': 'AUTH', 'admin': 'ADMIN'}));
  });

  test('GlInterceptorTag enum is registered with one member per distinct tag',
      () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
      adminStats: Stats @glIntercept(tag: "admin")
    }

    extend type Mutation @glIntercept(tag: "auth") {
      createArticle(input: String!): String
    }

    type Article { id: ID! }
    type Stats { count: Int! }
    type Mutation { login(input: String!): String }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    final enumDef = g.enums['GlInterceptorTag'];
    expect(enumDef, isNotNull);
    expect(enumDef!.values.map((v) => v.token).toList(),
        equals(['auth', 'admin']));
  });

  test('no GlInterceptorTag enum is registered when no tag is declared', () {
    const schema = '''
    type Query {
      articles: [Article]
      adminStats: Stats @glIntercept
    }
    type Article { id: ID! }
    type Stats { count: Int! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    expect(g.enums.containsKey('GlInterceptorTag'), isFalse,
        reason:
            'bare @glIntercept usages contribute no tag, so there is nothing to enumerate');
  });

  test('no GlInterceptorTag enum is registered when @glIntercept is unused',
      () {
    const schema = '''
    type Query {
      articles: [Article]
    }
    type Article { id: ID! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    expect(g.enums.containsKey('GlInterceptorTag'), isFalse);
  });

  test(
      'no GlInterceptorTag enum or GraphLinkInterceptor interface is registered in '
      'client mode, even when tags are used — the same schema must still '
      'generate a client target, @glIntercept is simply ignored there', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
    }
    type Article { id: ID! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.client);
    g.parse(schema);

    expect(g.enums.containsKey('GlInterceptorTag'), isFalse);
    expect(g.interfaces.containsKey('GraphLinkInterceptor'), isFalse);
    // schema-level resolution still works in client mode; it's only the
    // generated scaffolding that's server-only.
    final field = g.types['Query']!.getFieldByName('getArticle')!;
    expect(g.isIntercepted(field, GLQueryType.query), isTrue);
  });

  test('GraphLinkInterceptor interface is registered with a runBefore method '
      'including a tag argument when tags are used', () {
    const schema = '''
    type Query {
      getArticle(id: ID!): Article @glIntercept(tag: "auth")
    }
    type Article { id: ID! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    final iface = g.interfaces['GraphLinkInterceptor'];
    expect(iface, isNotNull);
    expect(iface!.fieldAsMethods, isTrue);
    expect(iface.skipJsonMethods, isTrue);

    final runBefore = iface.getFieldByName('runBefore');
    expect(runBefore, isNotNull);
    expect(runBefore!.arguments.map((a) => a.token).toList(),
        equals(['tag', 'operation', 'args']));

    final tagArg = runBefore.getArgumentByName('tag')!;
    expect(tagArg.type.token, equals('GlInterceptorTag'));
    expect(tagArg.type.nullable, isTrue);
  });

  test('GraphLinkInterceptor runBefore has no tag argument when @glIntercept is '
      'only used bare (no tags, so no enum was generated)', () {
    const schema = '''
    type Query {
      adminStats: Stats @glIntercept
    }
    type Stats { count: Int! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    expect(g.enums.containsKey('GlInterceptorTag'), isFalse);

    final iface = g.interfaces['GraphLinkInterceptor'];
    expect(iface, isNotNull);
    final runBefore = iface!.getFieldByName('runBefore')!;
    expect(runBefore.arguments.map((a) => a.token).toList(),
        equals(['operation', 'args']));
    expect(runBefore.getArgumentByName('tag'), isNull,
        reason: 'no enum was generated, so runBefore must not reference one');
  });

  test('no GraphLinkInterceptor interface is registered when @glIntercept is unused',
      () {
    const schema = '''
    type Query {
      articles: [Article]
    }
    type Article { id: ID! }
    ''';
    final g = GLParser(mode: CodeGenerationMode.server);
    g.parse(schema);

    expect(g.interfaces.containsKey('GraphLinkInterceptor'), isFalse);
  });

  test('@glIntercept on a plain field of a non-root type is rejected', () {
    const schema = '''
    type Query {
      getAuthor(id: ID!): Author
    }
    type Author {
      id: ID!
      name: String! @glIntercept
    }
    ''';
    final g = GLParser();
    expect(
      () => g.parse(schema),
      throwsA(isA<ParseException>().having(
        (e) => e.message,
        'message',
        contains('no resolver to guard'),
      )),
    );
  });

  test('@glIntercept on a non-root object block is rejected', () {
    const schema = '''
    type Query {
      getAuthor(id: ID!): Author
    }
    extend type Author @glIntercept(tag: "auth") {
      name: String!
    }
    type Author {
      id: ID!
    }
    ''';
    final g = GLParser();
    expect(
      () => g.parse(schema),
      throwsA(isA<ParseException>().having(
        (e) => e.message,
        'message',
        contains('root type'),
      )),
    );
  });

  test('@glIntercept on an input field is rejected', () {
    const schema = '''
    type Query {
      getAuthor(id: ID!): Author
    }
    type Author { id: ID! }
    input AuthorFilter {
      name: String @glIntercept
    }
    ''';
    final g = GLParser();
    expect(
      () => g.parse(schema),
      throwsA(isA<ParseException>().having(
        (e) => e.message,
        'message',
        contains('input field'),
      )),
    );
  });

  test(
      '@glIntercept is allowed on a @glSkipOnServer (batch loader) field even '
      'though it lives on a non-root type', () {
    const schema = '''
    type Query {
      getAuthor(id: ID!): Author
    }
    type Author {
      id: ID!
      articles: [Article!] @glSkipOnServer(batch: true) @glIntercept(tag: "auth")
    }
    type Article { id: ID! }
    ''';
    final g = GLParser();
    g.parse(schema);

    final field = g.types['Author']!.getFieldByName('articles')!;
    expect(field.hasDirective(glIntercept), isTrue);
  });
}
