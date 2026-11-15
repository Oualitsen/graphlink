import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java/java_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_spring_server_serializer.dart';
import 'package:test/test.dart';

String _schema(String type) => '''
  type $type { id: ID! name: String! }
  interface ${type}Repository @glRepository(glType: "$type", glIdType: "String") {
    _: Int
  }
  type Query { noop: String }
''';

GLParser _parse(Set<String> reserved, String type) =>
    GLParser(mode: CodeGenerationMode.server, reservedTypeNames: reserved)..parse(_schema(type));

void main() {
  group('@glRepository on a type whose generated name differs from its schema name', () {
    test('Java repository uses the renamed type', () {
      final g = _parse(javaReservedTypeNames, 'Supplier');
      final out = JavaSpringServerSerializer(g, packageName: 'com.example').serializeRepository(g.repositories['SupplierRepository']!);
      expect(out, contains('JpaRepository<Supplier_, String>'));
      expect(out, isNot(contains('JpaRepository<Supplier,')));
    });

    test('Kotlin repository uses the renamed type', () {
      final g = _parse(kotlinReservedTypeNames, 'Result');
      final out = KotlinSpringServerSerializer(g, packageName: 'com.example').serializeRepository(g.repositories['ResultRepository']!);
      expect(out, contains('JpaRepository<Result_, String>'));
    });
  });
}
