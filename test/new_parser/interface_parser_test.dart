import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — interface definitions', () {
    test('simple interface', () {
      final parser = GLParser();
      parser.parse('interface Node { id: ID! }', validate: false);
      expect(parser.interfaces.containsKey('Node'), true);
      expect(parser.interfaces['Node']!.fields.length, 1);
    });

    test('extended interface', () {
      final parser = GLParser();
      parser.parse('extend interface Node { id: ID! }', validate: false);
      expect(parser.interfaces['Node']!.extension, true);
    });

    test('interface without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('interface Node { id: ID! }', validate: false);
      expect(parser.interfaces['Node']!.documentation, null);
    });

    test('interface with documentation', () {
      final parser = GLParser();
      parser.parse('"A node interface" interface Node { id: ID! }',
          validate: false);
      expect(parser.interfaces['Node']!.documentation, '"A node interface"');
    });

    test('interface with block string documentation', () {
      final parser = GLParser();
      parser.parse('"""A node interface""" interface Node { id: ID! }',
          validate: false);
      expect(
          parser.interfaces['Node']!.documentation, '"""A node interface"""');
    });

    test('interface with directive', () {
      final parser = GLParser();
      parser.parse('interface Node @deprecated { id: ID! }', validate: false);
      expect(parser.interfaces['Node']!.getDirectives().first.token,
          '@deprecated');
    });

    test('interface implements another interface', () {
      final parser = GLParser();
      parser.parse('interface Admin implements Node { id: ID! }',
          validate: false);
      final names = parser.interfaces['Admin']!.interfaceNames
          .map((t) => t.token)
          .toSet();
      expect(names.contains('Node'), true);
    });

    test('interface implements multiple interfaces', () {
      final parser = GLParser();
      parser.parse('interface Admin implements Node & Auditable { id: ID! }',
          validate: false);
      final names = parser.interfaces['Admin']!.interfaceNames
          .map((t) => t.token)
          .toSet();
      expect(names, {'Node', 'Auditable'});
    });

    test('non-nullable field', () {
      final parser = GLParser();
      parser.parse('interface Node { id: ID! }', validate: false);
      final field = parser.interfaces['Node']!.fields.first;
      expect(field.type.nullable, false);
    });

    test('list field', () {
      final parser = GLParser();
      parser.parse('interface Feed { items: [String!]! }', validate: false);
      final field = parser.interfaces['Feed']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, false);
    });

    test('field with argument', () {
      final parser = GLParser();
      parser.parse('interface Feed { items(limit: Int): [String] }',
          validate: false);
      final field = parser.interfaces['Feed']!.getFieldByName('items')!;
      expect(field.arguments.length, 1);
      expect(field.arguments.first.token, 'limit');
    });

    test('field with documentation', () {
      final parser = GLParser();
      parser.parse('''
        interface Node {
          "Unique identifier"
          id: ID!
        }
      ''', validate: false);
      final field = parser.interfaces['Node']!.getFieldByName('id')!;
      expect(field.documentation, '"Unique identifier"');
    });

    test('field without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('interface Node { id: ID! }', validate: false);
      expect(parser.interfaces['Node']!.fields.first.documentation, null);
    });

    test('interface field cannot have default value', () {
      // canBeInitialized: false — = value is not consumed as initialValue,
      // the parser will hit an unexpected token
      expect(
        () => GLParser()
            .parse('interface Node { id: ID! = "x" }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('full interface with all features', () {
      final parser = GLParser();
      parser.parse('''
        """Base interface for all nodes"""
        interface Admin implements Node & Auditable @deprecated {
          "Unique identifier"
          id: ID!

          roles: [String!]! @deprecated(reason: "use permissions")

          posts(limit: Int = 10): [String]
        }
      ''', validate: false);
      final iface = parser.interfaces['Admin']!;
      expect(iface.documentation, '"""Base interface for all nodes"""');
      expect(iface.getDirectives().first.token, '@deprecated');
      expect(iface.interfaceNames.map((t) => t.token).toSet(),
          {'Node', 'Auditable'});
      expect(iface.fields.length, 3);

      final id = iface.getFieldByName('id')!;
      expect(id.documentation, '"Unique identifier"');
      expect(id.type.nullable, false);

      final roles = iface.getFieldByName('roles')!;
      expect(roles.getDirectives().first.getArgValue('reason'),
          '"use permissions"');

      final posts = iface.getFieldByName('posts')!;
      expect(posts.getArgumentByName('limit')!.initialValue, 10);
    });

    test('missing interface name throws', () {
      expect(
        () => GLParser().parse('interface { id: ID! }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => GLParser().parse('interface Node id: ID! }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => GLParser().parse('interface Node { id: ID!', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate field throws', () {
      expect(
        () => GLParser()
            .parse('interface Node { id: ID! id: ID! }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
