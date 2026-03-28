import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — directive definitions', () {
    test('simple directive on field', () {
      final grammar = parse('directive @myDir on FIELD');
      expect(grammar.directiveDefinitions.containsKey('myDir'), true);
      expect(grammar.directiveDefinitions['myDir']!.scopes, {GLDirectiveScope.FIELD});
    });

    test('directive on multiple scopes', () {
      final grammar = parse('directive @myDir on FIELD | OBJECT | INTERFACE');
      final scopes = grammar.directiveDefinitions['myDir']!.scopes;
      expect(scopes, {GLDirectiveScope.FIELD, GLDirectiveScope.OBJECT, GLDirectiveScope.INTERFACE});
    });

    test('directive is not repeatable by default', () {
      final grammar = parse('directive @myDir on FIELD');
      expect(grammar.directiveDefinitions['myDir']!.repeatable, false);
    });

    test('repeatable directive', () {
      final grammar = parse('directive @myDir repeatable on FIELD');
      expect(grammar.directiveDefinitions['myDir']!.repeatable, true);
    });

    test('directive with argument', () {
      final grammar = parse('directive @myDir(reason: String) on FIELD');
      final args = grammar.directiveDefinitions['myDir']!.arguments;
      expect(args.length, 1);
      expect(args.first.token, 'reason');
      expect(args.first.type.token, 'String');
    });

    test('directive with multiple arguments', () {
      final grammar = parse('directive @myDir(reason: String!, ttl: Int = 300) on FIELD');
      final args = grammar.directiveDefinitions['myDir']!.arguments;
      expect(args.length, 2);
      expect(args.first.type.nullable, false);
      expect(args.last.initialValue, 300);
    });

    test('directive without documentation has null documentation', () {
      final grammar = parse('directive @myDir on FIELD');
      expect(grammar.directiveDefinitions['myDir']!.documentation, null);
    });

    test('directive with documentation', () {
      final grammar = parse('"Marks a field as deprecated" directive @myDir on FIELD');
      expect(grammar.directiveDefinitions['myDir']!.documentation, '"Marks a field as deprecated"');
    });

    test('directive with block string documentation', () {
      final grammar = parse('"""Marks a field as deprecated""" directive @myDir on FIELD');
      expect(grammar.directiveDefinitions['myDir']!.documentation, '"""Marks a field as deprecated"""');
    });

    test('full directive with all features', () {
      final grammar = parse('''
        """Custom caching directive"""
        directive @cache(ttl: Int = 60, tags: [String!]) repeatable on FIELD_DEFINITION | OBJECT
      ''');
      final d = grammar.directiveDefinitions['cache']!;
      expect(d.documentation, '"""Custom caching directive"""');
      expect(d.repeatable, true);
      expect(d.scopes, {GLDirectiveScope.FIELD_DEFINITION, GLDirectiveScope.OBJECT});
      expect(d.arguments.length, 2);
      expect(d.arguments.first.initialValue, 60);
      expect(d.arguments.last.type.isList, true);
    });

    test('unknown scope throws', () {
      expect(
        () => parse('directive @myDir on UNKNOWN_SCOPE'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing on keyword throws', () {
      expect(
        () => parse('directive @myDir FIELD'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing directive name throws', () {
      expect(
        () => parse('directive on FIELD'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing scope after pipe throws', () {
      expect(
        () => parse('directive @myDir on FIELD |'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
