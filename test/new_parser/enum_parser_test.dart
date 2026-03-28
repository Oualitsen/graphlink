import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'parser_test_helper.dart';

void main() {
  group('GLParser — enum definitions', () {
    test('simple enum', () {
      final grammar = parse('enum Status { ACTIVE INACTIVE }');
      expect(grammar.enums.containsKey('Status'), true);
      expect(grammar.enums['Status']!.values.length, 2);
    });

    test('extended enum', () {
      final grammar = parse('extend enum Status { ACTIVE }');
      expect(grammar.enums['Status']!.extension, true);
    });

    test('enum with documentation', () {
      final grammar = parse('"Represents a status" enum Status { ACTIVE }');
      expect(grammar.enums['Status']!.documentation, '"Represents a status"');
    });

    test('enum with block string documentation', () {
      final grammar = parse('"""Represents a status""" enum Status { ACTIVE }');
      expect(grammar.enums['Status']!.documentation, '"""Represents a status"""');
    });

    test('enum with directive', () {
      final grammar = parse('enum Status @deprecated { ACTIVE }');
      expect(grammar.enums['Status']!.getDirectives().first.token, 'deprecated');
    });

    test('enum value with documentation', () {
      final grammar = parse('''
        enum Status {
          "The user is active"
          ACTIVE
          INACTIVE
        }
      ''');
      final values = grammar.enums['Status']!.values;
      final active = values.firstWhere((v) => v.token == 'ACTIVE');
      expect(active.documentation, '"The user is active"');
    });

    test('enum value with block string documentation', () {
      final grammar = parse('''
        enum Status {
          """The user is active"""
          ACTIVE
        }
      ''');
      final active = grammar.enums['Status']!.values.first;
      expect(active.documentation, '"""The user is active"""');
    });

    test('enum value with directive', () {
      final grammar = parse('enum Status { ACTIVE @deprecated(reason: "use ENABLED") }');
      final active = grammar.enums['Status']!.values.first;
      expect(active.getDirectives().first.token, 'deprecated');
      expect(active.getDirectives().first.getArgValue('reason'), '"use ENABLED"');
    });

    test('full enum with documentation and documented values', () {
      final grammar = parse('''
        """Represents the status of an order"""
        enum OrderStatus @deprecated {
          "Order has been placed"
          PENDING @deprecated(reason: "use CREATED instead")

          CREATED

          """Order is being processed"""
          PROCESSING

          COMPLETED
          CANCELLED
        }
      ''');
      final e = grammar.enums['OrderStatus']!;
      expect(e.documentation, '"""Represents the status of an order"""');
      expect(e.getDirectives().first.token, 'deprecated');
      expect(e.values.length, 5);
      final pending = e.values.firstWhere((v) => v.token == 'PENDING');
      expect(pending.documentation, '"Order has been placed"');
      expect(pending.getDirectives().first.getArgValue('reason'), '"use CREATED instead"');
      final processing = e.values.firstWhere((v) => v.token == 'PROCESSING');
      expect(processing.documentation, '"""Order is being processed"""');
      final created = e.values.firstWhere((v) => v.token == 'CREATED');
      expect(created.documentation, null);
    });

    test('duplicate enum value throws', () {
      expect(
        () => parse('enum Status { ACTIVE ACTIVE }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing enum name throws', () {
      expect(
        () => parse('enum { ACTIVE }'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => parse('enum Status { ACTIVE'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => parse('enum Status ACTIVE }'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
