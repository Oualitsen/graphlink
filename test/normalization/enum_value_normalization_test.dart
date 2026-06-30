import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  // Helpers — anonymous conventions so tests are language-agnostic.
  final lowerCamel = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toLowerCamelCase(),
  );
  final screaming = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toScreamingSnakeCase(),
  );
  final pascal = NamingConvention(
    field: (s) => s.toLowerCamelCase(),
    enumValue: (s) => s.toPascalCase(),
  );

  group('enum value normalization — lowerCamelCase (Dart)', () {
    test('SCREAMING_SNAKE value → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('enum Sex { MALE FEMALE }');

      final male = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'MALE');
      expect(male.codeName, 'male');
      expect(male.value.token, 'MALE');
    });

    test('PascalCase value → lowerCamelCase codeName, wire name unchanged', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('enum Status { Active Inactive }');

      final active = g.enums['Status']!.values.firstWhere((v) => v.value.token == 'Active');
      expect(active.codeName, 'active');
      expect(active.value.token, 'Active');
    });

    test('already lowerCamelCase value is not renamed', () {
      final g = GLParser(naming: lowerCamel);
      g.parse('enum Status { active inactive }');

      final active = g.enums['Status']!.values.firstWhere((v) => v.value.token == 'active');
      expect(active.codeName, 'active');
    });
  });

  group('enum value normalization — SCREAMING_SNAKE (Java/Kotlin)', () {
    test('lowerCamelCase value → SCREAMING_SNAKE codeName, wire name unchanged', () {
      final g = GLParser(naming: screaming);
      g.parse('enum Sex { male female }');

      final male = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'male');
      expect(male.codeName, 'MALE');
      expect(male.value.token, 'male');
    });

    test('snake_case value → SCREAMING_SNAKE codeName', () {
      final g = GLParser(naming: screaming);
      g.parse('enum Status { not_found server_error }');

      final notFound = g.enums['Status']!.values.firstWhere((v) => v.value.token == 'not_found');
      expect(notFound.codeName, 'NOT_FOUND');
      expect(notFound.value.token, 'not_found');
    });

    test('already SCREAMING_SNAKE value is not renamed', () {
      final g = GLParser(naming: screaming);
      g.parse('enum Status { NOT_FOUND SERVER_ERROR }');

      final notFound = g.enums['Status']!.values.firstWhere((v) => v.value.token == 'NOT_FOUND');
      expect(notFound.codeName, 'NOT_FOUND');
    });
  });

  group('enum value normalization — PascalCase (TypeScript)', () {
    test('SCREAMING_SNAKE value → PascalCase codeName, wire name unchanged', () {
      final g = GLParser(naming: pascal);
      g.parse('enum Sex { MALE FEMALE }');

      final male = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'MALE');
      expect(male.codeName, 'Male');
      expect(male.value.token, 'MALE');
    });

    test('lowerCamelCase value → PascalCase codeName', () {
      final g = GLParser(naming: pascal);
      g.parse('enum Status { active inactive }');

      final active = g.enums['Status']!.values.firstWhere((v) => v.value.token == 'active');
      expect(active.codeName, 'Active');
      expect(active.value.token, 'active');
    });
  });

  group('collision handling', () {
    test('two values normalizing to same name: first keeps it, second gets index', () {
      final g = GLParser(naming: screaming);
      // MALE and Male both → MALE
      g.parse('enum Sex { male Male }');

      final lower = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'male');
      final upper = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'Male');
      final codeNames = {lower.codeName, upper.codeName};
      expect(codeNames, containsAll(['MALE', 'MALE2']));
    });
  });

  group('normalization + keyword-safe composition', () {
    test('normalized value that lands on a reserved word gets _ suffix', () {
      final g = GLParser(
        naming: lowerCamel,
        reservedWords: {'in'},
      );
      // IN → lowerCamelCase → in → reserved → in_
      g.parse('enum Direction { IN OUT }');

      final inVal = g.enums['Direction']!.values.firstWhere((v) => v.value.token == 'IN');
      expect(inVal.codeName, 'in_');
      expect(inVal.value.token, 'IN');
    });
  });

  group('no naming convention', () {
    test('without a NamingConvention, codeName equals wire name', () {
      final g = GLParser();
      g.parse('enum Sex { male female }');

      final male = g.enums['Sex']!.values.firstWhere((v) => v.value.token == 'male');
      expect(male.codeName, 'male');
    });
  });
}
