import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — scalar definitions', () {
    test('simple scalar', () {
      final grammar = parse('scalar MyScalar');
      expect(grammar.scalars.containsKey('MyScalar'), true);
      expect(grammar.scalars['MyScalar']!.token, 'MyScalar');
      expect(grammar.scalars['MyScalar']!.extension, false);
    });

    test('extended scalar', () {
      final grammar = parse('extend scalar MyScalar');
      expect(grammar.scalars.containsKey('MyScalar'), true);
      expect(grammar.scalars['MyScalar']!.extension, true);
    });

    test('scalar with directive', () {
      final grammar = parse('scalar MyScalar @deprecated');
      expect(grammar.scalars.containsKey('MyScalar'), true);
      expect(grammar.scalars['MyScalar']!.getDirectives().length, 1);
      expect(grammar.scalars['MyScalar']!.getDirectives().first.token, 'deprecated');
    });

    test('scalar with directive and string argument', () {
      final grammar = parse('scalar MyScalar @deprecated(reason: "use something else")');
      final directive = grammar.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('reason'), '"use something else"');
    });

    test('multiple scalars', () {
      final grammar = parse('''
        scalar A
        scalar B
        scalar C
      ''');
      expect(grammar.scalars.containsKey('A'), true);
      expect(grammar.scalars.containsKey('B'), true);
      expect(grammar.scalars.containsKey('C'), true);
    });

    test('duplicate scalar throws', () {
      expect(() => parse('scalar A\nscalar A'), throwsA(isA<ParseException>()));
    });

    test('scalar with boolean directive argument', () {
      final grammar = parse('scalar MyScalar @skip(if: true)');
      final directive = grammar.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('if'), true);
    });

    test('scalar with int directive argument', () {
      final grammar = parse('scalar MyScalar @cache(ttl: 300)');
      final directive = grammar.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('ttl'), 300);
    });

    test('missing scalar name throws', () {
      expect(() => parse('scalar'), throwsA(isA<ParseException>()));
    });

    test('scalar with documentation', () {
      final grammar = parse('"A custom scalar" scalar MyScalar');
      expect(grammar.scalars['MyScalar']!.documentation, '"A custom scalar"');
    });

    test('scalar with block string documentation', () {
      final grammar = parse('"""A custom scalar""" scalar MyScalar');
      expect(grammar.scalars['MyScalar']!.documentation, '"""A custom scalar"""');
    });
  });
}
