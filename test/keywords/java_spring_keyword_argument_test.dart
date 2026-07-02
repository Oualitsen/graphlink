import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// Generated Spring resolver/service code must sanitize argument names that are
/// Java keywords (`default` -> `default_`). Because Spring binds `@Argument` by
/// the parameter name, the binding must be pinned to the original wire name via
/// `@Argument(name = "default")`.
void main() {
  const schema = '''
    type Query { getCar(default: ID!): Car! }
    type Car {
      id: ID!
      related(default: Int): [Car] @glSkipOnServer(batch: false)
    }
  ''';

  GLParser parser() => GLParser(
        reservedWords: javaReservedWords,
        mode: CodeGenerationMode.server,
      )..parse(schema);

  String controllers(GLParser g, JavaSpringServerSerializer ser) =>
      g.controllers.values.map(ser.serializeController).join('\n');
  String services(GLParser g, JavaSpringServerSerializer ser) =>
      g.services.values.map(ser.serializeService).join('\n');

  test("top-level query arg: param sanitized, @Argument pinned to wire name",
      () {
    final g = parser();
    final ser = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    expect(ctrls, contains('@Argument(name = "default") String default_'));
    expect(ctrls, contains('carService.getCar(default_)'));
    expect(svcs, contains('Car getCar(String default_);'));
    // never an unsanitized identifier
    expect(ctrls, isNot(contains('String default)')));
  });

  test("type-field (schema mapping) arg: param sanitized, @Argument pinned", () {
    final g = parser();
    final ser = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    expect(ctrls,
        contains('@Argument(name = "default") Integer default_'));
    expect(ctrls, contains('carRelated(Car.fromJson(value), default_)'));
    expect(svcs, contains('carRelated(Car value, Integer default_);'));
  });
}
