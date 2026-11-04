import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
scalar Void @glVoid
scalar Download @glDownload
enum Status { ACTIVE }
type Owner { name: String! }
type Product { id: ID! owner: Owner! }
''';

GLParser _parse(String body, {bool restNullable = false}) =>
    GLParser(restNullable: restNullable)..parse('$_types$body');

GLRestOperation _operation(GLParser g, String name) => g.restOperations.values.firstWhere((o) => o.name == name);

String _resultOf(GLParser g, String name) => _operation(g, name).field.type.firstType.token;

void main() {
  group('restNullable option', () {
    const schema = '''
      type Query {
        product: Product! @glRest(path: "/p")
        owner: Owner! @glRest(path: "/o")
      }
      type Mutation { rename(id: ID! @glRestField): Product! @glRest(path: "/r", method: POST) }
    ''';

    test('every REST operation returns the nullable copy', () {
      final g = _parse(schema, restNullable: true);
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(_resultOf(g, 'owner'), 'OwnerRest');
      expect(_resultOf(g, 'rename'), 'ProductRest');
      expect(g.projectedTypes.keys, containsAll(['Product', 'ProductRest', 'Owner', 'OwnerRest']));
    });

    test('GraphQL operations keep the original type', () {
      final g = _parse('''
        type Query {
          product: Product! @glRest(path: "/p")
          graphqlProduct: Product!
        }
      ''', restNullable: true);
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(g.types['Query']!.fields.firstWhere((f) => f.name.token == 'graphqlProduct').type.firstType.token, 'Product');
    });

    test('off by default: nothing is copied', () {
      final g = _parse(schema);
      expect(_resultOf(g, 'product'), 'Product');
      expect(g.projectedTypes.keys, isNot(contains('ProductRest')));
    });

    test('an operation with the directive already is not tagged twice', () {
      final g = _parse('type Query { product: Product! @glRest(path: "/p") @glRestNullable }', restNullable: true);
      expect(_resultOf(g, 'product'), 'ProductRest');
    });
  });

  group('restNullable option skips what cannot be copied', () {
    final g = _parse('''
      type Query {
        product: Product! @glRest(path: "/p")
        text: String! @glRest(path: "/t", response: TEXT)
        file: Download! @glRest(path: "/f")
        status: Status! @glRest(path: "/s")
        count: Int! @glRest(path: "/c")
      }
      type Mutation { clear: Void! @glRest(path: "/x", method: POST) }
    ''', restNullable: true);

    test('the other operations are still converted', () {
      expect(_resultOf(g, 'product'), 'ProductRest');
    });

    test('text, binary, void, enum and scalar results are left alone without an error', () {
      expect(_resultOf(g, 'text'), 'String');
      expect(_resultOf(g, 'file'), 'Download');
      expect(_resultOf(g, 'status'), 'Status');
      expect(_resultOf(g, 'count'), 'Int');
      expect(_resultOf(g, 'clear'), 'Void');
    });

    test('an explicit directive on one of them is still an error', () {
      expect(
        () => _parse('type Query { text: String! @glRest(path: "/t", response: TEXT) @glRestNullable }', restNullable: true),
        throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains('text response'))),
      );
    });
  });

  group('@glRestNullable on a root type', () {
    test('converts the REST operations of that type only', () {
      final g = _parse('''
        type Query @glRestNullable {
          product: Product! @glRest(path: "/p")
          owner: Owner! @glRest(path: "/o")
        }
        type Mutation { rename(id: ID! @glRestField): Product! @glRest(path: "/r", method: POST) }
      ''');
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(_resultOf(g, 'owner'), 'OwnerRest');
      expect(_resultOf(g, 'rename'), 'Product');
    });

    test('works on Mutation too', () {
      final g = _parse('''
        type Query { product: Product! @glRest(path: "/p") }
        type Mutation @glRestNullable { rename(id: ID! @glRestField): Product! @glRest(path: "/r", method: POST) }
      ''');
      expect(_resultOf(g, 'product'), 'Product');
      expect(_resultOf(g, 'rename'), 'ProductRest');
    });

    test('GraphQL fields of the root type are ignored', () {
      final g = _parse('''
        type Query @glRestNullable {
          product: Product! @glRest(path: "/p")
          graphqlProduct: Product!
        }
      ''');
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(g.types['Query']!.fields.firstWhere((f) => f.name.token == 'graphqlProduct').type.firstType.token, 'Product');
    });
  });

  group('@glRestNullable on a root type: blocks, prefixes, skips', () {
    test('an extension block converts only its own fields', () {
      final g = _parse('''
        type Query { product: Product! @glRest(path: "/p") }
        extend type Query @glRestNullable { owner: Owner! @glRest(path: "/o") }
      ''');
      expect(_resultOf(g, 'product'), 'Product');
      expect(_resultOf(g, 'owner'), 'OwnerRest');
    });

    test('the base block does not leak into an extension', () {
      final g = _parse('''
        type Query @glRestNullable { product: Product! @glRest(path: "/p") }
        extend type Query { owner: Owner! @glRest(path: "/o") }
      ''');
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(_resultOf(g, 'owner'), 'Owner');
    });

    test('operations routed by @glRestPrefix are converted', () {
      final g = _parse('''
        type Query @glRestNullable @glRestPrefix(path: "/products") { product: Product! }
      ''');
      expect(_resultOf(g, 'product'), 'ProductRest');
    });

    test('operations that cannot be copied are skipped without an error', () {
      final g = _parse('''
        type Query @glRestNullable {
          product: Product! @glRest(path: "/p")
          text: String! @glRest(path: "/t", response: TEXT)
          status: Status! @glRest(path: "/s")
        }
      ''');
      expect(_resultOf(g, 'product'), 'ProductRest');
      expect(_resultOf(g, 'text'), 'String');
      expect(_resultOf(g, 'status'), 'Status');
    });

    test('the directive on the type and on a field is harmless', () {
      final g = _parse('type Query @glRestNullable { product: Product! @glRest(path: "/p") @glRestNullable }');
      expect(_resultOf(g, 'product'), 'ProductRest');
    });
  });
}
