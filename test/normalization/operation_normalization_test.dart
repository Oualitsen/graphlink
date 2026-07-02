import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  final lowerCamel = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );

  group('operation name normalization', () {
    test('_prefixed query → leading underscore stripped, codeName is lowerCamelCase, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { _userResolver: String }
        query _userResolver { _userResolver }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == '_userResolver');
      expect(q.codeName, 'userResolver');
      expect(q.token, '_userResolver');
    });

    test('SCREAMING_SNAKE query → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { GET_USER: String }
        query GET_USER { GET_USER }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == 'GET_USER');
      expect(q.codeName, 'getUser');
      expect(q.token, 'GET_USER');
    });

    test('snake_case query → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { get_user: String }
        query get_user { get_user }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == 'get_user');
      expect(q.codeName, 'getUser');
      expect(q.token, 'get_user');
    });

    test('already lowerCamelCase query is not renamed', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('''
        type Query { getUser: String }
        query getUser { getUser }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == 'getUser');
      expect(q.codeName, 'getUser');
    });

    test('normalization + keyword-safe: normalized name landing on reserved word gets _ suffix', () {
      final g = GLParser(
        naming: lowerCamel,
        reservedWords: {'return'},
      );
      g.parse('''
        type Query { Return: String }
        query Return { Return }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == 'Return');
      expect(q.codeName, 'return_');
      expect(q.token, 'Return');
    });

    test('without a NamingConvention, leading-underscore operation still gets trailing-underscore codeName', () {
      final g = GLParser();
      g.parse('''
        type Query { _userResolver: String }
        query _userResolver { _userResolver }
      ''');

      final q = g.queries.values.firstWhere((q) => q.token == '_userResolver');
      expect(q.codeName, 'userResolver_');
      expect(q.token, '_userResolver');
    });
  });
}
