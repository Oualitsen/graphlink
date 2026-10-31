import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _prelude = '''
  enum Status { ACTIVE INACTIVE }
  scalar Date
  input Filter { limit: Int! status: Status tag: String }
''';

void _parse(String queryFields) => GLParser().parse('''
  $_prelude
  type Query { $queryFields }
''');

Matcher _rejectsWith(String fragment) => throwsA(
    isA<ParseException>().having((e) => e.message, 'message', contains(fragment)));

void main() {
  group('default values are checked against their declared type', () {
    group('scalars', () {
      test('rejects a string for Int', () {
        expect(() => _parse('q(n: Int = "x"): Int'), _rejectsWith("'Int'"));
      });

      test('rejects an int for String', () {
        expect(() => _parse('q(s: String = 5): Int'), _rejectsWith("'String'"));
      });

      test('rejects a bare name for String', () {
        expect(() => _parse('q(s: String = hello): Int'), _rejectsWith("'String'"));
      });

      test('rejects a string for Boolean', () {
        expect(() => _parse('q(b: Boolean = "true"): Int'), _rejectsWith("'Boolean'"));
      });

      test('rejects an object for a scalar', () {
        expect(() => _parse('q(n: Int = {a: 1}): Int'), _rejectsWith("'Int'"));
      });

      test('accepts an int for Float', () {
        expect(() => _parse('q(f: Float = 1): Int'), returnsNormally);
      });

      test('accepts an int or a string for ID', () {
        expect(() => _parse('q(a: ID = 1, b: ID = "x"): Int'), returnsNormally);
      });

      test('accepts any value for a custom scalar', () {
        expect(() => _parse('q(d: Date = "2024-01-01"): Int'), returnsNormally);
      });
    });

    group('enums', () {
      test('rejects a value the enum does not declare', () {
        expect(() => _parse('q(s: Status = BOGUS): Int'), _rejectsWith('BOGUS'));
      });

      test('rejects a quoted string, enums are bare names', () {
        expect(() => _parse('q(s: Status = "ACTIVE"): Int'), _rejectsWith("'Status'"));
      });

      test('accepts a declared value', () {
        expect(() => _parse('q(s: Status = ACTIVE): Int'), returnsNormally);
      });
    });

    group('input objects', () {
      test('rejects a missing required field', () {
        expect(() => _parse('q(f: Filter = {tag: "x"}): Int'), _rejectsWith("'limit'"));
      });

      test('rejects a wrongly typed field', () {
        expect(() => _parse('q(f: Filter = {limit: "x"}): Int'), _rejectsWith("'Int'"));
      });

      test('rejects an undeclared enum value in a field', () {
        expect(
          () => _parse('q(f: Filter = {limit: 1, status: BOGUS}): Int'),
          _rejectsWith('BOGUS'),
        );
      });

      test('accepts a complete object', () {
        expect(
          () => _parse('q(f: Filter = {limit: 1, status: ACTIVE, tag: "x"}): Int'),
          returnsNormally,
        );
      });
    });

    group('lists', () {
      test('rejects a wrongly typed item', () {
        expect(() => _parse('q(l: [Int!] = [1, "x"]): Int'), _rejectsWith("'Int'"));
      });

      test('accepts a single value where a list is expected', () {
        expect(() => _parse('q(l: [Int!] = 5): Int'), returnsNormally);
      });

      test('accepts a list of valid items', () {
        expect(() => _parse('q(l: [Int!] = [1, 2]): Int'), returnsNormally);
      });
    });

    group('input field defaults and query variable defaults', () {
      test('rejects a wrongly typed default on an input field', () {
        expect(
          () => GLParser().parse('input I { n: Int = "x" } type Query { q: Int }'),
          _rejectsWith("'Int'"),
        );
      });

      test('rejects a wrongly typed default on an operation variable', () {
        expect(
          () => GLParser().parse('''
            type Query { q(n: Int): Int }
            query Q(\$n: Int = "x") { q(n: \$n) }
          '''),
          _rejectsWith("'Int'"),
        );
      });
    });
  });
}
