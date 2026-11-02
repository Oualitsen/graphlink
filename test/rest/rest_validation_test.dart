import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
scalar Upload @glUpload
type Product { id: ID! name: String }
input Filter { tag: String limit: Int @glRestParam(name: "max") }
input Tenant { id: ID @glRestHeader(name: "X-Tenant") trace: String }
input Nested { inner: Filter }
input Matrix { rows: [[Int!]!] }
input Clash { limit: Int }
''';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

void expectError(String body, Pattern message) {
  expect(() => _parse(body),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('routes', () {
    test('two operations on the same method and path are rejected', () {
      expectError('type Query { a: Product @glRest(path: "/x")  b: Product @glRest(path: "/x") }', "'a'");
    });

    test('placeholder names do not make routes different', () {
      expectError('''type Query {
        a(id: ID!): Product @glRest(path: "/x/{id}")
        b(other: ID!): Product @glRest(path: "/x/{other}")
      }''', 'same route');
    });

    test('a different method on the same path is fine', () {
      final g = _parse('''
        type Query { a: Product @glRest(path: "/x") }
        type Mutation { b: Product @glRest(path: "/x") }''');
      expect(g.restOperations.length, 2);
    });
  });

  group('capture errors', () {
    test('@glCaptureErrors on a REST operation is rejected', () {
      expectError('type Query { a: Product @glRest(path: "/x") @glCaptureErrors }', 'glCaptureErrors');
    });
  });

  group('spread fields', () {
    test('query spread keeps field names and honours field-level names', () {
      final g = _parse('type Query { a(filter: Filter @glRestParam): Product @glRest(path: "/x") }');
      final filter = g.restOperations.values.single.argument('filter')!;
      expect(filter.spreadFields, {'tag': 'tag', 'limit': 'max'});
    });

    test('header groups honour field-level names', () {
      final g = _parse('type Query { a(t: Tenant @glRestHeader): Product @glRest(path: "/x") }');
      expect(g.restOperations.values.single.argument('t')!.spreadFields, {'id': 'X-Tenant', 'trace': 'trace'});
    });

    test('FLAT objects have no spread fields', () {
      final g = _parse('type Query { a(filter: Filter @glRestParam(encoding: FLAT)): Product @glRest(path: "/x") }');
      expect(g.restOperations.values.single.argument('filter')!.spreadFields, isEmpty);
    });

    test('a nested object cannot be a header', () {
      expectError('type Query { a(n: Nested @glRestHeader): Product @glRest(path: "/x") }', 'inner');
    });

    test('a spread key clashing with another query parameter', () {
      expectError('type Query { a(f: Clash @glRestParam, limit: Int @glRestParam): Product @glRest(path: "/x") }', 'limit');
    });

    test('two spread objects sharing a key', () {
      expectError('type Query { a(f: Clash @glRestParam, g: Clash @glRestParam): Product @glRest(path: "/x") }', 'limit');
    });

    test('headers are compared case-insensitively', () {
      expectError('''type Query { a(h: String @glRestHeader(name: "X-A"), i: String @glRestHeader(name: "x-a")): Product @glRest(path: "/x") }''', 'x-a');
    });
  });

  group('list depth', () {
    test('a matrix is allowed', () {
      final g = _parse('type Query { a(m: [[Int!]!] @glRestParam): Product @glRest(path: "/x") }');
      expect(g.restOperations.length, 1);
    });

    test('three levels are rejected and the message names the escape', () {
      expectError('type Query { a(m: [[[Int!]!]!] @glRestParam): Product @glRest(path: "/x") }', 'encoding: JSON');
    });

    test('three levels are fine with JSON encoding', () {
      final g = _parse('type Query { a(m: [[[Int!]!]!] @glRestParam(encoding: JSON)): Product @glRest(path: "/x") }');
      expect(g.restOperations.length, 1);
    });

    test('depth adds up through nested input objects', () {
      expectError('type Query { a(m: [Matrix!] @glRestParam(encoding: FLAT)): Product @glRest(path: "/x") }', 'encoding: JSON');
    });

    test('forms and multipart have the same cap', () {
      expectError('type Mutation { a(m: [[[Int!]!]!] @glRestField): Product @glRest(path: "/x") }', 'encoding: JSON');
      expectError('type Mutation { a(m: [[[Int!]!]!] @glRestPart): Product @glRest(path: "/x") }', 'encoding: JSON');
    });

    test('a header cannot be a list of lists', () {
      expectError('type Query { a(h: [[String!]!] @glRestHeader(name: "X")): Product @glRest(path: "/x") }', 'header');
    });

    test('a JSON body has no cap', () {
      final g = _parse('type Mutation { a(m: [Matrix!]! @glRestBody): Product @glRest(path: "/x") }');
      expect(g.restOperations.values.single.bodyKind, RestBodyKind.json);
    });
  });

  group('uploads', () {
    test('a matrix of uploads is rejected', () {
      expectError('type Mutation { a(f: [[Upload!]!]! @glRestPart): Product @glRest(path: "/x") }', 'Upload');
    });

    test('uploads nested in an input object stay rejected', () {
      expectError('input WithFile { file: Upload }\ntype Mutation { a(i: WithFile! @glRestPart): Product @glRest(path: "/x") }', 'input');
    });
  });
}
