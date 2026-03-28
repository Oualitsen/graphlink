import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GLParser — enum definitions', () {
    test('simple enum', () {
      final parser = GLParser();
      parser.parse('enum Status { ACTIVE INACTIVE }', validate: false);
      expect(parser.enums.containsKey('Status'), true);
      expect(parser.enums['Status']!.values.length, 2);
    });

    test('extended enum', () {
      final parser = GLParser();
      parser.parse('extend enum Status { ACTIVE }', validate: false);
      expect(parser.enums['Status']!.extension, true);
    });

    test('enum with documentation', () {
      final parser = GLParser();
      parser.parse('"Represents a status" enum Status { ACTIVE }',
          validate: false);
      expect(parser.enums['Status']!.documentation, '"Represents a status"');
    });

    test('enum with block string documentation', () {
      final parser = GLParser();
      parser.parse('"""Represents a status""" enum Status { ACTIVE }',
          validate: false);
      expect(
          parser.enums['Status']!.documentation, '"""Represents a status"""');
    });

    test('enum with directive', () {
      final parser = GLParser();
      parser.parse('enum Status @deprecated { ACTIVE }', validate: false);
      expect(
          parser.enums['Status']!.getDirectives().first.token, '@deprecated');
    });

    test('enum value with documentation', () {
      final parser = GLParser();
      parser.parse('''
        enum Status {
          "The user is active"
          ACTIVE
          INACTIVE
        }
      ''', validate: false);
      final values = parser.enums['Status']!.values;
      final active = values.firstWhere((v) => v.token == 'ACTIVE');
      expect(active.documentation, '"The user is active"');
    });

    test('enum value with block string documentation', () {
      final parser = GLParser();
      parser.parse('''
        enum Status {
          """The user is active"""
          ACTIVE
        }
      ''', validate: false);
      final active = parser.enums['Status']!.values.first;
      expect(active.documentation, '"""The user is active"""');
    });

    test('enum value with directive', () {
      final parser = GLParser();
      parser.parse('enum Status { ACTIVE @deprecated(reason: "use ENABLED") }',
          validate: false);
      final active = parser.enums['Status']!.values.first;
      expect(active.getDirectives().first.token, '@deprecated');
      expect(
          active.getDirectives().first.getArgValue('reason'), '"use ENABLED"');
    });

    test('full enum with documentation and documented values', () {
      final parser = GLParser();
      parser.parse('''
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
      ''', validate: false);
      final e = parser.enums['OrderStatus']!;
      expect(e.documentation, '"""Represents the status of an order"""');
      expect(e.getDirectives().first.token, '@deprecated');
      expect(e.values.length, 5);
      final pending = e.values.firstWhere((v) => v.token == 'PENDING');
      expect(pending.documentation, '"Order has been placed"');
      expect(pending.getDirectives().first.getArgValue('reason'),
          '"use CREATED instead"');
      final processing = e.values.firstWhere((v) => v.token == 'PROCESSING');
      expect(processing.documentation, '"""Order is being processed"""');
      final created = e.values.firstWhere((v) => v.token == 'CREATED');
      expect(created.documentation, null);
    });

    test('duplicate enum value throws', () {
      expect(
        () =>
            GLParser().parse('enum Status { ACTIVE ACTIVE }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing enum name throws', () {
      expect(
        () => GLParser().parse('enum { ACTIVE }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws', () {
      expect(
        () => GLParser().parse('enum Status { ACTIVE', validate: false),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing opening brace throws', () {
      expect(
        () => GLParser().parse('enum Status ACTIVE }', validate: false),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
