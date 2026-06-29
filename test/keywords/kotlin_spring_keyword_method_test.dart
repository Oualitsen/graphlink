import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/kotlin_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A top-level operation (resolver) may be named after a Kotlin hard keyword
/// (`return`, `when`). The generated controller/service *method* must be
/// sanitized (`return_`), but Spring binds `@QueryMapping` by method name, so
/// the binding is pinned to the wire name via `@QueryMapping(name = "return")`.
void main() {
  const schema = '''
    type Query { return(id: ID!): Car! }
    type Mutation { when(id: ID!): Boolean! }
    type Car { id: ID! }
  ''';

  GLParser parser() => GLParser(
        reservedWords: kotlinReservedWords,
        mode: CodeGenerationMode.server,
      )..parse(schema);

  String controllers(GLParser g, KotlinSpringServerSerializer ser) =>
      g.controllers.values.map(ser.serializeController).join('\n');
  String services(GLParser g, KotlinSpringServerSerializer ser) =>
      g.services.values.map(ser.serializeService).join('\n');

  test("keyword query: method sanitized, @QueryMapping pinned to wire name", () {
    final g = parser();
    final ser = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    expect(ctrls, contains('@QueryMapping(name = "return")'));
    expect(ctrls, contains('return_('));
    expect(ctrls, contains('.return_('));
    expect(svcs, contains('return_('));
    expect(ctrls, isNot(contains('fun return(')));
  });

  test("keyword mutation: method sanitized, @MutationMapping pinned", () {
    final g = parser();
    final ser = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);

    expect(ctrls, contains('@MutationMapping(name = "when")'));
    expect(ctrls, contains('when_('));
    expect(ctrls, isNot(contains('fun when(')));
  });
}
