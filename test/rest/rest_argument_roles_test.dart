import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
scalar Upload @glUpload
type Product { id: ID! name: String }
enum Kind { A B }
input ProductInput { name: String! kind: Kind }
input Filter { tag: String limit: Int }
''';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

GLRestOperation _query(String declaration) {
  final g = _parse('type Query { $declaration }');
  return g.restOperations.values.single;
}

GLRestOperation _mutation(String declaration) {
  final g = _parse('type Mutation { $declaration }');
  return g.restOperations.values.single;
}

void expectError(String schema, Pattern message) {
  expect(() => _parse(schema),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains(message))));
}

void main() {
  group('path variables', () {
    test('an argument named like a placeholder is a path variable', () {
      final op = _query('product(id: ID!): Product @glRest(path: "/products/{id}")');
      final id = op.argument('id')!;
      expect(id.role, RestArgRole.path);
      expect(id.wireName, 'id');
    });

    test('the pass injects @glRestPath on the argument', () {
      final op = _query('product(id: ID!): Product @glRest(path: "/products/{id}")');
      final directive = op.argument('id')!.argument.getDirectiveByName(glRestPath);
      expect(directive, isNotNull);
      expect(directive!.getArgValueAsString(glRestNameArg), 'id');
    });

    test('@glRestPath(name:) binds an argument to a differently named placeholder', () {
      final op = _query('''product(shop: ID! @glRestPath(name: "shopId"), id: ID!): Product
        @glRest(path: "/shops/{shopId}/products/{id}")''');
      expect(op.argument('shop')!.role, RestArgRole.path);
      expect(op.argument('shop')!.wireName, 'shopId');
      expect(op.argument('id')!.wireName, 'id');
    });

    test('enum path variables are accepted', () {
      final op = _query('byKind(kind: Kind!): Product @glRest(path: "/kinds/{kind}")');
      expect(op.argument('kind')!.role, RestArgRole.path);
    });

    test('unbound placeholder', () {
      expectError('type Query { p: Product @glRest(path: "/products/{id}") }', "'id'");
    });

    test('explicit @glRestPath matching no placeholder', () {
      expectError('type Query { p(id: ID! @glRestPath(name: "other")): Product @glRest(path: "/products/{id}") }', 'other');
    });

    test('nullable path variable', () {
      expectError('type Query { p(id: ID): Product @glRest(path: "/products/{id}") }', 'non-null');
    });

    test('list or input path variable', () {
      expectError('type Query { p(id: [ID!]!): Product @glRest(path: "/products/{id}") }', 'scalar');
      expectError('type Query { p(id: Filter!): Product @glRest(path: "/products/{id}") }', 'scalar');
    });
  });

  group('query parameters', () {
    test('@glRestParam keeps the argument name by default', () {
      final op = _query('list(limit: Int @glRestParam): [Product!]! @glRest(path: "/p")');
      final limit = op.argument('limit')!;
      expect(limit.role, RestArgRole.query);
      expect(limit.wireName, 'limit');
      expect(limit.encoding, isNull);
    });

    test('@glRestParam(name:) renames the key', () {
      final op = _query('list(fields: String @glRestParam(name: "select")): [Product!]! @glRest(path: "/p")');
      expect(op.argument('fields')!.wireName, 'select');
    });

    test('an input object is spread by default', () {
      final op = _query('list(filter: Filter @glRestParam): [Product!]! @glRest(path: "/p")');
      expect(op.argument('filter')!.encoding, RestEncoding.spread);
    });

    test('FLAT and JSON can be chosen', () {
      final flat = _query('list(filter: Filter @glRestParam(encoding: FLAT)): [Product!]! @glRest(path: "/p")');
      expect(flat.argument('filter')!.encoding, RestEncoding.flat);
      final json = _query('list(filter: Filter @glRestParam(encoding: JSON)): [Product!]! @glRest(path: "/p")');
      expect(json.argument('filter')!.encoding, RestEncoding.json);
    });

    test('a list of input objects defaults to FLAT', () {
      final op = _query('list(filters: [Filter!] @glRestParam): [Product!]! @glRest(path: "/p")');
      expect(op.argument('filters')!.encoding, RestEncoding.flat);
    });

    test('SPREAD on a list is rejected', () {
      expectError('type Query { list(filters: [Filter!] @glRestParam(encoding: SPREAD)): [Product!]! @glRest(path: "/p") }', 'SPREAD');
    });

    test('encoding on a scalar is rejected', () {
      expectError('type Query { list(limit: Int @glRestParam(encoding: FLAT)): [Product!]! @glRest(path: "/p") }', 'encoding');
    });

    test('unknown encoding', () {
      expectError('type Query { list(filter: Filter @glRestParam(encoding: NESTED)): [Product!]! @glRest(path: "/p") }', 'NESTED');
    });
  });

  group('headers', () {
    test('a scalar header needs a name', () {
      final op = _query('p(tenant: ID! @glRestHeader(name: "X-Tenant")): Product @glRest(path: "/p")');
      expect(op.argument('tenant')!.role, RestArgRole.header);
      expect(op.argument('tenant')!.wireName, 'X-Tenant');
      expectError('type Query { p(tenant: ID! @glRestHeader): Product @glRest(path: "/p") }', 'name');
    });

    test('an input object is spread into headers without a name', () {
      final op = _query('p(auth: Filter @glRestHeader): Product @glRest(path: "/p")');
      final auth = op.argument('auth')!;
      expect(auth.role, RestArgRole.header);
      expect(auth.wireName, isNull);
      expect(auth.encoding, RestEncoding.spread);
    });

    test('a list of input objects cannot be a header group', () {
      expectError('type Query { p(auth: [Filter!] @glRestHeader): Product @glRest(path: "/p") }', 'header');
    });
  });

  group('bodies', () {
    test('no body role means no body', () {
      expect(_query('p(id: ID!): Product @glRest(path: "/p/{id}")').bodyKind, RestBodyKind.none);
    });

    test('@glRestBody on an input is a JSON body', () {
      final op = _mutation('create(input: ProductInput! @glRestBody): Product @glRest(path: "/p")');
      expect(op.bodyKind, RestBodyKind.json);
      expect(op.argument('input')!.role, RestArgRole.body);
    });

    test('a list of inputs is a valid JSON body', () {
      final op = _mutation('bulk(items: [ProductInput!]! @glRestBody): [Product!]! @glRest(path: "/p")');
      expect(op.bodyKind, RestBodyKind.json);
    });

    test('@glRestBody on an Upload is a raw body', () {
      final op = _mutation('avatar(id: ID!, file: Upload! @glRestBody): Product @glRest(path: "/p/{id}", method: PUT)');
      expect(op.bodyKind, RestBodyKind.raw);
    });

    test('@glRestField makes a form with FLAT objects by default', () {
      final op = _mutation('signup(name: String! @glRestField, input: ProductInput @glRestField): Product @glRest(path: "/s")');
      expect(op.bodyKind, RestBodyKind.form);
      expect(op.argument('name')!.wireName, 'name');
      expect(op.argument('input')!.encoding, RestEncoding.flat);
    });

    test('@glRestPart makes a multipart body', () {
      final op = _mutation('''up(meta: ProductInput! @glRestPart, photo: Upload! @glRestPart, note: String @glRestPart(name: "comment")): Product
        @glRest(path: "/p")''');
      expect(op.bodyKind, RestBodyKind.multipart);
      expect(op.argument('meta')!.encoding, RestEncoding.flat);
      expect(op.argument('photo')!.encoding, isNull);
      expect(op.argument('note')!.wireName, 'comment');
    });

    test('a list of uploads is a valid multipart part', () {
      final op = _mutation('up(files: [Upload!]! @glRestPart): Product @glRest(path: "/p")');
      expect(op.bodyKind, RestBodyKind.multipart);
    });

    test('a form can still carry path, query and header arguments', () {
      final op = _mutation('''up(id: ID!, v: Int @glRestParam, t: ID @glRestHeader(name: "X-T"), name: String @glRestField): Product
        @glRest(path: "/p/{id}")''');
      expect(op.bodyKind, RestBodyKind.form);
      expect(op.arguments.map((a) => a.role),
          [RestArgRole.path, RestArgRole.query, RestArgRole.header, RestArgRole.field]);
    });
  });

  group('errors', () {
    test('an argument without a role names the fix', () {
      expectError('type Query { list(limit: Int): [Product!]! @glRest(path: "/p") }', '@glRestParam');
    });

    test('two roles on one argument', () {
      expectError('type Query { list(limit: Int @glRestParam @glRestHeader(name: "X")): [Product!]! @glRest(path: "/p") }', 'limit');
    });

    test('body roles on GET and DELETE', () {
      expectError('type Query { p(i: ProductInput @glRestBody): Product @glRest(path: "/p") }', 'GET');
      expectError('type Mutation { p(i: ProductInput @glRestField): Product @glRest(path: "/p", method: DELETE) }', 'DELETE');
    });

    test('more than one JSON body', () {
      expectError('type Mutation { p(a: ProductInput @glRestBody, b: ProductInput @glRestBody): Product @glRest(path: "/p") }', 'one');
    });

    test('mixed body kinds', () {
      expectError('type Mutation { p(a: ProductInput @glRestBody, b: String @glRestField): Product @glRest(path: "/p") }', 'mix');
      expectError('type Mutation { p(a: String @glRestField, b: Upload @glRestPart): Product @glRest(path: "/p") }', 'mix');
    });

    test('an upload must be a part or a raw body', () {
      expectError('type Mutation { p(f: Upload @glRestParam): Product @glRest(path: "/p") }', 'Upload');
      expectError('type Mutation { p(f: Upload @glRestField): Product @glRest(path: "/p") }', 'Upload');
    });

    test('a list of uploads cannot be a raw body', () {
      expectError('type Mutation { p(f: [Upload!]! @glRestBody): Product @glRest(path: "/p") }', 'raw');
    });
  });
}
