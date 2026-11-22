import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/swift/swift_serializer.dart';
import 'package:test/test.dart';

String _schemaFor(String t) => '''
  type $t {
    id: ID!
    message: String!
  }

  input ErrorInput @glMapsTo(type: "$t") {
    message: String!
  }

  type Query { noop: String }
''';

GLParser _parse(Set<String> reserved, CodeGenerationMode mode, [String t = 'Error']) =>
    GLParser(mode: mode, reservedTypeNames: reserved)..parse(_schemaFor(t));

void main() {
  group('@glMapsTo to a target whose code name differs from its schema name', () {
    test('Java', () {
      final g = _parse(javaReservedTypeNames, CodeGenerationMode.server);
      final out = JavaSerializer(g, importPrefix: '', typesAsRecords: true)
          .serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('toError_'));
    });

    test('Kotlin', () {
      final g = _parse(kotlinReservedTypeNames, CodeGenerationMode.server);
      final out = KotlinSerializer(g, importPrefix: '')
          .serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('message = message'));
    });

    test('Swift', () {
      final g = _parse(swiftReservedTypeNames, CodeGenerationMode.server);
      final out = SwiftSerializer(g, importPrefix: '')
          .serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('message: message'));
    });

    test('Dart', () {
      final g = _parse(dartReservedTypeNames, CodeGenerationMode.server);
      final out = DartSerializer(g, importPrefix: '').serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('Error_'));
      expect(out, contains('message: message'));
    });

    test('Python', () {
      final g = _parse(pythonReservedTypeNames, CodeGenerationMode.server, 'Exception');
      final out = PythonSerializer(g).serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('Exception_'));
      expect(out, contains('message=self.message'));
    });

    test('Go', () {
      final g = _parse(const {}, CodeGenerationMode.server);
      final out = GoSerializer(g).serializeInputDefinition(g.inputs['ErrorInput']!);
      expect(out, contains('message'));
    });
  });
}
