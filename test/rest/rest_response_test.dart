import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
scalar Upload @glUpload
scalar Download @glDownload
scalar Void @glVoid
type Product { id: ID! name: String }
input In { name: String }
''';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

GLRestOperation _query(String declaration) =>
    _parse('type Query { $declaration }').restOperations.values.single;

GLRestOperation _mutation(String declaration) =>
    _parse('type Mutation { $declaration }').restOperations.values.single;

void expectError(String body, Pattern message) {
  expect(() => _parse(body),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('response kind', () {
    test('JSON is the default', () {
      final op = _query('p: Product @glRest(path: "/p")');
      expect(op.responseKind, RestResponseKind.json);
      expect(op.accept, 'application/json');
    });

    test('a @glDownload return is binary and accepts anything', () {
      final op = _query('file(id: ID!): Download! @glRest(path: "/f/{id}")');
      expect(op.responseKind, RestResponseKind.binary);
      expect(op.accept, '*/*');
    });

    test('a download can come from a mutation', () {
      final op = _mutation('export: Download @glRest(path: "/export")');
      expect(op.responseKind, RestResponseKind.binary);
    });

    test('response: TEXT on a String return', () {
      final op = _query('t: String @glRest(path: "/t", response: TEXT)');
      expect(op.responseKind, RestResponseKind.text);
      expect(op.accept, 'text/plain');
    });

    test('TEXT needs a plain String return', () {
      expectError('type Query { t: Product @glRest(path: "/t", response: TEXT) }', 'TEXT');
      expectError('type Query { t: [String!] @glRest(path: "/t", response: TEXT) }', 'TEXT');
      expectError('type Query { t: Int @glRest(path: "/t", response: TEXT) }', 'TEXT');
    });

    test('unknown response kind', () {
      expectError('type Query { t: String @glRest(path: "/t", response: XML) }', 'XML');
    });

    test('a download is always binary and BINARY needs a download', () {
      expectError('type Query { f: Download @glRest(path: "/f", response: JSON) }', 'download');
      expectError('type Query { p: Product @glRest(path: "/p", response: BINARY) }', 'BINARY');
    });
  });

  group('response path', () {
    test('is split into segments', () {
      final op = _query('p: [Product!]! @glRest(path: "/p", responsePath: "data.items")');
      expect(op.responsePathSegments, ['data', 'items']);
    });

    test('is empty by default', () {
      expect(_query('p: Product @glRest(path: "/p")').responsePathSegments, isEmpty);
    });

    test('malformed paths are rejected', () {
      for (final bad in ['a..b', '.a', 'a.', '']) {
        expectError('type Query { p: Product @glRest(path: "/p", responsePath: "$bad") }', 'responsePath');
      }
    });

    test('only JSON responses have a path', () {
      expectError('type Query { t: String @glRest(path: "/t", response: TEXT, responsePath: "a") }', 'responsePath');
      expectError('type Query { f: Download @glRest(path: "/f", responsePath: "a") }', 'responsePath');
    });
  });

  group('empty bodies', () {
    test('a nullable return allows an empty body, a non-null one does not', () {
      expect(_query('p: Product @glRest(path: "/p")').allowsEmptyBody, isTrue);
      expect(_query('p: Product! @glRest(path: "/p")').allowsEmptyBody, isFalse);
    });
  });

  group('content types', () {
    test('defaults follow the body kind', () {
      expect(_mutation('m(i: In! @glRestBody): Product @glRest(path: "/p")').contentType, 'application/json');
      expect(_mutation('m(s: String @glRestField): Product @glRest(path: "/p")').contentType,
          'application/x-www-form-urlencoded');
      expect(_mutation('m(u: Upload! @glRestPart): Product @glRest(path: "/p")').contentType, 'multipart/form-data');
    });

    test('a raw body and a request without a body leave it to the runtime', () {
      expect(_mutation('m(u: Upload! @glRestBody): Product @glRest(path: "/p")').contentType, isNull);
      expect(_query('p: Product @glRest(path: "/p")').contentType, isNull);
    });

    test('contentType overrides a JSON or raw body', () {
      expect(_mutation('m(i: In! @glRestBody): Product @glRest(path: "/p", contentType: "application/vnd.api+json")').contentType,
          'application/vnd.api+json');
      expect(_mutation('m(u: Upload! @glRestBody): Product @glRest(path: "/p", contentType: "image/png")').contentType,
          'image/png');
    });

    test('contentType is meaningless without a body or for forms', () {
      expectError('type Query { p: Product @glRest(path: "/p", contentType: "text/plain") }', 'contentType');
      expectError('type Mutation { m(s: String @glRestField): Product @glRest(path: "/p", contentType: "text/plain") }', 'contentType');
      expectError('type Mutation { m(u: Upload! @glRestPart): Product @glRest(path: "/p", contentType: "text/plain") }', 'contentType');
    });

    test('accept can be overridden', () {
      expect(_query('p: Product @glRest(path: "/p", accept: "application/vnd.api+json")').accept, 'application/vnd.api+json');
    });
  });

  group('download scalar placement', () {
    test('@glDownload is only allowed on scalars', () {
      expectError('type Plain @glDownload { id: ID }\ntype Query { p: Plain @glRest(path: "/p") }', 'glDownload');
    });

    test('a list of downloads is rejected', () {
      expectError('type Query { f: [Download!] @glRest(path: "/f") }', 'Download');
    });

    test('a download is not an argument or a field of a type', () {
      expectError('type Mutation { m(d: Download @glRestParam): Product @glRest(path: "/p") }', 'Download');
      expectError('type Doc { file: Download }\ntype Query { d: Doc @glRest(path: "/d") }', 'Download');
    });

    test('a download needs a REST operation', () {
      expectError('type Query { f: Download }', 'REST');
    });

    test('a download cannot be cached', () {
      expectError('type Query { f: Download @glRest(path: "/f") @glCache(ttl: 10) }', 'glCache');
    });

    test('returning an upload is rejected', () {
      expectError('type Query { u: Upload @glRest(path: "/u") }', 'Upload');
    });
  });

  group('void', () {
    test('a Void return ignores the body and accepts anything', () {
      final op = _mutation('remove(id: ID!): Void @glRest(path: "/p/{id}", method: DELETE)');
      expect(op.responseKind, RestResponseKind.none);
      expect(op.allowsEmptyBody, isTrue);
      expect(op.accept, '*/*');
    });

    test('nullability of Void does not matter', () {
      expect(_mutation('remove(id: ID!): Void! @glRest(path: "/p/{id}", method: DELETE)').responseKind, RestResponseKind.none);
    });

    test('a POST can return Void too', () {
      expect(_mutation('notify: Void @glRest(path: "/n")').responseKind, RestResponseKind.none);
    });

    test('a void response has no kind, path or cache', () {
      expectError('type Query { v: Void @glRest(path: "/v", response: JSON) }', 'Void');
      expectError('type Query { v: Void @glRest(path: "/v", responsePath: "a") }', 'responsePath');
      expectError('type Query { v: Void @glRest(path: "/v") @glCache(ttl: 10) }', 'glCache');
    });

    test('placement is the same as a download', () {
      expectError('type Query { v: [Void!] @glRest(path: "/v") }', 'Void');
      expectError('type Mutation { m(v: Void @glRestParam): Product @glRest(path: "/p") }', 'Void');
      expectError('type Doc { v: Void }\ntype Query { d: Doc @glRest(path: "/d") }', 'Void');
      expectError('type Query { v: Void }', 'REST');
      expectError('type Plain @glVoid { id: ID }\ntype Query { p: Plain @glRest(path: "/p") }', 'glVoid');
    });
  });

  group('nullable returns', () {
    test('lists and downloads follow the same rule', () {
      expect(_query('p: [Product!] @glRest(path: "/p")').allowsEmptyBody, isTrue);
      expect(_query('p: [Product!]! @glRest(path: "/p")').allowsEmptyBody, isFalse);
      expect(_query('f: Download @glRest(path: "/f")').allowsEmptyBody, isTrue);
      expect(_query('f: Download! @glRest(path: "/f")').allowsEmptyBody, isFalse);
    });
  });

  group('nullable bodies', () {
    test('a nullable JSON body is optional, a required one is not', () {
      expect(_mutation('m(i: In @glRestBody): Product @glRest(path: "/p")').bodyIsOptional, isTrue);
      expect(_mutation('m(i: In! @glRestBody): Product @glRest(path: "/p")').bodyIsOptional, isFalse);
    });

    test('a nullable raw body is optional', () {
      expect(_mutation('m(u: Upload @glRestBody): Product @glRest(path: "/p")').bodyIsOptional, isTrue);
      expect(_mutation('m(u: Upload! @glRestBody): Product @glRest(path: "/p")').bodyIsOptional, isFalse);
    });

    test('a form is optional only when every field is', () {
      expect(_mutation('m(a: String @glRestField, b: Int @glRestField): Product @glRest(path: "/p")').bodyIsOptional, isTrue);
      expect(_mutation('m(a: String @glRestField, b: Int! @glRestField): Product @glRest(path: "/p")').bodyIsOptional, isFalse);
    });

    test('a default value makes a field optional', () {
      expect(_mutation('m(a: String! = "x" @glRestField): Product @glRest(path: "/p")').bodyIsOptional, isTrue);
    });

    test('multipart follows the same rule', () {
      expect(_mutation('m(a: String @glRestPart): Product @glRest(path: "/p")').bodyIsOptional, isTrue);
      expect(_mutation('m(a: String @glRestPart, f: Upload! @glRestPart): Product @glRest(path: "/p")').bodyIsOptional, isFalse);
    });

    test('no body means nothing is optional', () {
      expect(_query('p: Product @glRest(path: "/p")').bodyIsOptional, isFalse);
    });
  });

  group('GraphQL operations', () {
    for (final scalar in ['Void', 'Download']) {
      test('a GraphQL field returning $scalar fires an exception', () {
        expectError('type Query { f: $scalar }', 'GraphQL operation');
        expectError('type Mutation { f: $scalar }', 'GraphQL operation');
      });

      test('a GraphQL document variable of type $scalar fires an exception', () {
        expectError('type Query { gql: Product }\nquery q(\$v: $scalar) { gql { id } }', 'GraphQL operation');
      });

      test('a GraphQL document selecting a REST field returning $scalar fires an exception', () {
        expectError('type Query { f: $scalar @glRest(path: "/f") }\nquery q { f }', 'REST operation');
      });
    }
  });
}
