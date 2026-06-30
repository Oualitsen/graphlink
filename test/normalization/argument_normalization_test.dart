import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  final lowerCamel = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  group('field argument normalization', () {
    test('PascalCase argument → lowerCamelCase codeName, bareName unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { user(UserId: ID!): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('user')!.arguments.first;
      expect(arg.codeName, 'userId');
      expect(arg.bareName, 'UserId');
    });

    test('SCREAMING_SNAKE argument → lowerCamelCase codeName, bareName unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { search(FULL_TEXT: String): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('search')!.arguments.first;
      expect(arg.codeName, 'fullText');
      expect(arg.bareName, 'FULL_TEXT');
    });

    test('snake_case argument → lowerCamelCase codeName, bareName unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { filter(max_count: Int): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('filter')!.arguments.first;
      expect(arg.codeName, 'maxCount');
      expect(arg.bareName, 'max_count');
    });

    test('already lowerCamelCase argument is not renamed', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { user(userId: ID!): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('user')!.arguments.first;
      expect(arg.codeName, 'userId');
    });

    test('collision: two arguments normalizing to same name get index', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { search(MaxCount: Int, maxCount: Int): String }
      ''');

      final args = g.types['Query']!.getFieldByName('search')!.arguments;
      final codeNames = args.map((a) => a.codeName).toSet();
      expect(codeNames, containsAll(['maxCount', 'maxCount2']));
    });
  });

  group('operation argument normalization', () {
    test('PascalCase operation argument → lowerCamelCase codeName, bareName unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { user(id: ID!): String }
        query GetUser(\$UserId: ID!) { user(id: \$UserId) }
      ''');

      final arg = g.queries.values
          .firstWhere((q) => q.token == 'GetUser')
          .arguments
          .first;
      expect(arg.codeName, 'userId');
      expect(arg.bareName, 'UserId');
    });

    test('SCREAMING_SNAKE operation argument → lowerCamelCase codeName', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { search(text: String): String }
        query Search(\$FULL_TEXT: String) { search(text: \$FULL_TEXT) }
      ''');

      final arg = g.queries.values
          .firstWhere((q) => q.token == 'Search')
          .arguments
          .first;
      expect(arg.codeName, 'fullText');
      expect(arg.bareName, 'FULL_TEXT');
    });
  });

  group('normalization + keyword-safe composition', () {
    test('argument normalized name that is reserved gets _ suffix', () {
      final g = GLParser(
        naming: lowerCamel,
        parameterReservedWords: {'in'},
      );
      // IN → lowerCamelCase → in → reserved → in_
      g.parse('''
        type Query { filter(IN: String): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('filter')!.arguments.first;
      expect(arg.codeName, 'in_');
      expect(arg.bareName, 'IN');
    });
  });

  group('no naming convention', () {
    test('without a NamingConvention, argument codeName equals bareName', () {
      final g = GLParser();
      g.parse('''
        type Query { user(UserId: ID!): String }
      ''');

      final arg = g.types['Query']!.getFieldByName('user')!.arguments.first;
      expect(arg.codeName, 'UserId');
    });
  });
}
