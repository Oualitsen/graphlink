import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — schema definitions', () {
    test('simple schema with query', () {
      final parser = GLParser();
      parser.parse('schema { query: MyQuery }', validate: false);
      expect(parser.schema.getByQueryType(GLQueryType.query), 'MyQuery');
    });

    test('schema with query and mutation', () {
      final parser = GLParser();
      parser.parse('schema { query: MyQuery mutation: MyMutation }',
          validate: false);
      expect(parser.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(parser.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
    });

    test('schema with all operation types', () {
      final parser = GLParser();
      parser.parse(
          'schema { query: MyQuery mutation: MyMutation subscription: MySubscription }',
          validate: false);
      expect(parser.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(parser.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
      expect(parser.schema.getByQueryType(GLQueryType.subscription),
          'MySubscription');
    });

    test('schema with directive', () {
      final parser = GLParser();
      parser.parse('schema @deprecated { query: MyQuery }', validate: false);
      expect(parser.schema.getDirectives().first.token, '@deprecated');
    });

    test('schema without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('schema { query: MyQuery }', validate: false);
      expect(parser.schema.documentation, null);
    });

    test('schema with documentation', () {
      final parser = GLParser();
      parser.parse('"The root schema" schema { query: MyQuery }',
          validate: false);
      expect(parser.schema.documentation, '"The root schema"');
    });

    test('schema with block string documentation', () {
      final parser = GLParser();
      parser.parse('"""The root schema""" schema { query: MyQuery }',
          validate: false);
      expect(parser.schema.documentation, '"""The root schema"""');
    });

    test('extended schema merges operation types', () {
      final parser = GLParser();
      parser.parse('''
        schema { query: MyQuery }
        extend schema { mutation: MyMutation }
      ''', validate: false);
      expect(parser.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(parser.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
    });

    test('schema defaults to Query when not defined', () {
      final parser = GLParser();
      parser.parse('schema { mutation: MyMutation }', validate: false);
      expect(parser.schema.getByQueryType(GLQueryType.query), 'Query');
    });

    test('full schema with all features', () {
      final parser = GLParser();
      parser.parse('''
        """The root schema definition"""
        schema @deprecated(reason: "use new schema") {
          query: MyQuery
          mutation: MyMutation
          subscription: MySubscription
        }
      ''', validate: false);
      expect(parser.schema.documentation, '"""The root schema definition"""');
      expect(parser.schema.getDirectives().first.getArgValue('reason'),
          '"use new schema"');
      expect(parser.schema.getByQueryType(GLQueryType.query), 'MyQuery');
      expect(parser.schema.getByQueryType(GLQueryType.mutation), 'MyMutation');
      expect(parser.schema.getByQueryType(GLQueryType.subscription),
          'MySubscription');
    });

    test('duplicate schema definition throws', () {
      expect(
        () => GLParser()
            .parse('schema { query: A } schema { query: B }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('duplicate operation type in schema throws', () {
      expect(
        () => GLParser().parse('schema { query: A query: B }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('invalid operation type in schema throws', () {
      expect(
        () => GLParser().parse('schema { unknown: MyQuery }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
