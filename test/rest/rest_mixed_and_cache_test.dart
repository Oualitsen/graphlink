import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = 'type Product { id: ID! name: String }\ninput In { name: String }\n';

GLParser _parse(String body, {GLParser? parser}) => (parser ?? GLParser())..parse('$_types$body');

GLRestOperation _op(GLParser g, String name, [GLQueryType type = GLQueryType.query]) =>
    g.restOperations[GLOperationKey(name, type)]!;

void expectError(String body, Pattern message) {
  expect(() => _parse(body),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('keeping REST out of GraphQL generation', () {
    test('auto-generated queries skip REST fields', () {
      final g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true)
        ..parse('''
          ${_types}type Query { gql: Product  rest: Product @glRest(path: "/r") }
        ''');
      expect(g.queries.keys.map((k) => k.fieldName), ['gql']);
      expect(g.restOperations.keys.map((k) => k.fieldName), ['rest']);
    });

    test('a GraphQL document cannot select a REST field', () {
      expectError('type Query { rest: Product @glRest(path: "/r") }\nquery q { rest { id } }', 'rest');
    });

    test('a field of the same name on the other operation type is not affected', () {
      final g = _parse('''
        type Query { item: Product @glRest(path: "/i") }
        type Mutation { item(i: In): Product }
        mutation m { item(i: {name: "x"}) { id } }
      ''');
      expect(g.queries.keys.map((k) => k.fieldName), contains('m'));
    });
  });

  group('cache directives', () {
    test('ttl, tags and staleIfOffline are exposed', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") @glCache(ttl: "30s", tags: ["products"], staleIfOffline: true) }');
      final op = _op(g, 'p');
      expect(op.cacheTtl, 30);
      expect(op.cacheTags, ['products']);
      expect(op.staleIfOffline, isTrue);
    });

    test('no directive means no cache', () {
      final g = _parse('type Query { p: Product @glRest(path: "/p") }');
      expect(_op(g, 'p').cacheTtl, 0);
      expect(_op(g, 'p').cacheTags, isEmpty);
    });

    test('only GET queries can be cached', () {
      expectError('type Query { p: Product @glRest(path: "/p", method: POST) @glCache(ttl: 10) }', 'GET');
      expectError('type Mutation { p: Product @glRest(path: "/p") @glCache(ttl: 10) }', 'mutation');
      expectError('type Mutation { p: Product @glRest(path: "/p") @glNoCache }', 'mutation');
    });

    test('invalidation belongs to mutations', () {
      expectError('type Query { p: Product @glRest(path: "/p") @glCacheInvalidate(all: true) }', 'mutation');
    });

    test('@glCache and @glNoCache conflict', () {
      expectError('type Query { p: Product @glRest(path: "/p") @glCache(ttl: 10) @glNoCache }', 'glNoCache');
    });

    test('a REST mutation exposes what it invalidates', () {
      final g = _parse('''
        type Query { a: Product @glRest(path: "/a") @glCache(ttl: 10, tags: ["t"]) }
        type Mutation {
          tagged: Product @glRest(path: "/t") @glCacheInvalidate(tags: ["t"])
          everything: Product @glRest(path: "/e") @glCacheInvalidate(all: true)
        }''');
      expect(_op(g, 'tagged', GLQueryType.mutation).invalidateTags, ['t']);
      expect(_op(g, 'tagged', GLQueryType.mutation).invalidatesAll, isFalse);
      expect(_op(g, 'everything', GLQueryType.mutation).invalidatesAll, isTrue);
    });
  });

  group('one tag space for both transports', () {
    test('a REST mutation can invalidate a tag declared on a GraphQL query', () {
      final g = _parse('''
        type Query { gql: Product @glCache(ttl: 10, tags: ["shared"]) }
        type Mutation { m: Product @glRest(path: "/m") @glCacheInvalidate(tags: ["shared"]) }''');
      expect(_op(g, 'm', GLQueryType.mutation).invalidateTags, ['shared']);
    });

    test('a GraphQL mutation can invalidate a tag declared on a REST query', () {
      final g = _parse('''
        type Query { r: Product @glRest(path: "/r") @glCache(ttl: 10, tags: ["shared"]) }
        type Mutation { m: Product @glCacheInvalidate(tags: ["shared"]) }''');
      expect(g.restOperations.length, 1);
    });

    test('an undeclared tag is still an error', () {
      expectError('type Mutation { m: Product @glRest(path: "/m") @glCacheInvalidate(tags: ["nobody"]) }', 'nobody');
    });
  });

  group('configuration', () {
    const schema = '''
      type Query {
        plain: Product @glRest(path: "/a")
        off: Product @glRest(path: "/b") @glNoCache
        post: Product @glRest(path: "/c", method: POST)
        explicit: Product @glRest(path: "/d") @glCache(ttl: 5)
      }
      type Mutation { m: Product @glRest(path: "/m") }''';

    test('defaultCacheTTL applies to GET queries that did not decide', () {
      final g = _parse(schema, parser: GLParser(defaultCacheTTL: 120));
      expect(_op(g, 'plain').cacheTtl, 120);
      expect(_op(g, 'off').cacheTtl, 0);
      expect(_op(g, 'post').cacheTtl, 0);
      expect(_op(g, 'explicit').cacheTtl, 5);
      expect(_op(g, 'm', GLQueryType.mutation).cacheTtl, 0);
    });

    test('disableCache removes every cache directive', () {
      final g = _parse('''
        type Query { a: Product @glRest(path: "/a") @glCache(ttl: 5, tags: ["t"]) }
        type Mutation { m: Product @glRest(path: "/m") @glCacheInvalidate(tags: ["t"]) }''',
          parser: GLParser(disableCache: true));
      expect(_op(g, 'a').cacheTtl, 0);
      expect(_op(g, 'm', GLQueryType.mutation).invalidateTags, isEmpty);
    });
  });
}
