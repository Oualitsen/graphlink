import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  // A lowerCamelCase convention used throughout — no serializer involved,
  // tests check codeName / name.token directly on the IR.
  final lowerCamel = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  group('type field normalization', () {
    test('PascalCase field → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Company { User: User }
        type User { id: ID! }
      ''');

      final field = g.types['Company']!.getFieldByName('User')!;
      expect(field.codeName, 'user');
      expect(field.name.token, 'User');
    });

    test('SCREAMING_SNAKE field → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Foo { MY_FIELD: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('MY_FIELD')!;
      expect(field.codeName, 'myField');
      expect(field.name.token, 'MY_FIELD');
    });

    test('snake_case field → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Foo { first_name: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('first_name')!;
      expect(field.codeName, 'firstName');
      expect(field.name.token, 'first_name');
    });

    test('already lowerCamelCase field is not renamed', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Foo { firstName: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('firstName')!;
      expect(field.codeName, 'firstName');
    });
  });

  group('input field normalization', () {
    test('PascalCase input field → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        input ProductFilter { IsActive: Boolean }
      ''');

      final field = g.inputs['ProductFilter']!.getFieldByName('IsActive')!;
      expect(field.codeName, 'isActive');
      expect(field.name.token, 'IsActive');
    });

    test('SCREAMING_SNAKE input field is normalized', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        input SearchQuery { FULL_TEXT: String }
      ''');

      final field = g.inputs['SearchQuery']!.getFieldByName('FULL_TEXT')!;
      expect(field.codeName, 'fullText');
      expect(field.name.token, 'FULL_TEXT');
    });
  });

  group('collision handling', () {
    test('two fields that normalize to the same name: first keeps it, second gets index', () {
      final g = GLParser(naming: lowerCamel);
      // `User` and `user` both normalize to `user`
      g.parse('''
        type Foo {
          User: String
          user: String
        }
      ''');

      final upper = g.types['Foo']!.getFieldByName('User')!;
      final lower = g.types['Foo']!.getFieldByName('user')!;
      final codeNames = {upper.codeName, lower.codeName};
      expect(codeNames, containsAll(['user', 'user2']));
    });

    test('triple collision gets sequential indices', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Foo {
          My_Field: String
          MY_FIELD: String
          myField: String
        }
      ''');

      final fields = [
        g.types['Foo']!.getFieldByName('My_Field')!,
        g.types['Foo']!.getFieldByName('MY_FIELD')!,
        g.types['Foo']!.getFieldByName('myField')!,
      ];
      final codeNames = fields.map((f) => f.codeName).toSet();
      expect(codeNames, hasLength(3));
      expect(codeNames, containsAll(['myField', 'myField2', 'myField3']));
    });
  });

  group('normalization + keyword-safe composition', () {
    test('normalized name that lands on a reserved word gets _ suffix', () {
      final g = GLParser(
        naming: lowerCamel,
        reservedWords: {'return'},
      );
      g.parse('''
        type Foo { Return: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('Return')!;
      expect(field.codeName, 'return_');
      expect(field.name.token, 'Return');
    });

    test('already-reserved raw name still gets _ suffix when not transformed', () {
      final g = GLParser(
        naming: lowerCamel,
        reservedWords: {'return'},
      );
      // `return` is already lowerCamelCase — normalization is a no-op,
      // but keyword-safe must still fire.
      g.parse('''
        type Foo { return: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('return')!;
      expect(field.codeName, 'return_');
      expect(field.name.token, 'return');
    });
  });

  group('no naming convention', () {
    test('without a NamingConvention, codeName equals wire name', () {
      final g = GLParser(); // naming == null
      g.parse('''
        type Foo { MY_FIELD: String }
      ''');

      final field = g.types['Foo']!.getFieldByName('MY_FIELD')!;
      expect(field.codeName, 'MY_FIELD');
    });
  });
}
