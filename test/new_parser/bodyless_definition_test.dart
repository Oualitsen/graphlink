import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

/// Tests for bodyless type/interface/input definitions.
/// This is a common pattern in modular schemas where a stub declaration
/// is extended by one or more `extend` blocks across files.
void main() {
  // ── Parser: bodyless definitions must parse without error ─────────────────
  group('bodyless definitions — parse (validate: false)', () {
    test('type without body parses', () {
      expect(
        () => GLParser().parse('type Query', validate: false),
        returnsNormally,
      );
    });

    test('interface without body parses', () {
      expect(
        () => GLParser().parse('interface Node', validate: false),
        returnsNormally,
      );
    });

    test('input without body parses', () {
      expect(
        () => GLParser().parse('input CreateUserInput', validate: false),
        returnsNormally,
      );
    });
  });

  // ── Validation: bodyless with no extend must throw ────────────────────────
  group('bodyless definitions — validation rejects zero fields', () {
    test('type with no fields and no extend throws', () {
      expect(
        () => GLParser().parse('type Query', validate: true),
        throwsA(isA<ParseException>()),
      );
    });

    test('interface with no fields and no extend throws', () {
      expect(
        () => GLParser().parse('interface Node', validate: true),
        throwsA(isA<ParseException>()),
      );
    });

    test('input with no fields and no extend throws', () {
      expect(
        () => GLParser().parse('input CreateUserInput', validate: true),
        throwsA(isA<ParseException>()),
      );
    });
  });

  // ── Validation: bodyless + extend passes ──────────────────────────────────
  group('bodyless definitions — validation passes when extended with fields', () {
    test('bodyless type extended with fields passes', () {
      expect(
        () => GLParser().parse('''
          type Query
          extend type Query {
            users: [String!]!
          }
        ''', validate: false),
        returnsNormally,
      );
    });

    test('bodyless interface extended with fields passes', () {
      expect(
        () => GLParser().parse('''
          interface Node
          extend interface Node {
            id: ID!
          }
        ''', validate: false),
        returnsNormally,
      );
    });

    test('bodyless input extended with fields passes', () {
      expect(
        () => GLParser().parse('''
          input CreateUserInput
          extend input CreateUserInput {
            name: String!
          }
        ''', validate: false),
        returnsNormally,
      );
    });
  });
}
