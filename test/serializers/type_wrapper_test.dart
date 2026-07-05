import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  type Dog {
    id: ID!
    name: String!
  }
''';

const _wrapper = 'Flux';
const _wrapperImport = 'reactor.core.publisher.Flux';

void main() {
  group('GLType.wrapper', () {
    test('wraps a plain type in Java/Kotlin/TypeScript/Dart', () {
      final g = GLParser();
      g.parse(_schema);

      final type = GLType('Dog'.toToken(), false, wrapper: _wrapper, wrapperImport: _wrapperImport);

      expect(JavaSerializer(g, importPrefix: '').serializeType(type), 'Flux<Dog>');
      expect(KotlinSerializer(g, importPrefix: '').serializeType(type), 'Flux<Dog>');
      expect(TypeScriptSerializer(g, importPrefix: '').serializeType(type), 'Flux<Dog>');
      expect(DartSerializer(g, importPrefix: '').serializeType(type), 'Flux<Dog>');
    });

    test('wraps a List<Dog> in Java/Kotlin/TypeScript/Dart', () {
      final g = GLParser();
      g.parse(_schema);

      final type = GLListType(GLType('Dog'.toToken(), false), false,
          wrapper: _wrapper, wrapperImport: _wrapperImport);

      expect(JavaSerializer(g, importPrefix: '').serializeType(type), 'Flux<List<Dog>>');
      expect(KotlinSerializer(g, importPrefix: '').serializeType(type), 'Flux<List<Dog>>');
      expect(TypeScriptSerializer(g, importPrefix: '').serializeType(type), 'Flux<Dog[]>');
      expect(DartSerializer(g, importPrefix: '').serializeType(type), 'Flux<List<Dog>>');
    });

    test('wraps a Map<String, Dog> in Java/Kotlin/TypeScript/Dart', () {
      final g = GLParser();
      g.parse(_schema);

      final type = GLMapType(
        GLType('String'.toToken(), false),
        GLType('Dog'.toToken(), false),
        false,
        wrapper: _wrapper,
        wrapperImport: _wrapperImport,
      );

      expect(JavaSerializer(g, importPrefix: '').serializeType(type), 'Flux<Map<String, Dog>>');
      expect(KotlinSerializer(g, importPrefix: '').serializeType(type), 'Flux<Map<String, Dog>>');
      expect(TypeScriptSerializer(g, importPrefix: '').serializeType(type), 'Flux<Map<string, Dog>>');
      expect(DartSerializer(g, importPrefix: '').serializeType(type), 'Flux<Map<String, Dog>>');
    });

    test('registers wrapperImport on the referenced type token (Java)', () {
      final g = GLParser();
      g.parse(_schema);

      final type = GLType('Dog'.toToken(), false, wrapper: _wrapper, wrapperImport: _wrapperImport);
      JavaSerializer(g, importPrefix: '').serializeType(type);

      final dogImports = g.getTypeByName('Dog')!.getImports(g);
      expect(dogImports, contains(_wrapperImport));
    });
  });
}
