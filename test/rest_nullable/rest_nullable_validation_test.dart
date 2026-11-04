import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
scalar Void @glVoid
scalar Download @glDownload
enum Status { ACTIVE }
type Owner { name: String! }
type Product { id: ID! owner: Owner! }
''';

GLParser _parse(String body) => GLParser()..parse('$_types$body');

void expectError(String body, List<Pattern> messages) {
  expect(
    () => _parse(body),
    throwsA(isA<ParseException>().having((e) => e.toString(), 'message', allOf(messages.map(contains).toList()))),
  );
}

void main() {
  group('placement', () {
    test('a root field that is not a REST operation', () {
      expectError('type Query { product: Product! @glRestNullable }', ['@glRestNullable', 'REST operation', 'product']);
    });

    test('a field of an ordinary type', () {
      expectError('''
        type Wrapper { product: Product @glRestNullable }
        type Query { w: Wrapper! @glRest(path: "/w") }
      ''', ['@glRestNullable', 'REST operation', 'product']);
    });

    test('a GraphQL mutation', () {
      expectError('''
        type Query { ping: String }
        type Mutation { make: Product! @glRestNullable }
      ''', ['@glRestNullable', 'REST operation', 'make']);
    });
  });

  group('nothing to make nullable', () {
    test('text response', () {
      expectError('type Query { name: String @glRest(path: "/n", response: TEXT) @glRestNullable }', ['@glRestNullable', "'name'", 'text']);
    });

    test('download', () {
      expectError('type Query { file: Download! @glRest(path: "/f") @glRestNullable }', ['@glRestNullable', "'file'", 'binary']);
    });

    test('void', () {
      expectError('type Mutation { drop: Void @glRest(path: "/d", method: DELETE) @glRestNullable }\ntype Query { ping: String }', ['@glRestNullable', "'drop'", 'void']);
    });

    test('scalar result', () {
      expectError('type Query { count: Int! @glRest(path: "/c") @glRestNullable }', ['@glRestNullable', "'count'", 'scalar or enum']);
    });

    test('list of scalars', () {
      expectError('type Query { names: [String!]! @glRest(path: "/c") @glRestNullable }', ['@glRestNullable', "'names'", 'scalar or enum']);
    });

    test('enum result', () {
      expectError('type Query { status: Status! @glRest(path: "/s") @glRestNullable }', ['@glRestNullable', "'status'", 'scalar or enum']);
    });
  });

  group('@glTypeName', () {
    test('is rejected on a REST operation with a message about REST', () {
      expectError('type Query { product: Product! @glRest(path: "/p") @glTypeName(name: "X") }', ['@glTypeName', 'REST']);
    });

    test('also when the route comes from a prefix', () {
      expectError('''
        type Query { ping: String }
        extend type Query @glRestPrefix(path: "/p") { product: Product! @glTypeName(name: "X") }
      ''', ['@glTypeName', 'REST']);
    });
  });

  group('name collisions', () {
    const operation = 'type Query { product: Product! @glRest(path: "/p") @glRestNullable }';

    test('with a type', () {
      expectError('type ProductRest { id: ID }\n$operation', ['ProductRest', 'restNullableSuffix']);
    });

    test('with an enum', () {
      expectError('enum OwnerRest { A }\n$operation', ['OwnerRest', 'restNullableSuffix']);
    });

    test('with an input', () {
      expectError('input ProductRest { id: ID }\n$operation', ['ProductRest', 'restNullableSuffix']);
    });

    test('with a type generated for a GraphQL selection', () {
      expectError('''
        type Query { product: Product! @glRest(path: "/p") @glRestNullable  other: Product! }
        query other { other @glTypeName(name: "ProductRest") { id } }
      ''', ['ProductRest', 'restNullableSuffix']);
    });

    test('only types that would be copied are checked', () {
      expect(() => _parse('type Unrelated { id: ID }\ntype OwnerRest { id: ID }\ntype Query { name: Owner! @glRest(path: "/p") }'), returnsNormally);
    });
  });
}
