import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// priority is intentionally non-null (Priority!) to verify that a non-null
// field with a default is not widened to nullable in any language.
// tags tests list literal generation.
const _schema = '''
enum Priority { LOW MEDIUM HIGH }

input CreateTaskInput {
  title: String!
  priority: Priority! = MEDIUM
  score: Int = 10
  done: Boolean = false
  label: String = "untitled"
  tags: [String] = ["dart", "graphql"]
}
''';

void main() {
  group('Dart — serializeDefaultLiteral', () {
    late GLParser g;
    late DartSerializer s;

    setUp(() {
      g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
      g.parse(_schema);
      s = DartSerializer(g, importPrefix: '');
    });

    test('generates correct constructor defaults for CreateTaskInput', () {
      final out = s.serializeInputDefinition(g.inputs['CreateTaskInput']!);
      print('=== Dart CreateTaskInput ===\n$out');

      expect(out, contains('required this.title'));
      // non-null with default: not required, no ? widening
      expect(out, contains('this.priority = Priority.MEDIUM'));
      expect(out, isNot(contains('Priority?')));
      expect(out, contains('this.score = 10'));
      expect(out, contains('this.done = false'));
      expect(out, contains("this.label = 'untitled'"));
      expect(out, contains("this.tags = const ['dart', 'graphql']"));
    });
  });

  group('Kotlin — serializeDefaultLiteral', () {
    late GLParser g;
    late KotlinSerializer s;

    setUp(() {
      g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
      g.parse(_schema);
      s = KotlinSerializer(g, importPrefix: '');
    });

    test('generates correct constructor defaults for CreateTaskInput', () {
      final out = s.serializeInputDefinition(g.inputs['CreateTaskInput']!);
      print('=== Kotlin CreateTaskInput ===\n$out');

      // non-null with default: stays non-null, gets literal
      expect(out, contains('priority: Priority = Priority.MEDIUM'));
      expect(out, isNot(contains('Priority?')));
      // nullable with default
      expect(out, contains('score: Int? = 10'));
      expect(out, contains('done: Boolean? = false'));
      expect(out, contains('label: String? = "untitled"'));
      expect(out, contains('tags: List<String?>? = listOf("dart", "graphql")'));
    });
  });

  group('TypeScript — serializeDefaultLiteral', () {
    late GLParser g;
    late TypeScriptSerializer s;

    setUp(() {
      g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
      g.parse(_schema);
      s = TypeScriptSerializer(g, importPrefix: '');
    });

    test('generates correct optional fields for CreateTaskInput', () {
      final out = s.serializeInputDefinition(g.inputs['CreateTaskInput']!);
      print('=== TypeScript CreateTaskInput ===\n$out');

      expect(out, contains('title: string'));
      // non-null with default: no ? widening
      expect(out, contains('priority: Priority'));
      expect(out, isNot(contains('priority?: Priority')));
      // nullable with default: gets ?
      expect(out, contains('score?: number'));
      expect(out, contains('done?: boolean'));
      expect(out, contains('label?: string'));
      // companion const
      expect(out, contains('export const defaultCreateTaskInput: Partial<CreateTaskInput>'));
      expect(out, contains('priority: Priority.MEDIUM'));
      expect(out, contains('score: 10'));
      expect(out, contains('done: false'));
      expect(out, contains('label: "untitled"'));
      expect(out, contains('tags: ["dart", "graphql"]'));
    });
  });

  group('Java — serializeDefaultLiteral', () {
    late GLParser g;
    late JavaSerializer s;

    setUp(() {
      g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client);
      g.parse(_schema);
      s = JavaSerializer(g, importPrefix: '');
    });

    test('generates correct constructor defaults for CreateTaskInput', () {
      final out = s.serializeInputDefinition(g.inputs['CreateTaskInput']!);
      print('=== Java CreateTaskInput ===\n$out');

      // Fields are final — defaults go in the constructor, not field initializers.
      expect(out, contains('Priority priority'));
      expect(out, isNot(contains('Priority priority =')));
      // Constructor null-coalescing applies defaults.
      expect(out, contains('this.priority = priority != null ? priority : Priority.MEDIUM'));
      expect(out, contains('this.score = score != null ? score : 10'));
      expect(out, contains('this.done = done != null ? done : false'));
      expect(out, contains('this.label = label != null ? label : "untitled"'));
      expect(out, contains('Arrays.asList("dart", "graphql")'));
    });
  });
}
