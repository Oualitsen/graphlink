import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — fragment definitions', () {
    test('simple fragment', () {
      final grammar = parse('fragment UserFields on User { id name }');
      expect(grammar.fragments.containsKey('UserFields'), true);
    });

    test('fragment on type', () {
      final grammar = parse('fragment UserFields on User { id }');
      final frag = grammar.fragments['UserFields'] as GLFragmentDefinition;
      expect(frag.token, 'UserFields');
      expect(frag.onTypeName.token, 'User');
    });

    test('fragment with single field', () {
      final grammar = parse('fragment UserFields on User { id }');
      final frag = grammar.fragments['UserFields']!;
      expect(frag.block.projections.containsKey('id'), true);
    });

    test('fragment with multiple fields', () {
      final grammar = parse('fragment UserFields on User { id name email }');
      final frag = grammar.fragments['UserFields']!;
      expect(frag.block.projections.length, 3);
    });

    test('fragment with directive', () {
      final grammar = parse('fragment UserFields on User @deprecated { id }');
      final frag = grammar.fragments['UserFields']!;
      expect(frag.getDirectives().first.token, 'deprecated');
    });

    test('fragment field with directive', () {
      final grammar = parse('fragment UserFields on User { id @deprecated }');
      final frag = grammar.fragments['UserFields']!;
      final field = frag.block.projections['id']!;
      expect(field.getDirectives().first.token, 'deprecated');
    });

    test('fragment field with alias', () {
      final grammar = parse('fragment UserFields on User { userId: id }');
      final frag = grammar.fragments['UserFields']!;
      expect(frag.block.projections.containsKey('id'), true);
      expect(frag.block.projections['id']!.alias?.token, 'userId');
    });

    test('fragment field with sub-block', () {
      final grammar = parse('fragment UserFields on User { address { street city } }');
      final frag = grammar.fragments['UserFields']!;
      final address = frag.block.projections['address']!;
      expect(address.block, isNotNull);
      expect(address.block!.projections.containsKey('street'), true);
      expect(address.block!.projections.containsKey('city'), true);
    });

    test('fragment spread reference', () {
      final grammar = parse('''
        fragment AddressFields on Address { street city }
        fragment UserFields on User { id ...AddressFields }
      ''');
      final frag = grammar.fragments['UserFields']!;
      expect(frag.block.projections.containsKey('AddressFields'), true);
      expect(frag.block.projections['AddressFields']!.isFragmentReference, true);
    });

    test('inline fragment', () {
      final grammar = parse('''
        fragment SearchResult on SearchResult {
          ... on User { id name }
        }
      ''');
      final frag = grammar.fragments['SearchResult']!;
      // inline fragment creates a GLInlineFragmentsProjection with key '*'
      expect(frag.block.projections.containsKey('*'), true);
      final proj = frag.block.projections['*']!;
      expect(proj is GLInlineFragmentsProjection, true);
    });

    test('multiple inline fragments for union', () {
      final grammar = parse('''
        fragment SearchResult on SearchResult {
          ... on User { id name }
          ... on Post { id title }
        }
      ''');
      final frag = grammar.fragments['SearchResult']!;
      final proj = frag.block.projections['*']! as GLInlineFragmentsProjection;
      expect(proj.inlineFragments.length, 2);
    });

    test('full fragment with all features', () {
      final grammar = parse('''
        fragment AdminFields on Admin {
          id
          userId: id
          name @deprecated(reason: "use fullName")
          address {
            street
            city
          }
          ...ContactFields
          ... on SuperAdmin { permissions }
        }
      ''');
      final frag = grammar.fragments['AdminFields']!;
      expect(frag.onTypeName.token, 'Admin');
      expect(frag.block.projections.containsKey('id'), true);
      expect(frag.block.projections['id']!.alias?.token, 'userId');
      expect(frag.block.projections['name']!.getDirectives().first.token, 'deprecated');
      expect(frag.block.projections['address']!.block, isNotNull);
      expect(frag.block.projections.containsKey('ContactFields'), true);
      expect(frag.block.projections.containsKey('*'), true);
    });

    test('missing fragment name throws', () {
      expect(
        () => parse('fragment on User { id }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing on keyword throws', () {
      expect(
        () => parse('fragment UserFields User { id }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing type name throws', () {
      expect(
        () => parse('fragment UserFields on { id }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('fragment UserFields on User id }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('fragment UserFields on User { id'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
