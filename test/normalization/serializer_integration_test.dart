/// Integration tests: naming convention → serializer output.
/// Each test uses a static NamingConvention instance (the same one generators
/// will receive after grammar_factory is wired) and verifies the emitted code.
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  // ── Dart ─────────────────────────────────────────────────────────────────

  group('Dart — NamingConvention.dart', () {
    test('PascalCase field: identifier is lowerCamelCase, JSON key is original', () {
      final g = GLParser(
        naming: NamingConvention.dart,
        reservedWords: dartReservedWords,
      );
      g.parse('''
        type Company { User: User }
        type User { id: ID! }
      ''');

      final out = DartSerializer(g, importPrefix: '').serializeTypeDefinition(
          g.types['Company']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      // identifier is lowerCamelCase
      expect(lines, anyElement(contains('User? user;')));
      // toJson wire key stays 'User'
      expect(lines, anyElement(contains("'User': user")));
      // fromJson reads from 'User'
      expect(lines, anyElement(contains("json['User']")));
    });

    test('input SCREAMING_SNAKE field: identifier lowerCamelCase, JSON key original', () {
      final g = GLParser(
        naming: NamingConvention.dart,
        reservedWords: dartReservedWords,
      );
      g.parse('''
        input ProductFilter { IS_ACTIVE: Boolean }
      ''');

      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(
          g.inputs['ProductFilter']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, contains('final bool? isActive;'));
      expect(lines, anyElement(contains("'IS_ACTIVE': isActive")));
      expect(lines, anyElement(contains("json['IS_ACTIVE']")));
    });

    test('enum SCREAMING_SNAKE value: codeName is lowerCamelCase, toJson/fromJson use wire name', () {
      final g = GLParser(
        naming: NamingConvention.dart,
        reservedWords: dartReservedWords,
      );
      g.parse('enum Sex { MALE FEMALE }');

      final out = DartSerializer(g, importPrefix: '').serializeEnumDefinition(
          g.enums['Sex']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, anyElement(contains('male,')));
      expect(lines, anyElement(contains("case male:")));
      expect(lines, anyElement(contains('return "MALE";')));
      expect(lines, anyElement(contains('case "MALE":')));
    });
  });

  // ── Java ─────────────────────────────────────────────────────────────────

  group('Java — NamingConvention.java', () {
    test('enum lowerCase value: codeName is SCREAMING_SNAKE, toJson/fromJson use wire name', () {
      final g = GLParser(
        naming: NamingConvention.java,
        reservedWords: javaReservedWords,
      );
      g.parse('enum Sex { male female }');

      final out = JavaSerializer(g, importPrefix: '', generateJsonMethods: true)
          .serializeEnumDefinition(g.enums['Sex']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      // code constant is SCREAMING
      expect(lines, anyElement(contains('MALE')));
      expect(lines, anyElement(contains('FEMALE')));
      // toJson returns the original wire name
      expect(lines, anyElement(contains('"male"')));
      expect(lines, anyElement(contains('"female"')));
    });

    test('PascalCase field: identifier is lowerCamelCase, JSON key is original', () {
      final g = GLParser(
        naming: NamingConvention.java,
        reservedWords: javaReservedWords,
      );
      g.parse('''
        type Company { User: User }
        type User { id: ID! }
      ''');

      final out = JavaSerializer(g, importPrefix: '', generateJsonMethods: true)
          .serializeTypeDefinition(g.types['Company']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, anyElement(contains('user')));
      expect(lines, anyElement(contains('"User"')));
    });
  });

  // ── Kotlin ───────────────────────────────────────────────────────────────

  group('Kotlin — NamingConvention.kotlin', () {
    test('enum lowerCase value: codeName is SCREAMING_SNAKE, wire name preserved', () {
      final g = GLParser(
        naming: NamingConvention.kotlin,
        reservedWords: kotlinReservedWords,
      );
      g.parse('enum Sex { male female }');

      final out = KotlinSerializer(g, importPrefix: '', generateJsonMethods: true)
          .serializeEnumDefinition(g.enums['Sex']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, anyElement(contains('MALE')));
      expect(lines, anyElement(contains('FEMALE')));
      expect(lines, anyElement(contains('"male"')));
      expect(lines, anyElement(contains('"female"')));
    });
  });

  // ── TypeScript ───────────────────────────────────────────────────────────

  group('TypeScript — NamingConvention.typescript', () {
    test('enum lowerCase value: codeName is PascalCase, wire name preserved', () {
      final g = GLParser(
        naming: NamingConvention.typescript,
        reservedWords: const {},
        parameterReservedWords: typescriptParameterReservedWords,
      );
      g.parse('enum Sex { male female }');

      final out = TypeScriptSerializer(g, importPrefix: '')
          .serializeEnumDefinition(g.enums['Sex']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, anyElement(contains('Male')));
      expect(lines, anyElement(contains('Female')));
      expect(lines, anyElement(contains("'male'")));
      expect(lines, anyElement(contains("'female'")));
    });

    test('SCREAMING_SNAKE field: identifier is lowerCamelCase, JSON key is original', () {
      final g = GLParser(
        naming: NamingConvention.typescript,
        reservedWords: const {},
        parameterReservedWords: typescriptParameterReservedWords,
      );
      g.parse('''
        type Company { MY_FIELD: String }
      ''');

      final out = TypeScriptSerializer(g, importPrefix: '')
          .serializeTypeDefinition(g.types['Company']!);
      final lines = out.split('\n').map((l) => l.trim()).toList();

      expect(lines, anyElement(contains('myField')));
      expect(lines, anyElement(contains('"MY_FIELD"')));
    });
  });
}
