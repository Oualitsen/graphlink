import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — type definitions', () {
    test('simple type', () {
      final grammar = parse('type User { name: String }');
      expect(grammar.types.containsKey('User'), true);
      expect(grammar.types['User']!.fields.length, 1);
    });

    test('extended type', () {
      final grammar = parse('extend type User { name: String }');
      expect(grammar.types['User']!.extension, true);
    });

    test('type without documentation has null documentation', () {
      final grammar = parse('type User { name: String }');
      expect(grammar.types['User']!.documentation, null);
    });

    test('type with documentation', () {
      final grammar = parse('"Represents a user" type User { name: String }');
      expect(grammar.types['User']!.documentation, '"Represents a user"');
    });

    test('type with block string documentation', () {
      final grammar = parse('"""Represents a user""" type User { name: String }');
      expect(grammar.types['User']!.documentation, '"""Represents a user"""');
    });

    test('type with directive', () {
      final grammar = parse('type User @deprecated { name: String }');
      expect(grammar.types['User']!.getDirectives().first.token, 'deprecated');
    });

    test('type implements single interface', () {
      final grammar = parse('type Admin implements User { name: String }');
      final names = grammar.types['Admin']!.interfaceNames.map((t) => t.token).toSet();
      expect(names.contains('User'), true);
    });

    test('type implements multiple interfaces', () {
      final grammar = parse('type Admin implements User & Node & Auditable { name: String }');
      final names = grammar.types['Admin']!.interfaceNames.map((t) => t.token).toSet();
      expect(names, {'User', 'Node', 'Auditable'});
    });

    test('non-nullable field', () {
      final grammar = parse('type User { name: String! }');
      final field = grammar.types['User']!.fields.first;
      expect(field.type.nullable, false);
    });

    test('nullable field', () {
      final grammar = parse('type User { name: String }');
      final field = grammar.types['User']!.fields.first;
      expect(field.type.nullable, true);
    });

    test('list field', () {
      final grammar = parse('type User { tags: [String!]! }');
      final field = grammar.types['User']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, false);
      expect(field.type.firstType.nullable, false);
    });

    test('field with argument', () {
      final grammar = parse('type User { posts(limit: Int): [String] }');
      final field = grammar.types['User']!.getFieldByName('posts')!;
      expect(field.arguments.length, 1);
      expect(field.arguments.first.token, 'limit');
      expect(field.arguments.first.type.token, 'Int');
    });

    test('field with multiple arguments', () {
      final grammar = parse('type User { posts(limit: Int!, offset: Int = 0): [String] }');
      final field = grammar.types['User']!.getFieldByName('posts')!;
      expect(field.arguments.length, 2);
      expect(field.arguments.first.token, 'limit');
      expect(field.arguments.first.type.nullable, false);
      final offset = field.getArgumentByName('offset')!;
      expect(offset.initialValue, 0);
    });

    test('field with documentation', () {
      final grammar = parse('''
        type User {
          "The user full name"
          name: String!
        }
      ''');
      final field = grammar.types['User']!.getFieldByName('name')!;
      expect(field.documentation, '"The user full name"');
    });

    test('field without documentation has null documentation', () {
      final grammar = parse('type User { name: String }');
      expect(grammar.types['User']!.fields.first.documentation, null);
    });

    test('full type with all features', () {
      final grammar = parse('''
        """Represents an admin user"""
        type Admin implements User & Node @deprecated {
          "The admin name"
          name: String!

          roles: [String!]! @deprecated(reason: "use permissions")

          posts(limit: Int = 10, offset: Int = 0): [String]
        }
      ''');
      final type = grammar.types['Admin']!;
      expect(type.documentation, '"""Represents an admin user"""');
      expect(type.getDirectives().first.token, 'deprecated');
      expect(type.interfaceNames.map((t) => t.token).toSet(), {'User', 'Node'});
      expect(type.fields.length, 3);

      final name = type.getFieldByName('name')!;
      expect(name.documentation, '"The admin name"');
      expect(name.type.nullable, false);

      final roles = type.getFieldByName('roles')!;
      expect(roles.type.isList, true);
      expect(roles.getDirectives().first.getArgValue('reason'), '"use permissions"');

      final posts = type.getFieldByName('posts')!;
      expect(posts.arguments.length, 2);
      expect(posts.getArgumentByName('limit')!.initialValue, 10);
    });

    test('missing type name throws', () {
      expect(
        () => parse('type { name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('type User name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('type User { name: String'),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate field throws', () {
      expect(
        () => parse('type User { name: String name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('implements with missing interface name throws', () {
      expect(
        () => parse('type User implements { name: String }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
