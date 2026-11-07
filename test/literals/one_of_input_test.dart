import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  input Pet @oneOf { cat: String dog: Int }
  input Plain { cat: String dog: Int }
  type Query { f(p: Pet, q: Plain): String }
''';

GLParser _parse() => GLParser()..parse(_schema);

void main() {
  test('an input declared with @oneOf is flagged', () {
    final g = _parse();
    expect(g.inputs['Pet']!.isOneOf, isTrue);
    expect(g.inputs['Plain']!.isOneOf, isFalse);
  });

  group('a oneOf input leaves its unused members out of the payload', () {
    String out(String Function(GLParser g, String name) emit, String name) => emit(_parse(), name);

    test('Dart', () {
      String emit(GLParser g, String n) => DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains("if (cat != null) 'cat': cat"));
      expect(out(emit, 'Pet'), contains("if (dog != null) 'dog': dog"));
      expect(out(emit, 'Plain'), contains("'cat': cat,"));
    });

    test('Java', () {
      String emit(GLParser g, String n) => JavaSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('if (cat != null)'));
      expect(out(emit, 'Pet'), contains('glMap__.put("cat", cat);'));
      expect(out(emit, 'Plain'), isNot(contains('if (cat != null)')));
    });

    test('Kotlin', () {
      String emit(GLParser g, String n) => KotlinSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('.filterValues { it != null }'));
      expect(out(emit, 'Plain'), isNot(contains('filterValues')));
    });

    test('TypeScript', () {
      String emit(GLParser g, String n) => TypeScriptSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('.filter(([, v]) => v != null)'));
      expect(out(emit, 'Plain'), isNot(contains('.filter(')));
    });

    test('Swift', () {
      String emit(GLParser g, String n) => SwiftSerializer(g, importPrefix: 'G').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('.filter { \$0.value != nil }'));
      expect(out(emit, 'Plain'), isNot(contains('.filter')));
    });

    test('Go', () {
      String emit(GLParser g, String n) => GoSerializer(g, packageName: 'generated').serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('if v.cat != nil {'));
      expect(out(emit, 'Plain'), isNot(contains('if v.cat != nil {')));
    });

    test('Python', () {
      String emit(GLParser g, String n) => PythonSerializer(g).serializeInputDefinition(g.inputs[n]!);
      expect(out(emit, 'Pet'), contains('.items() if v is not None}'));
      expect(out(emit, 'Plain'), isNot(contains('if v is not None')));
    });
  });
}
