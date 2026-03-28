import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — operation definitions', () {
    test('simple query', () {
      final parser = GLParser();
      parser.parse('query GetUser { user }', validate: false);
      expect(parser.queries.containsKey('GetUser'), true);
    });

    test('query type is query', () {
      final parser = GLParser();
      parser.parse('query GetUser { user }', validate: false);
      expect(parser.queries['GetUser']!.type, GLQueryType.query);
    });

    test('mutation type is mutation', () {
      final parser = GLParser();
      parser.parse('mutation CreateUser { createUser }', validate: false);
      expect(parser.queries['CreateUser']!.type, GLQueryType.mutation);
    });

    test('subscription type is subscription', () {
      final parser = GLParser();
      parser.parse('subscription OnUser { userUpdated }', validate: false);
      expect(parser.queries['OnUser']!.type, GLQueryType.subscription);
    });

    test('query with single element', () {
      final parser = GLParser();
      parser.parse('query GetUser { user }', validate: false);
      final q = parser.queries['GetUser']!;
      expect(q.elements.length, 1);
      expect(q.elements.first.token, 'user');
    });

    test('query with multiple elements', () {
      final parser = GLParser();
      parser.parse('query GetData { user posts comments }', validate: false);
      expect(parser.queries['GetData']!.elements.length, 3);
    });

    test('query element with alias', () {
      final parser = GLParser();
      parser.parse('query GetUser { me: user }', validate: false);
      final elem = parser.queries['GetUser']!.elements.first;
      expect(elem.token, 'user');
      expect(elem.alias?.token, 'me');
    });

    test('query element with sub-block', () {
      final parser = GLParser();
      parser.parse('query GetUser { user { id name } }', validate: false);
      final elem = parser.queries['GetUser']!.elements.first;
      expect(elem.block, isNotNull);
      expect(elem.block!.projections.containsKey('id'), true);
      expect(elem.block!.projections.containsKey('name'), true);
    });

    test('query element with argument value', () {
      final parser = GLParser();
      parser.parse('query GetUser { user(id: 42) }', validate: false);
      final elem = parser.queries['GetUser']!.elements.first;
      expect(elem.arguments.length, 1);
      expect(elem.arguments.first.token, 'id');
      expect(elem.arguments.first.value, 42);
    });

    test('query element with variable reference argument', () {
      final parser = GLParser();
      parser.parse('query GetUser(\$userId: ID!) { user(id: \$userId) }',
          validate: false);
      final elem = parser.queries['GetUser']!.elements.first;
      expect(elem.arguments.first.value, '\$userId');
    });

    test('query with variable declarations', () {
      final parser = GLParser();
      parser.parse('query GetUser(\$id: ID!, \$limit: Int = 10) { user }',
          validate: false);
      final q = parser.queries['GetUser']!;
      expect(q.arguments.length, 2);
      expect(q.arguments.first.token, '\$id');
      expect(q.arguments.first.type.nullable, false);
      expect(q.arguments.last.initialValue, 10);
    });

    test('query with directive', () {
      final parser = GLParser();
      parser.parse('query GetUser @deprecated { user }', validate: false);
      final q = parser.queries['GetUser']!;
      expect(q.getDirectives().first.token, '@deprecated');
    });

    test('query element with directive', () {
      final parser = GLParser();
      parser.parse('query GetUser { user @deprecated }', validate: false);
      final elem = parser.queries['GetUser']!.elements.first;
      expect(elem.getDirectives().first.token, '@deprecated');
    });

    test('subscription enforces single root field', () {
      final parser = GLParser();
      parser.parse('subscription OnUser { userUpdated }', validate: false);
      expect(parser.queries['OnUser']!.elements.length, 1);
    });

    test('full query with all features', () {
      final parser = GLParser();
      parser.parse('''
        query GetUser(\$id: ID!, \$active: Boolean = true) @deprecated {
          me: user(id: \$id, active: \$active) @cache(ttl: 60) {
            id
            name
          }
          posts
        }
      ''', validate: false);
      final q = parser.queries['GetUser']!;
      expect(q.type, GLQueryType.query);
      expect(q.arguments.length, 2);
      expect(q.getDirectives().first.token, '@deprecated');
      expect(q.elements.length, 2);
      final userElem = q.elements.first;
      expect(userElem.alias?.token, 'me');
      expect(userElem.token, 'user');
      expect(userElem.arguments.length, 2);
      expect(userElem.block!.projections.containsKey('id'), true);
    });

    test('missing operation name throws', () {
      expect(
        () => GLParser().parse('query { user }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => GLParser().parse('query GetUser user }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => GLParser().parse('query GetUser { user', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('empty operation body throws', () {
      expect(
        () => GLParser().parse('query GetUser { }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('subscription with multiple root fields throws', () {
      expect(
        () => GLParser().parse(
            'subscription OnData { userUpdated postUpdated }',
            validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('dollar without identifier throws', () {
      expect(
        () => GLParser()
            .parse('query GetUser(\$: ID!) { user }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
