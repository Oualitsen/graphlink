import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — scalar definitions', () {
    test('simple scalar', () {
      final parser = GLParser();
      parser.parse('scalar MyScalar', validate: false);
      expect(parser.scalars.containsKey('MyScalar'), true);
      expect(parser.scalars['MyScalar']!.token, 'MyScalar');
      expect(parser.scalars['MyScalar']!.extension, false);
    });

    test('extended scalar', () {
      final parser = GLParser();
      parser.parse('extend scalar MyScalar', validate: false);
      expect(parser.scalars.containsKey('MyScalar'), true);
      expect(parser.scalars['MyScalar']!.extension, true);
    });

    test('scalar with directive', () {
      final parser = GLParser();
      parser.parse('scalar MyScalar @deprecated', validate: false);
      expect(parser.scalars.containsKey('MyScalar'), true);
      expect(parser.scalars['MyScalar']!.getDirectives().length, 1);
      expect(parser.scalars['MyScalar']!.getDirectives().first.token,
          '@deprecated');
    });

    test('scalar with directive and string argument', () {
      final parser = GLParser();
      parser.parse('scalar MyScalar @deprecated(reason: "use something else")',
          validate: false);
      final directive = parser.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('reason'), '"use something else"');
    });

    test('multiple scalars', () {
      final parser = GLParser();
      parser.parse('''
        scalar A
        scalar B
        scalar C
      ''', validate: false);
      expect(parser.scalars.containsKey('A'), true);
      expect(parser.scalars.containsKey('B'), true);
      expect(parser.scalars.containsKey('C'), true);
    });

    test('duplicate scalar throws', () {
      expect(() => GLParser().parse('scalar A\nscalar A', validate: false),
          throwsA(isA<ParseException>()));
    });

    test('scalar with boolean directive argument', () {
      final parser = GLParser();
      parser.parse('scalar MyScalar @skip(if: true)', validate: false);
      final directive = parser.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('if'), true);
    });

    test('scalar with int directive argument', () {
      final parser = GLParser();
      parser.parse('scalar MyScalar @cache(ttl: 300)', validate: false);
      final directive = parser.scalars['MyScalar']!.getDirectives().first;
      expect(directive.getArgValue('ttl'), 300);
    });

    test('missing scalar name throws', () {
      expect(() => GLParser().parse('scalar', validate: false),
          throwsA(isA<ParseException>()));
    });

    test('scalar with documentation', () {
      final parser = GLParser();
      parser.parse('"A custom scalar" scalar MyScalar', validate: false);
      expect(parser.scalars['MyScalar']!.documentation, '"A custom scalar"');
    });

    test('scalar with block string documentation', () {
      final parser = GLParser();
      parser.parse('"""A custom scalar""" scalar MyScalar', validate: false);
      expect(
          parser.scalars['MyScalar']!.documentation, '"""A custom scalar"""');
    });
  });
}
