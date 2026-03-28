import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — interface definitions', () {
    test('simple interface', () {
      final grammar = parse('interface Node { id: ID! }');
      expect(grammar.interfaces.containsKey('Node'), true);
      expect(grammar.interfaces['Node']!.fields.length, 1);
    });

    test('extended interface', () {
      final grammar = parse('extend interface Node { id: ID! }');
      expect(grammar.interfaces['Node']!.extension, true);
    });

    test('interface without documentation has null documentation', () {
      final grammar = parse('interface Node { id: ID! }');
      expect(grammar.interfaces['Node']!.documentation, null);
    });

    test('interface with documentation', () {
      final grammar = parse('"A node interface" interface Node { id: ID! }');
      expect(grammar.interfaces['Node']!.documentation, '"A node interface"');
    });

    test('interface with block string documentation', () {
      final grammar = parse('"""A node interface""" interface Node { id: ID! }');
      expect(grammar.interfaces['Node']!.documentation, '"""A node interface"""');
    });

    test('interface with directive', () {
      final grammar = parse('interface Node @deprecated { id: ID! }');
      expect(grammar.interfaces['Node']!.getDirectives().first.token, 'deprecated');
    });

    test('interface implements another interface', () {
      final grammar = parse('interface Admin implements Node { id: ID! }');
      final names = grammar.interfaces['Admin']!.interfaceNames.map((t) => t.token).toSet();
      expect(names.contains('Node'), true);
    });

    test('interface implements multiple interfaces', () {
      final grammar = parse('interface Admin implements Node & Auditable { id: ID! }');
      final names = grammar.interfaces['Admin']!.interfaceNames.map((t) => t.token).toSet();
      expect(names, {'Node', 'Auditable'});
    });

    test('non-nullable field', () {
      final grammar = parse('interface Node { id: ID! }');
      final field = grammar.interfaces['Node']!.fields.first;
      expect(field.type.nullable, false);
    });

    test('list field', () {
      final grammar = parse('interface Feed { items: [String!]! }');
      final field = grammar.interfaces['Feed']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, false);
    });

    test('field with argument', () {
      final grammar = parse('interface Feed { items(limit: Int): [String] }');
      final field = grammar.interfaces['Feed']!.getFieldByName('items')!;
      expect(field.arguments.length, 1);
      expect(field.arguments.first.token, 'limit');
    });

    test('field with documentation', () {
      final grammar = parse('''
        interface Node {
          "Unique identifier"
          id: ID!
        }
      ''');
      final field = grammar.interfaces['Node']!.getFieldByName('id')!;
      expect(field.documentation, '"Unique identifier"');
    });

    test('field without documentation has null documentation', () {
      final grammar = parse('interface Node { id: ID! }');
      expect(grammar.interfaces['Node']!.fields.first.documentation, null);
    });

    test('interface field cannot have default value', () {
      // canBeInitialized: false — = value is not consumed as initialValue,
      // the parser will hit an unexpected token
      expect(
        () => parse('interface Node { id: ID! = "x" }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('full interface with all features', () {
      final grammar = parse('''
        """Base interface for all nodes"""
        interface Admin implements Node & Auditable @deprecated {
          "Unique identifier"
          id: ID!

          roles: [String!]! @deprecated(reason: "use permissions")

          posts(limit: Int = 10): [String]
        }
      ''');
      final iface = grammar.interfaces['Admin']!;
      expect(iface.documentation, '"""Base interface for all nodes"""');
      expect(iface.getDirectives().first.token, 'deprecated');
      expect(iface.interfaceNames.map((t) => t.token).toSet(), {'Node', 'Auditable'});
      expect(iface.fields.length, 3);

      final id = iface.getFieldByName('id')!;
      expect(id.documentation, '"Unique identifier"');
      expect(id.type.nullable, false);

      final roles = iface.getFieldByName('roles')!;
      expect(roles.getDirectives().first.getArgValue('reason'), '"use permissions"');

      final posts = iface.getFieldByName('posts')!;
      expect(posts.getArgumentByName('limit')!.initialValue, 10);
    });

    test('missing interface name throws', () {
      expect(
        () => parse('interface { id: ID! }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('interface Node id: ID! }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('interface Node { id: ID!'),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate field throws', () {
      expect(
        () => parse('interface Node { id: ID! id: ID! }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
