import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';

/// A top-level operation (resolver) may be named after a Java keyword
/// (`return`). The generated controller/service *method* must be sanitized
/// (`return_`), but Spring binds `@QueryMapping` by method name, so the binding
/// must be pinned to the original wire name via `@QueryMapping(name = "return")`.
void main() {
  const schema = '''
    type Query { return(id: ID!): Car! }
    type Mutation { import(id: ID!): Boolean! }
    type Car { id: ID! }
  ''';

  GLParser parser() => GLParser(
        reservedWords: javaReservedWords,
        mode: CodeGenerationMode.server,
      )..parse(schema);

  String controllers(GLParser g, JavaSpringServerSerializer ser) =>
      g.controllers.values.map(ser.serializeController).join('\n');
  String services(GLParser g, JavaSpringServerSerializer ser) =>
      g.services.values.map(ser.serializeService).join('\n');

  test("keyword query: method sanitized, @QueryMapping pinned to wire name", () {
    final g = parser();
    final ser = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);
    final svcs = services(g, ser);

    // controller method name sanitized + binding pinned to the wire name.
    expect(ctrls, contains('@QueryMapping(name = "return")'));
    expect(ctrls, contains('return_('));
    // service call uses the sanitized method name.
    expect(ctrls, contains('.return_('));
    // service interface declares the sanitized method.
    expect(svcs, contains('return_('));
    // never an illegal bare `return(` method.
    expect(ctrls, isNot(contains(' return(')));
  });

  test("keyword mutation: method sanitized, @MutationMapping pinned", () {
    final g = parser();
    final ser = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrls = controllers(g, ser);

    // `import` is a Java keyword -> method sanitized, binding pinned.
    expect(ctrls, contains('@MutationMapping(name = "import")'));
    expect(ctrls, contains('import_('));
    expect(ctrls, isNot(contains(' import(')));
  });
}
