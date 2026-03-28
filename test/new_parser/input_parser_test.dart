import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — input definitions', () {
    test('simple input', () {
      final grammar = parse('input CreateUser { name: String }');
      expect(grammar.inputs.containsKey('CreateUser'), true);
      expect(grammar.inputs['CreateUser']!.fields.length, 1);
    });

    test('extended input', () {
      final grammar = parse('extend input CreateUser { name: String }');
      expect(grammar.inputs['CreateUser']!.extension, true);
    });

    test('input without documentation has null documentation', () {
      final grammar = parse('input CreateUser { name: String }');
      expect(grammar.inputs['CreateUser']!.documentation, null);
    });

    test('input with documentation', () {
      final grammar = parse('"Creates a user" input CreateUser { name: String }');
      expect(grammar.inputs['CreateUser']!.documentation, '"Creates a user"');
    });

    test('input with block string documentation', () {
      final grammar = parse('"""Creates a user""" input CreateUser { name: String }');
      expect(grammar.inputs['CreateUser']!.documentation, '"""Creates a user"""');
    });

    test('input with directive', () {
      final grammar = parse('input CreateUser @deprecated { name: String }');
      expect(grammar.inputs['CreateUser']!.getDirectives().first.token, 'deprecated');
    });

    test('non-nullable field', () {
      final grammar = parse('input CreateUser { name: String! }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.name.token, 'name');
      expect(field.type.token, 'String');
      expect(field.type.nullable, false);
    });

    test('nullable field', () {
      final grammar = parse('input CreateUser { name: String }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.type.nullable, true);
    });

    test('list field', () {
      final grammar = parse('input CreateUser { tags: [String] }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, true);
    });

    test('non-nullable list of non-nullable field', () {
      final grammar = parse('input CreateUser { tags: [String!]! }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, false);
      expect(field.type.firstType.nullable, false);
    });

    test('field with default value', () {
      final grammar = parse('input CreateUser { age: Int = 0 }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, 0);
    });

    test('field with string default value', () {
      final grammar = parse('input CreateUser { name: String = "anonymous" }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, '"anonymous"');
    });

    test('field with boolean default value', () {
      final grammar = parse('input CreateUser { active: Boolean = true }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, true);
    });

    test('field with directive', () {
      final grammar = parse('input CreateUser { name: String @deprecated }');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.getDirectives().first.token, 'deprecated');
    });

    test('field without documentation has null documentation', () {
      final grammar = parse('input CreateUser { name: String }');
      expect(grammar.inputs['CreateUser']!.fields.first.documentation, null);
    });

    test('field with documentation', () {
      final grammar = parse('''
        input CreateUser {
          "The user name"
          name: String
        }
      ''');
      final field = grammar.inputs['CreateUser']!.fields.first;
      expect(field.documentation, '"The user name"');
    });

    test('multiple fields', () {
      final grammar = parse('''
        input CreateUser {
          name: String!
          age: Int
          active: Boolean = true
          tags: [String!]!
        }
      ''');
      final fields = grammar.inputs['CreateUser']!.fields;
      expect(fields.length, 4);
    });

    test('full input with documentation and documented fields', () {
      final grammar = parse('''
        """Input for creating a new user"""
        input CreateUser @deprecated {
          "The user full name"
          name: String!

          age: Int = 18

          """List of tags"""
          tags: [String!]! @deprecated(reason: "use roles")
        }
      ''');
      final input = grammar.inputs['CreateUser']!;
      expect(input.documentation, '"""Input for creating a new user"""');
      expect(input.getDirectives().first.token, 'deprecated');
      expect(input.fields.length, 3);

      final name = input.fields.firstWhere((f) => f.name.token == 'name');
      expect(name.documentation, '"The user full name"');
      expect(name.type.nullable, false);

      final age = input.fields.firstWhere((f) => f.name.token == 'age');
      expect(age.initialValue, 18);

      final tags = input.fields.firstWhere((f) => f.name.token == 'tags');
      expect(tags.documentation, '"""List of tags"""');
      expect(tags.type.isList, true);
      expect(tags.getDirectives().first.getArgValue('reason'), '"use roles"');
    });

    test('missing input name throws', () {
      expect(
        () => parse('input { name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('input CreateUser name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('input CreateUser { name: String'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing field type throws', () {
      expect(
        () => parse('input CreateUser { name: }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing colon throws', () {
      expect(
        () => parse('input CreateUser { name String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate field throws', () {
      expect(
        () => parse('input CreateUser { name: String name: String }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('input field with argument syntax throws', () {
      // input fields cannot have arguments — only type/interface fields can
      expect(
        () => parse('input CreateUser { name(lang: String): String }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
