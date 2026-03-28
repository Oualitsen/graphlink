import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — schema definitions', () {
    test('simple schema with query', () {
      final grammar = parse('schema { query: MyQuery }');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'MyQuery');
    });

    test('schema with query and mutation', () {
      final grammar = parse('schema { query: MyQuery mutation: MyMutation }');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(grammar.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
    });

    test('schema with all operation types', () {
      final grammar = parse('schema { query: MyQuery mutation: MyMutation subscription: MySubscription }');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(grammar.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
      expect(grammar.schema.getByQueryType(GLQueryType.subscription), 'MySubscription');
    });

    test('schema with directive', () {
      final grammar = parse('schema @deprecated { query: MyQuery }');
      expect(grammar.schema.getDirectives().first.token, 'deprecated');
    });

    test('schema without documentation has null documentation', () {
      final grammar = parse('schema { query: MyQuery }');
      expect(grammar.schema.documentation, null);
    });

    test('schema with documentation', () {
      final grammar = parse('"The root schema" schema { query: MyQuery }');
      expect(grammar.schema.documentation, '"The root schema"');
    });

    test('schema with block string documentation', () {
      final grammar = parse('"""The root schema""" schema { query: MyQuery }');
      expect(grammar.schema.documentation, '"""The root schema"""');
    });

    test('extended schema merges operation types', () {
      final grammar = parse('''
        schema { query: MyQuery }
        extend schema { mutation: MyMutation }
      ''');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(grammar.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
    });

    test('schema defaults to Query when not defined', () {
      final grammar = parse('schema { mutation: MyMutation }');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'Query');
    });

    test('full schema with all features', () {
      final grammar = parse('''
        """The root schema definition"""
        schema @deprecated(reason: "use new schema") {
          query: MyQuery
          mutation: MyMutation
          subscription: MySubscription
        }
      ''');
      expect(grammar.schema.documentation, '"""The root schema definition"""');
      expect(grammar.schema.getDirectives().first.getArgValue('reason'), '"use new schema"');
      expect(grammar.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(grammar.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
      expect(grammar.schema.getByQueryType(GLQueryType.subscription), 'MySubscription');
    });

    test('duplicate schema definition throws', () {
      expect(
        () => parse('schema { query: A } schema { query: B }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate operation type in schema throws', () {
      expect(
        () => parse('schema { query: A query: B }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('invalid operation type in schema throws', () {
      expect(
        () => parse('schema { unknown: MyQuery }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
