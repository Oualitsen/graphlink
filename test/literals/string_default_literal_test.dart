import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

String _schema(String literal) => 'input In { s: String = $literal } type Query { f(i: In): String }';

String _emit(GLSerializer Function(GLParser) make, String literal) {
  final g = GLParser()..parse(_schema(literal));
  final field = g.inputs['In']!.fields.single;
  return make(g).serializeDefaultLiteral(field.type, field.initialValue);
}

void main() {
  group('a GraphQL string literal is decoded', () {
    test('escape sequences', () {
      expect(r'"a\"b\\c\/d\be\ff\ng\rh\ti"'.graphqlStringValue(), 'a"b\\c/d\be\ff\ng\rh\ti');
    });

    test('unicode escapes, including a surrogate pair', () {
      expect(r'"café 中 😀"'.graphqlStringValue(), 'café 中 😀');
    });

    test('a block string keeps its content and drops the common indentation', () {
      expect('"""\n  one\n    two\n  """'.graphqlStringValue(), 'one\n  two');
    });

    test('a block string only unescapes the triple quote', () {
      expect(r'"""a \""" b \n"""'.graphqlStringValue(), r'a """ b \n');
    });

    test('an enum value is returned untouched', () {
      expect('ACTIVE'.graphqlStringValue(), 'ACTIVE');
    });
  });

  group('the default of a string field is emitted as a literal that evaluates to the decoded value', () {
    const quoted = r'"a\"b\\c\nd$e"';
    const apostrophe = r'''"it's ${x} $$"''';

    test('Dart', () {
      DartSerializer make(GLParser g) => DartSerializer(g, importPrefix: '');
      expect(_emit(make, quoted), "'a\"b\\\\c\\nd\\\$e'");
      expect(_emit(make, apostrophe), r"'it\'s \${x} \$\$'");
    });

    test('TypeScript', () {
      TypeScriptSerializer make(GLParser g) => TypeScriptSerializer(g, importPrefix: '');
      expect(_emit(make, quoted), r'"a\"b\\c\nd$e"');
      expect(_emit(make, apostrophe), r'''"it's ${x} $$"''');
    });

    test('Java', () {
      JavaSerializer make(GLParser g) => JavaSerializer(g, importPrefix: '');
      expect(_emit(make, quoted), r'"a\"b\\c\nd$e"');
    });

    test('Kotlin', () {
      KotlinSerializer make(GLParser g) => KotlinSerializer(g, importPrefix: '');
      expect(_emit(make, quoted), r'"a\"b\\c\nd\$e"');
      expect(_emit(make, apostrophe), r'''"it's \${x} \$\$"''');
    });

    test('Swift', () {
      SwiftSerializer make(GLParser g) => SwiftSerializer(g, importPrefix: 'GraphLinkGenerated');
      expect(_emit(make, quoted), r'"a\"b\\c\nd$e"');
    });

    test('Go', () {
      GoSerializer make(GLParser g) => GoSerializer(g, packageName: 'generated');
      expect(_emit(make, quoted), r'Ptr[string]("a\"b\\c\nd$e")');
    });

    test('Python', () {
      PythonSerializer make(GLParser g) => PythonSerializer(g);
      expect(_emit(make, quoted), r'"a\"b\\c\nd$e"');
    });
  });

  group('the lexer keeps a string literal as written', () {
    Object? initial(String literal) =>
        (GLParser()..parse(_schema(literal))).inputs['In']!.fields.single.initialValue;

    test('an escaped quote keeps its backslash', () {
      expect(initial(r'"say \"hi\""'), r'"say \"hi\""');
    });

    test('a string ending in an escaped backslash terminates', () {
      expect(initial(r'"C:\\"'), r'"C:\\"');
      expect((initial(r'"C:\\"') as String).graphqlStringValue(), r'C:\');
    });

    test('an escaped backslash followed by an escaped quote', () {
      expect((initial(r'"a\\\"b"') as String).graphqlStringValue(), r'a\"b');
    });
  });

  test('a deprecation reason is decoded', () {
    final g = GLParser()
      ..parse(r'''type T { old: String @deprecated(reason: "gone \"soon\" \\ $x") } enum E { A @deprecated(reason: "no \"A\"") } type Query { t: T e: E }''');
    expect(g.types['T']!.fields.single.deprecationReason, r'gone "soon" \ $x');
    expect(g.enums['E']!.values.single.deprecationReason, 'no "A"');
  });
}
