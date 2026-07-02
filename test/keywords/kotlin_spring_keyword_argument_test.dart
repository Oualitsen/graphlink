import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/kotlin_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// Generated Kotlin Spring resolver/service code must sanitize argument names
/// that are Kotlin hard keywords (`object` -> `object_`). Spring binds
/// `@Argument` by parameter name, so the binding is pinned to the wire name via
/// `@Argument(name = "object")`.
void main() {
  const schema = '''
    type Query { getCar(object: ID!): Car! }
    type Car {
      id: ID!
      related(object: Int): [Car] @glSkipOnServer(batch: false)
    }
  ''';

  GLParser parser() => GLParser(
        reservedWords: kotlinReservedWords,
        mode: CodeGenerationMode.server,
      )..parse(schema);

  String controllers(GLParser g, KotlinSpringServerSerializer ser) =>
      g.controllers.values.map(ser.serializeController).join('\n');
  String services(GLParser g, KotlinSpringServerSerializer ser) =>
      g.services.values.map(ser.serializeService).join('\n');

  test("top-level query arg: param sanitized, @Argument pinned to wire name",
      () {
    final g = parser();
    final ser = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    expect(ctrls, contains('@Argument(name = "object") object_: String'));
    expect(ctrls, contains('carService.getCar(object_)'));
    expect(svcs, contains('suspend fun getCar(object_: String): Car'));
  });

  test("type-field (schema mapping) arg: param sanitized, @Argument pinned", () {
    final g = parser();
    final ser = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    expect(ctrls, contains('@Argument(name = "object") object_: Int?'));
    expect(ctrls, contains('carSchemaMappingsService.carRelated(Car.fromJson(value), object_)'));
    expect(svcs, contains('carRelated(value: Car, object_: Int?)'));
  });
}
