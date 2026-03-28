import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — union definitions', () {
    test('simple union', () {
      final grammar = parse('union SearchResult = Photo | Person | Place');
      expect(grammar.unions.containsKey('SearchResult'), true);
      expect(grammar.unions['SearchResult']!.typeNames.map((t) => t.token).toList(),
          ['Photo', 'Person', 'Place']);
    });

    test('extended union', () {
      final grammar = parse('extend union SearchResult = Video');
      expect(grammar.unions['SearchResult']!.extension, true);
    });

    test('union without documentation has null documentation', () {
      final grammar = parse('union SearchResult = Photo | Person');
      expect(grammar.unions['SearchResult']!.documentation, null);
    });

    test('union with documentation', () {
      final grammar = parse('"All searchable types" union SearchResult = Photo | Person');
      expect(grammar.unions['SearchResult']!.documentation, '"All searchable types"');
    });

    test('union with block string documentation', () {
      final grammar = parse('"""All searchable types""" union SearchResult = Photo | Person');
      expect(grammar.unions['SearchResult']!.documentation, '"""All searchable types"""');
    });

    test('union with directive', () {
      final grammar = parse('union SearchResult @deprecated = Photo | Person');
      expect(grammar.unions['SearchResult']!.getDirectives().first.token, 'deprecated');
    });

    test('union with directive and argument', () {
      final grammar = parse('union SearchResult @deprecated(reason: "use NewSearch") = Photo');
      final directive = grammar.unions['SearchResult']!.getDirectives().first;
      expect(directive.getArgValue('reason'), '"use NewSearch"');
    });

    test('union with single type', () {
      final grammar = parse('union SingleResult = Photo');
      expect(grammar.unions['SingleResult']!.typeNames.length, 1);
      expect(grammar.unions['SingleResult']!.typeNames.first.token, 'Photo');
    });

    test('full union with documentation', () {
      final grammar = parse('''
        """Represents all searchable content"""
        union SearchResult @deprecated(reason: "use ContentResult") = Photo | Person | Place
      ''');
      final u = grammar.unions['SearchResult']!;
      expect(u.documentation, '"""Represents all searchable content"""');
      expect(u.getDirectives().first.token, 'deprecated');
      expect(u.typeNames.map((t) => t.token).toList(), ['Photo', 'Person', 'Place']);
    });

    test('duplicate union type throws', () {
      expect(
        () => parse('union SearchResult = Photo | Photo'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing union name throws', () {
      expect(
        () => parse('union = Photo | Person'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing type after pipe throws', () {
      expect(
        () => parse('union SearchResult = Photo |'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
