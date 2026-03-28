import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — directive definitions', () {
    test('simple directive on field', () {
      final parser = GLParser();
      parser.parse('directive @myDir on FIELD', validate: false);
      expect(parser.directiveDefinitions.containsKey('@myDir'), true);
      expect(parser.directiveDefinitions['@myDir']!.scopes,
          {GLDirectiveScope.FIELD});
    });

    test('directive on multiple scopes', () {
      final parser = GLParser();
      parser.parse('directive @myDir on FIELD | OBJECT | INTERFACE',
          validate: false);
      final scopes = parser.directiveDefinitions['@myDir']!.scopes;
      expect(scopes, {
        GLDirectiveScope.FIELD,
        GLDirectiveScope.OBJECT,
        GLDirectiveScope.INTERFACE
      });
    });

    test('directive is not repeatable by default', () {
      final parser = GLParser();
      parser.parse('directive @myDir on FIELD', validate: false);
      expect(parser.directiveDefinitions['@myDir']!.repeatable, false);
    });

    test('repeatable directive', () {
      final parser = GLParser();
      parser.parse('directive @myDir repeatable on FIELD', validate: false);
      expect(parser.directiveDefinitions['@myDir']!.repeatable, true);
    });

    test('directive with argument', () {
      final parser = GLParser();
      parser.parse('directive @myDir(reason: String) on FIELD',
          validate: false);
      final args = parser.directiveDefinitions['@myDir']!.arguments;
      expect(args.length, 1);
      expect(args.first.token, 'reason');
      expect(args.first.type.token, 'String');
    });

    test('directive with multiple arguments', () {
      final parser = GLParser();
      parser.parse('directive @myDir(reason: String!, ttl: Int = 300) on FIELD',
          validate: false);
      final args = parser.directiveDefinitions['@myDir']!.arguments;
      expect(args.length, 2);
      expect(args.first.type.nullable, false);
      expect(args.last.initialValue, 300);
    });

    test('directive without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('directive @myDir on FIELD', validate: false);
      expect(parser.directiveDefinitions['@myDir']!.documentation, null);
    });

    test('directive with documentation', () {
      final parser = GLParser();
      parser.parse('"Marks a field as deprecated" directive @myDir on FIELD',
          validate: false);
      expect(parser.directiveDefinitions['@myDir']!.documentation,
          '"Marks a field as deprecated"');
    });

    test('directive with block string documentation', () {
      final parser = GLParser();

      parser.parse(
          '"""Marks a field as deprecated""" directive @myDir on FIELD',
          validate: false);
      expect(parser.directiveDefinitions['@myDir']!.documentation,
          '"""Marks a field as deprecated"""');
    });

    test('full directive with all features', () {
      final parser = GLParser();
      parser.parse('''
        """Custom caching directive"""
        directive @cache(ttl: Int = 60, tags: [String!]) repeatable on FIELD_DEFINITION | OBJECT
      ''', validate: false);
      final d = parser.directiveDefinitions['@cache']!;
      expect(d.documentation, '"""Custom caching directive"""');
      expect(d.repeatable, true);
      expect(d.scopes,
          {GLDirectiveScope.FIELD_DEFINITION, GLDirectiveScope.OBJECT});
      expect(d.arguments.length, 2);
      expect(d.arguments.first.initialValue, 60);
      expect(d.arguments.last.type.isList, true);
    });

    test('unknown scope throws', () {
      expect(
        () => GLParser()
            .parse('directive @myDir on UNKNOWN_SCOPE', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing on keyword throws', () {
      expect(
        () => GLParser().parse('directive @myDir FIELD', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing directive name throws', () {
      expect(
        () => GLParser().parse('directive on FIELD', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing scope after pipe throws', () {
      expect(
        () => GLParser().parse('directive @myDir on FIELD |', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
