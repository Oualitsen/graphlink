import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — input definitions', () {
    test('simple input', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String }', validate: false);
      expect(parser.inputs.containsKey('CreateUser'), true);
      expect(parser.inputs['CreateUser']!.fields.length, 1);
    });

    test('extended input', () {
      final parser = GLParser();
      parser.parse('extend input CreateUser { name: String }', validate: false);
      expect(parser.inputs['CreateUser']!.extension, true);
    });

    test('input without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String }', validate: false);
      expect(parser.inputs['CreateUser']!.documentation, null);
    });

    test('input with documentation', () {
      final parser = GLParser();
      parser.parse('"Creates a user" input CreateUser { name: String }',
          validate: false);
      expect(parser.inputs['CreateUser']!.documentation, '"Creates a user"');
    });

    test('input with block string documentation', () {
      final parser = GLParser();
      parser.parse('"""Creates a user""" input CreateUser { name: String }',
          validate: false);
      expect(
          parser.inputs['CreateUser']!.documentation, '"""Creates a user"""');
    });

    test('input with directive', () {
      final parser = GLParser();
      parser.parse('input CreateUser @deprecated { name: String }',
          validate: false);
      expect(parser.inputs['CreateUser']!.getDirectives().first.token,
          '@deprecated');
    });

    test('non-nullable field', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String! }', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.name.token, 'name');
      expect(field.type.token, 'String');
      expect(field.type.nullable, false);
    });

    test('nullable field', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String }', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.type.nullable, true);
    });

    test('list field', () {
      final parser = GLParser();
      parser.parse('input CreateUser { tags: [String] }', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, true);
    });

    test('non-nullable list of non-nullable field', () {
      final parser = GLParser();
      parser.parse('input CreateUser { tags: [String!]! }', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.type.isList, true);
      expect(field.type.nullable, false);
      expect(field.type.firstType.nullable, false);
    });

    test('field with default value', () {
      final parser = GLParser();
      parser.parse('input CreateUser { age: Int = 0 }', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, 0);
    });

    test('field with string default value', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String = "anonymous" }',
          validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, '"anonymous"');
    });

    test('field with boolean default value', () {
      final parser = GLParser();
      parser.parse('input CreateUser { active: Boolean = true }',
          validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.initialValue, true);
    });

    test('field with directive', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String @deprecated }',
          validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.getDirectives().first.token, '@deprecated');
    });

    test('field without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('input CreateUser { name: String }', validate: false);
      expect(parser.inputs['CreateUser']!.fields.first.documentation, null);
    });

    test('field with documentation', () {
      final parser = GLParser();
      parser.parse('''
        input CreateUser {
          "The user name"
          name: String
        }
      ''', validate: false);
      final field = parser.inputs['CreateUser']!.fields.first;
      expect(field.documentation, '"The user name"');
    });

    test('multiple fields', () {
      final parser = GLParser();
      parser.parse('''
        input CreateUser {
          name: String!
          age: Int
          active: Boolean = true
          tags: [String!]!
        }
      ''', validate: false);
      final fields = parser.inputs['CreateUser']!.fields;
      expect(fields.length, 4);
    });

    test('full input with documentation and documented fields', () {
      final parser = GLParser();
      parser.parse('''
        """Input for creating a new user"""
        input CreateUser @deprecated {
          "The user full name"
          name: String!

          age: Int = 18

          """List of tags"""
          tags: [String!]! @deprecated(reason: "use roles")
        }
      ''', validate: false);
      final input = parser.inputs['CreateUser']!;
      expect(input.documentation, '"""Input for creating a new user"""');
      expect(input.getDirectives().first.token, '@deprecated');
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
        () => GLParser().parse('input { name: String }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => GLParser()
            .parse('input CreateUser name: String }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => GLParser()
            .parse('input CreateUser { name: String', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing field type throws', () {
      expect(
        () => GLParser().parse('input CreateUser { name: }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing colon throws', () {
      expect(
        () => GLParser()
            .parse('input CreateUser { name String }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate field throws', () {
      expect(
        () => GLParser().parse('input CreateUser { name: String name: String }',
            validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('input field with argument syntax throws', () {
      // input fields cannot have arguments — only type/interface fields can
      expect(
        () => GLParser().parse(
            'input CreateUser { name(lang: String): String }',
            validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
