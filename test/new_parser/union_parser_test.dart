import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — union definitions', () {
    test('simple union', () {
      final parser = GLParser();
      parser.parse('union SearchResult = Photo | Person | Place',
          validate: false);
      expect(parser.unions.containsKey('SearchResult'), true);
      expect(
          parser.unions['SearchResult']!.typeNames.map((t) => t.token).toList(),
          ['Photo', 'Person', 'Place']);
    });

    test('extended union', () {
      final parser = GLParser();
      parser.parse('extend union SearchResult = Video', validate: false);
      expect(parser.unions['SearchResult']!.extension, true);
    });

    test('union without documentation has null documentation', () {
      final parser = GLParser();
      parser.parse('union SearchResult = Photo | Person', validate: false);
      expect(parser.unions['SearchResult']!.documentation, null);
    });

    test('union with documentation', () {
      final parser = GLParser();
      parser.parse('"All searchable types" union SearchResult = Photo | Person',
          validate: false);
      expect(parser.unions['SearchResult']!.documentation,
          '"All searchable types"');
    });

    test('union with block string documentation', () {
      final parser = GLParser();
      parser.parse(
          '"""All searchable types""" union SearchResult = Photo | Person',
          validate: false);
      expect(parser.unions['SearchResult']!.documentation,
          '"""All searchable types"""');
    });

    test('union with directive', () {
      final parser = GLParser();
      parser.parse('union SearchResult @deprecated = Photo | Person',
          validate: false);
      expect(parser.unions['SearchResult']!.getDirectives().first.token,
          '@deprecated');
    });

    test('union with directive and argument', () {
      final parser = GLParser();
      parser.parse(
          'union SearchResult @deprecated(reason: "use NewSearch") = Photo',
          validate: false);
      final directive = parser.unions['SearchResult']!.getDirectives().first;
      expect(directive.getArgValue('reason'), '"use NewSearch"');
    });

    test('union with single type', () {
      final parser = GLParser();
      parser.parse('union SingleResult = Photo', validate: false);
      expect(parser.unions['SingleResult']!.typeNames.length, 1);
      expect(parser.unions['SingleResult']!.typeNames.first.token, 'Photo');
    });

    test('full union with documentation', () {
      final parser = GLParser();
      parser.parse('''
        """Represents all searchable content"""
        union SearchResult @deprecated(reason: "use ContentResult") = Photo | Person | Place
      ''', validate: false);
      final u = parser.unions['SearchResult']!;
      expect(u.documentation, '"""Represents all searchable content"""');
      expect(u.getDirectives().first.token, '@deprecated');
      expect(u.typeNames.map((t) => t.token).toList(),
          ['Photo', 'Person', 'Place']);
    });

    test('duplicate union type throws', () {
      expect(
        () => GLParser()
            .parse('union SearchResult = Photo | Photo', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing union name throws', () {
      expect(
        () => GLParser().parse('union = Photo | Person', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing type after pipe throws', () {
      expect(
        () => GLParser().parse('union SearchResult = Photo |', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
