import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:test/test.dart';

List<String> _fieldNames(GLParser g, String type) =>
    g.projectedTypes[type]!.fields.map((f) => f.name.token).toList()..sort();

void main() {
  group('registration', () {
    test('a REST return type becomes a projected type without any fragment flag', () {
      final g = GLParser()
        ..parse('''
          type Product { id: ID! name: String }
          type Query { product: Product @glRest(path: "/p") }
        ''');
      expect(_fieldNames(g, 'Product'), ['id', 'name']);
    });

    test('lists unwrap to their element type', () {
      final g = GLParser()
        ..parse('''
          type Product { id: ID! }
          type Query { products: [Product!]! @glRest(path: "/p") }
        ''');
      expect(g.projectedTypes.containsKey('Product'), isTrue);
    });

    test('types reachable through fields are registered, unreachable ones are not', () {
      final g = GLParser()
        ..parse('''
          type Owner { name: String }
          type Product { id: ID! owner: Owner }
          type Unused { id: ID }
          type Query { product: Product @glRest(path: "/p") }
        ''');
      expect(g.projectedTypes.containsKey('Owner'), isTrue);
      expect(g.projectedTypes.containsKey('Unused'), isFalse);
    });

    test('scalars, enums and void return types register nothing', () {
      final g = GLParser()
        ..parse('''
          enum Kind { A }
          type Query { name: String @glRest(path: "/n")  kind: Kind @glRest(path: "/k") }
        ''');
      final baseline = GLParser()..parse('enum Kind { A }\ntype Query { name: String }');
      expect(g.projectedTypes.keys.toSet(), baseline.projectedTypes.keys.toSet());
    });

    test('fields marked @glSkipOnClient are left out', () {
      final g = GLParser()
        ..parse('''
          type Product { id: ID! secret: String @glSkipOnClient }
          type Query { product: Product @glRest(path: "/p") }
        ''');
      expect(_fieldNames(g, 'Product'), ['id']);
    });

    test('operations that are not REST register nothing', () {
      final g = GLParser()
        ..parse('''
          type Product { id: ID! }
          type Query { product: Product }
        ''');
      expect(g.projectedTypes.containsKey('Product'), isFalse);
    });
  });

  group('cycles', () {
    test('cyclic edges are nullable even without generateAllFieldsFragments', () {
      final g = GLParser()
        ..parse('''
          type A { id: ID! b: B! }
          type B { id: ID! a: A! }
          type Query { a: A @glRest(path: "/a") }
        ''');
      expect(g.projectedTypes['A']!.fields.firstWhere((f) => f.name.token == 'b').type.nullable, isTrue);
      expect(g.projectedTypes['B']!.fields.firstWhere((f) => f.name.token == 'a').type.nullable, isTrue);
    });
  });

  group('sharing with GraphQL operations', () {
    test('a partial GraphQL selection gets its own name next to the full REST type', () {
      final g = GLParser()
        ..parse('''
          type Product { id: ID! name: String }
          type Query { gql: Product  rest: Product @glRest(path: "/r") }
          query getName { gql { name } }
        ''');
      expect(_fieldNames(g, 'Product'), ['id', 'name']);
      final partial = g.projectedTypes.values.where((t) => t.token != 'Product' && t.fields.length == 1 && t.fields.single.name.token == 'name');
      expect(partial, isNotEmpty);
    });
  });

  group('polymorphic returns', () {
    const interfaceSchema = '''
      interface Pet%DIRECTIVE% { id: ID! }
      type Dog implements Pet { id: ID! }
      type Cat implements Pet { id: ID! }
    ''';

    test('an interface and all its implementors are registered', () {
      final g = GLParser()
        ..parse('''
          ${interfaceSchema.replaceFirst('%DIRECTIVE%', ' @glRestDiscriminator(field: "kind")')}
          type Query { pet: Pet @glRest(path: "/pet") }
        ''');
      expect(g.projectedInterfaces.containsKey('Pet'), isTrue);
      expect(g.projectedTypes.keys, containsAll(['Dog', 'Cat']));
    });

    test('a union return is registered through its converted interface', () {
      final g = GLParser()
        ..parse('''
          type Dog { id: ID! }
          type Cat { id: ID! }
          union Hit @glRestDiscriminator(field: "t") = Dog | Cat
          type Query { hit: Hit @glRest(path: "/h") }
        ''');
      expect(g.projectedInterfaces.containsKey('Hit'), isTrue);
    });

    test('a REST operation reaching an interface without a discriminator is rejected', () {
      expect(
          () => GLParser().parse('''
            ${interfaceSchema.replaceFirst('%DIRECTIVE%', '')}
            type Query { pet: Pet @glRest(path: "/pet") }
          '''),
          throwsA(isA<ParseException>().having((e) => e.toString(), 'message', allOf(contains('Pet'), contains('glRestDiscriminator')))));
    });

    test('the same applies when the interface is nested in a returned type', () {
      expect(
          () => GLParser().parse('''
            ${interfaceSchema.replaceFirst('%DIRECTIVE%', '')}
            type Owner { pet: Pet }
            type Query { owner: Owner @glRest(path: "/o") }
          '''),
          throwsA(isA<ParseException>().having((e) => e.toString(), 'message', contains('Pet'))));
    });

    test('an interface used only by GraphQL operations needs no discriminator', () {
      final g = GLParser()
        ..parse('''
          ${interfaceSchema.replaceFirst('%DIRECTIVE%', '')}
          type Query { pet: Pet  other: String @glRest(path: "/o") }
        ''');
      expect(g.restDiscriminators, isEmpty);
    });
  });

  group('reachable types', () {
    test('are the return types, everything reachable through fields, and implementors of reached interfaces', () {
      final g = GLParser()
        ..parse('''
          type Owner { name: String }
          interface Pet @glRestDiscriminator(field: "kind") { id: ID! }
          type Dog implements Pet { id: ID! owner: Owner }
          type Cat implements Pet { id: ID! }
          type Product { id: ID! pet: Pet }
          type Unused { id: ID }
          type Query { product: Product @glRest(path: "/p") }
        ''');
      expect(g.restReachableTypeNames, {'Product', 'Pet', 'Dog', 'Cat', 'Owner'});
    });

    test('are empty without REST operations', () {
      final g = GLParser()..parse('type A { id: ID } type Query { a: A }');
      expect(g.restReachableTypeNames, isEmpty);
    });
  });
}
