import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Parsing + getter tests
// ---------------------------------------------------------------------------

void main() {
  group('@deprecated parsing', () {
    test('accepted on field', () {
      final g = GLParser();
      const schema = '''
type Query { item: String @deprecated }
type Foo { name: String @deprecated(reason: "use bar instead") }
''';
      expect(() => g.parse(schema), returnsNormally);
      final foo = g.types['Foo']!;
      expect(foo.fields.first.isDeprecated, isTrue);
      expect(foo.fields.first.deprecationReason, 'use bar instead');
    });

    test('accepted on enum value', () {
      final g = GLParser();
      const schema = '''
enum Status { ACTIVE INACTIVE @deprecated(reason: "no longer valid") }
''';
      expect(() => g.parse(schema), returnsNormally);
      final status = g.enums['Status']!;
      final inactive = status.values.firstWhere((v) => v.token == 'INACTIVE');
      expect(inactive.isDeprecated, isTrue);
      expect(inactive.deprecationReason, 'no longer valid');
    });

    test('default reason when none provided', () {
      final g = GLParser();
      const schema = 'enum Status { ACTIVE INACTIVE @deprecated }';
      g.parse(schema);
      final inactive =
          g.enums['Status']!.values.firstWhere((v) => v.token == 'INACTIVE');
      expect(inactive.isDeprecated, isTrue);
      expect(inactive.deprecationReason, 'No longer supported');
    });

    test('not deprecated when directive absent', () {
      final g = GLParser();
      const schema = 'type Foo { name: String }';
      g.parse(schema);
      expect(g.types['Foo']!.fields.first.isDeprecated, isFalse);
      expect(g.types['Foo']!.fields.first.deprecationReason, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Dart
  // ---------------------------------------------------------------------------

  group('Dart', () {
    test('field emits @Deprecated annotation', () {
      final g = GLParser();
      g.parse('type Foo { name: String! @deprecated(reason: "use bar") }');
      final ser = DartSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains("@Deprecated('use bar')"));
      expect(result, contains('final String name;'));
    });

    test('enum value emits @Deprecated inline', () {
      final g = GLParser();
      g.parse('enum Status { ACTIVE INACTIVE @deprecated(reason: "gone") }');
      final ser = DartSerializer(g, importPrefix: '');
      final result = ser.serializeEnumDefinition(g.enums['Status']!);
      expect(result, contains("@Deprecated('gone') INACTIVE"));
    });

    test('no output when not deprecated', () {
      final g = GLParser();
      g.parse('type Foo { name: String }');
      final ser = DartSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, isNot(contains('@Deprecated')));
    });

    test('escapes single quote in reason', () {
      final g = GLParser();
      // Use a GraphQL string with an escaped single quote inside the reason
      g.parse("type Foo { name: String @deprecated(reason: \"it's deprecated\") }");
      final ser = DartSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains(r"@Deprecated('it\'s deprecated')"));
    });
  });

  // ---------------------------------------------------------------------------
  // Java
  // ---------------------------------------------------------------------------

  group('Java', () {
    test('field emits @Deprecated with Javadoc reason', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated(reason: "use bar") }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('@deprecated use bar'));
      expect(result, contains('@Deprecated'));
      expect(result, contains('private'));
    });

    test('field emits default Javadoc reason when no reason provided', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('@deprecated No longer supported'));
      expect(result, contains('@Deprecated'));
      expect(result, contains('private'));
    });

    test('enum value emits @Deprecated inline with Javadoc', () {
      final g = GLParser();
      g.parse('enum Status { ACTIVE INACTIVE @deprecated(reason: "gone") }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeEnumDefinition(g.enums['Status']!);
      expect(result, contains('@deprecated gone'));
      expect(result, contains('@Deprecated INACTIVE'));
    });

    test('no output when not deprecated', () {
      final g = GLParser();
      g.parse('type Foo { name: String }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, isNot(contains('@Deprecated')));
    });

    test('reason with special characters is included in Javadoc', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated(reason: "use bar instead") }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('/** @deprecated use bar instead */'));
      expect(result, contains('@Deprecated'));
      expect(result, contains('private'));
    });

    test('escapes */ in reason', () {
      final g = GLParser();
      g.parse(r'type Foo { name: String @deprecated(reason: "use */foo/* instead") }');
      final ser = JavaSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('*\\/foo/*'));
    });
  });

  // ---------------------------------------------------------------------------
  // Kotlin
  // ---------------------------------------------------------------------------

  group('Kotlin', () {
    test('field emits @Deprecated annotation', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated(reason: "use bar") }');
      final ser = KotlinSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('@Deprecated("use bar")'));
      expect(result, contains('val name: String'));
    });

    test('enum value emits @Deprecated inline', () {
      final g = GLParser();
      g.parse('enum Status { ACTIVE INACTIVE @deprecated(reason: "gone") }');
      final ser = KotlinSerializer(g, importPrefix: '');
      final result = ser.serializeEnumDefinition(g.enums['Status']!);
      expect(result, contains('@Deprecated("gone") INACTIVE'));
    });

    test('no output when not deprecated', () {
      final g = GLParser();
      g.parse('type Foo { name: String }');
      final ser = KotlinSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, isNot(contains('@Deprecated')));
    });

    test('escapes double quote in reason', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated(reason: "use \\"new\\" instead") }');
      final ser = KotlinSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      // escapeForStringLiteral escapes " → \" for Kotlin string literal
      expect(result, contains(r'@Deprecated("use \"new\" instead")'));
    });
  });

  // ---------------------------------------------------------------------------
  // TypeScript
  // ---------------------------------------------------------------------------

  group('TypeScript', () {
    test('field emits JSDoc @deprecated comment', () {
      final g = GLParser();
      g.parse('type Foo { name: String @deprecated(reason: "use bar") }');
      final ser = TypeScriptSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains('/** @deprecated use bar */'));
      expect(result, contains('readonly name: string'));
    });

    test('enum value emits JSDoc @deprecated comment', () {
      final g = GLParser();
      g.parse('enum Status { ACTIVE INACTIVE @deprecated(reason: "gone") }');
      final ser = TypeScriptSerializer(g, importPrefix: '');
      final result = ser.serializeEnumDefinition(g.enums['Status']!);
      expect(result, contains('/** @deprecated gone */'));
      expect(result, contains('INACTIVE'));
    });

    test('no output when not deprecated', () {
      final g = GLParser();
      g.parse('type Foo { name: String }');
      final ser = TypeScriptSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, isNot(contains('@deprecated')));
    });

    test('escapes star-slash in reason', () {
      final g = GLParser();
      g.parse(r'type Foo { name: String @deprecated(reason: "use */foo/* instead") }');
      final ser = TypeScriptSerializer(g, importPrefix: '');
      final result = ser.serializeTypeDefinition(g.types['Foo']!);
      expect(result, contains(r'/** @deprecated use *\/foo/* instead */'));
    });
  });
}
