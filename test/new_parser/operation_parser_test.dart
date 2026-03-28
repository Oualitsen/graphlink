import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — operation definitions', () {
    test('simple query', () {
      final grammar = parse('query GetUser { user }');
      expect(grammar.queries.containsKey('GetUser'), true);
    });

    test('query type is query', () {
      final grammar = parse('query GetUser { user }');
      expect(grammar.queries['GetUser']!.type, GLQueryType.query);
    });

    test('mutation type is mutation', () {
      final grammar = parse('mutation CreateUser { createUser }');
      expect(grammar.queries['CreateUser']!.type, GLQueryType.mutation);
    });

    test('subscription type is subscription', () {
      final grammar = parse('subscription OnUser { userUpdated }');
      expect(grammar.queries['OnUser']!.type, GLQueryType.subscription);
    });

    test('query with single element', () {
      final grammar = parse('query GetUser { user }');
      final q = grammar.queries['GetUser']!;
      expect(q.elements.length, 1);
      expect(q.elements.first.token, 'user');
    });

    test('query with multiple elements', () {
      final grammar = parse('query GetData { user posts comments }');
      expect(grammar.queries['GetData']!.elements.length, 3);
    });

    test('query element with alias', () {
      final grammar = parse('query GetUser { me: user }');
      final elem = grammar.queries['GetUser']!.elements.first;
      expect(elem.token, 'user');
      expect(elem.alias?.token, 'me');
    });

    test('query element with sub-block', () {
      final grammar = parse('query GetUser { user { id name } }');
      final elem = grammar.queries['GetUser']!.elements.first;
      expect(elem.block, isNotNull);
      expect(elem.block!.projections.containsKey('id'), true);
      expect(elem.block!.projections.containsKey('name'), true);
    });

    test('query element with argument value', () {
      final grammar = parse('query GetUser { user(id: 42) }');
      final elem = grammar.queries['GetUser']!.elements.first;
      expect(elem.arguments.length, 1);
      expect(elem.arguments.first.token, 'id');
      expect(elem.arguments.first.value, 42);
    });

    test('query element with variable reference argument', () {
      final grammar =
          parse('query GetUser(\$userId: ID!) { user(id: \$userId) }');
      final elem = grammar.queries['GetUser']!.elements.first;
      expect(elem.arguments.first.value, '\$userId');
    });

    test('query with variable declarations', () {
      final grammar =
          parse('query GetUser(\$id: ID!, \$limit: Int = 10) { user }');
      final q = grammar.queries['GetUser']!;
      expect(q.arguments.length, 2);
      expect(q.arguments.first.token, '\$id');
      expect(q.arguments.first.type.nullable, false);
      expect(q.arguments.last.initialValue, 10);
    });

    test('query with directive', () {
      final grammar = parse('query GetUser @deprecated { user }');
      final q = grammar.queries['GetUser']!;
      expect(q.getDirectives().first.token, 'deprecated');
    });

    test('query element with directive', () {
      final grammar = parse('query GetUser { user @deprecated }');
      final elem = grammar.queries['GetUser']!.elements.first;
      expect(elem.getDirectives().first.token, 'deprecated');
    });

    test('subscription enforces single root field', () {
      final grammar = parse('subscription OnUser { userUpdated }');
      expect(grammar.queries['OnUser']!.elements.length, 1);
    });

    test('full query with all features', () {
      final grammar = parse('''
        query GetUser(\$id: ID!, \$active: Boolean = true) @deprecated {
          me: user(id: \$id, active: \$active) @cache(ttl: 60) {
            id
            name
          }
          posts
        }
      ''');
      final q = grammar.queries['GetUser']!;
      expect(q.type, GLQueryType.query);
      expect(q.arguments.length, 2);
      expect(q.getDirectives().first.token, 'deprecated');
      expect(q.elements.length, 2);
      final userElem = q.elements.first;
      expect(userElem.alias?.token, 'me');
      expect(userElem.token, 'user');
      expect(userElem.arguments.length, 2);
      expect(userElem.block!.projections.containsKey('id'), true);
    });

    test('missing operation name throws', () {
      expect(
        () => parse('query { user }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('query GetUser user }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('query GetUser { user'),
        throwsA(isA<ParseException>()),
      );
    });

    test('empty operation body throws', () {
      expect(
        () => parse('query GetUser { }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('subscription with multiple root fields throws', () {
      expect(
        () => parse('subscription OnData { userUpdated postUpdated }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('dollar without identifier throws', () {
      expect(
        () => parse('query GetUser(\$: ID!) { user }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
