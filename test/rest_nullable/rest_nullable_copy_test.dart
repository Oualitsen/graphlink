import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';

const _types = '''
enum Status { ACTIVE ARCHIVED }
type Owner { name: String! status: Status! }
type Product {
  id: ID!
  name: String!
  tags: [String!]!
  owner: Owner!
  related: [Product!]!
  matrix: [[Int!]!]!
  maybeOwners: [Owner]!
}
''';

GLParser _parse(String schema, {String suffix = 'Rest'}) =>
    GLParser(restNullableSuffix: suffix)..parse('$_types\n$schema');

GLField _field(GLParser g, String type, String name) =>
    g.projectedTypes[type]!.fields.firstWhere((f) => f.name.token == name);

GLRestOperation _operation(GLParser g, String name) => g.restOperations.values.firstWhere((o) => o.name == name);

String _shape(GLType type) {
  final inner = type is GLListType ? '[${_shape(type.type)}]' : type.tokenInfo.token;
  return type.nullable ? inner : '$inner!';
}

void main() {
  group('the copy', () {
    final g = _parse('''
      type Query {
        product: Product! @glRest(path: "/p") @glRestNullable
        plain: Product! @glRest(path: "/q")
      }
    ''');

    test('exists next to the original, both projected', () {
      expect(g.projectedTypes.keys, containsAll(['Product', 'ProductRest', 'Owner', 'OwnerRest']));
    });

    test('is not added to the schema types', () {
      expect(g.types.containsKey('ProductRest'), isFalse);
      expect(g.types.containsKey('OwnerRest'), isFalse);
    });

    test('has every field nullable and the same field names', () {
      final copy = g.projectedTypes['ProductRest']!;
      expect(copy.fields.map((f) => f.name.token).toSet(), g.projectedTypes['Product']!.fields.map((f) => f.name.token).toSet());
      expect(copy.fields.every((f) => f.type.nullable), isTrue);
    });

    test('renames references to copied types and keeps scalars and enums', () {
      expect(_shape(_field(g, 'ProductRest', 'owner').type), 'OwnerRest');
      expect(_shape(_field(g, 'ProductRest', 'name').type), 'String');
      expect(_shape(_field(g, 'OwnerRest', 'status').type), 'Status');
    });

    test('relaxes only the outer level of a list: elements follow the schema', () {
      expect(_shape(_field(g, 'ProductRest', 'tags').type), '[String!]');
      expect(_shape(_field(g, 'ProductRest', 'related').type), '[ProductRest!]');
      expect(_shape(_field(g, 'ProductRest', 'matrix').type), '[[Int!]!]');
      expect(_shape(_field(g, 'ProductRest', 'maybeOwners').type), '[OwnerRest]');
    });

    test('leaves the original types exactly as they are without the directive', () {
      final without = _parse('''
        type Query {
          product: Product! @glRest(path: "/p")
          plain: Product! @glRest(path: "/q")
        }
      ''');
      for (final type in ['Product', 'Owner']) {
        for (final field in without.projectedTypes[type]!.fields) {
          expect(_shape(_field(g, type, field.name.token).type), _shape(field.type), reason: '$type.${field.name.token}');
        }
      }
    });
  });

  group('the operation', () {
    test('returns the copy and keeps its own nullability', () {
      final g = _parse('''
        type Query {
          one: Product! @glRest(path: "/1") @glRestNullable
          maybe: Product @glRest(path: "/2") @glRestNullable
          many: [Product!]! @glRest(path: "/3") @glRestNullable
          manyOrNone: [Product] @glRest(path: "/4") @glRestNullable
        }
      ''');
      expect(_shape(_operation(g, 'one').field.type), 'ProductRest!');
      expect(_shape(_operation(g, 'maybe').field.type), 'ProductRest');
      expect(_shape(_operation(g, 'many').field.type), '[ProductRest!]!');
      expect(_shape(_operation(g, 'manyOrNone').field.type), '[ProductRest]');
    });

    test('keeps path, method, response and empty-body rules', () {
      final g = _parse('''
        type Query {
          maybe: Product @glRest(path: "/m", responsePath: "data") @glRestNullable
          one: Product! @glRest(path: "/o") @glRestNullable
        }
      ''');
      expect(_operation(g, 'maybe').path, '/m');
      expect(_operation(g, 'maybe').responsePathSegments, ['data']);
      expect(_operation(g, 'maybe').allowsEmptyBody, isTrue);
      expect(_operation(g, 'one').allowsEmptyBody, isFalse);
    });

    test('works on an operation declared in an extension block with a prefix', () {
      final g = _parse('''
        type Query { ping: String }
        extend type Query @glRestPrefix(path: "/api") {
          product: Product! @glRest(path: "/p") @glRestNullable
          plain: Product! @glRest(path: "/q")
        }
      ''');
      expect(_shape(_operation(g, 'product').field.type), 'ProductRest!');
      expect(_operation(g, 'product').path, '/api/p');
      expect(_shape(_operation(g, 'plain').field.type), 'Product!');
    });

    test('without the directive nothing changes', () {
      final g = _parse('type Query { plain: Product! @glRest(path: "/q") }');
      expect(_shape(_operation(g, 'plain').field.type), 'Product!');
      expect(g.projectedTypes.keys.where((k) => k.endsWith('Rest')), isEmpty);
    });

    test('operations that are not opted in keep the original type', () {
      final g = _parse('''
        type Query {
          lenient: Product! @glRest(path: "/a") @glRestNullable
          strict: Product! @glRest(path: "/b")
        }
      ''');
      expect(_shape(_operation(g, 'lenient').field.type), 'ProductRest!');
      expect(_shape(_operation(g, 'strict').field.type), 'Product!');
    });
  });

  group('naming', () {
    test('the opted-in operation is named like any other operation', () {
      final g = GLParser(naming: NamingConvention.python)
        ..parse('''
          $_types
          type Query {
            lenientProduct: Product! @glRest(path: "/a") @glRestNullable
            strictProduct: Product! @glRest(path: "/b")
          }
        ''');
      expect(_operation(g, 'strictProduct').field.codeName, 'strict_product');
      expect(_operation(g, 'lenientProduct').field.codeName, 'lenient_product');
    });

    test('the type that owns the operation holds the very same field', () {
      final g = _parse('type Query { p: Product! @glRest(path: "/p") @glRestNullable }');
      final owned = g.types['Query']!.fields.firstWhere((f) => f.name.token == 'p');
      expect(identical(owned, _operation(g, 'p').field), isTrue);
    });
  });

  group('shared and recursive types', () {
    test('a self reference points at the copy itself', () {
      final g = _parse('type Query { p: Product! @glRest(path: "/p") @glRestNullable }');
      expect(_field(g, 'ProductRest', 'related').type.firstType.tokenInfo.token, 'ProductRest');
    });

    test('two opted-in operations share one copy per type', () {
      final g = _parse('''
        type Query {
          a: Product! @glRest(path: "/a") @glRestNullable
          b: [Owner!]! @glRest(path: "/b") @glRestNullable
        }
      ''');
      expect(g.projectedTypes.keys.where((k) => k == 'OwnerRest'), hasLength(1));
      expect(_shape(_field(g, 'ProductRest', 'owner').type), 'OwnerRest');
      expect(_shape(_operation(g, 'b').field.type), '[OwnerRest!]!');
    });

    test('only what the opted-in operation reaches is copied', () {
      final g = _parse('''
        type Query {
          owner: Owner! @glRest(path: "/o") @glRestNullable
          product: Product! @glRest(path: "/p")
        }
      ''');
      expect(g.projectedTypes.keys, contains('OwnerRest'));
      expect(g.projectedTypes.keys, isNot(contains('ProductRest')));
    });
  });

  group('suffix', () {
    test('comes from the parser option', () {
      final g = _parse('type Query { p: Product! @glRest(path: "/p") @glRestNullable }', suffix: 'Raw');
      expect(g.projectedTypes.keys, containsAll(['ProductRaw', 'OwnerRaw']));
      expect(g.projectedTypes.keys, isNot(contains('ProductRest')));
      expect(_shape(_field(g, 'ProductRaw', 'owner').type), 'OwnerRaw');
    });
  });

  group('GraphQL operations', () {
    test('keep returning the original types', () {
      final g = _parse('''
        type Query {
          product: Product! @glRest(path: "/p") @glRestNullable
          graphqlProduct: Product!
        }
        query graphqlProduct { graphqlProduct { id name } }
      ''');
      expect(_shape(g.queries.values.single.elements.first.returnType), 'Product!');
    });
  });
}
