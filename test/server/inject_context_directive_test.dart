import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

// @glInjectContext injects the request-context parameter into a single
// resolver method (Spring GraphQLContext, Apollo `context`), even when the
// global injectContext flag is off. It is OR'd with that global flag.
const _schema = '''
type Query {
  getCar(id: ID!): Car! @glInjectContext
  listCars: [Car!]!
}
type Car { id: ID! name: String! }
''';

void main() {
  group("Java Spring", () {
    JavaSpringServerSerializer serializer(GLParser g, {bool injectContext = false}) =>
        JavaSpringServerSerializer(g, packageName: "org", injectContext: injectContext);

    test("@glInjectContext injects GraphQLContext on that field only, flag off", () {
      final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
      final out = serializer(g).serializeService(g.services["CarService"]!);

      expect(out, contains("getCar(String id, GraphQLContext graphQLContext)"));
      expect(out, contains("listCars();"));
      expect(out, isNot(contains("listCars(GraphQLContext")));
    });

    test("global injectContext injects GraphQLContext into every method", () {
      final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server)..parse(_schema);
      final out = serializer(g, injectContext: true).serializeService(g.services["CarService"]!);

      expect(out, contains("getCar(String id, GraphQLContext graphQLContext)"));
      expect(out, contains("listCars(GraphQLContext graphQLContext)"));
    });
  });

  group("Apollo/Express", () {
    ExpressApolloServerSerializer serializer(GLParser g, {bool injectContext = false}) =>
        ExpressApolloServerSerializer(
          g,
          TypeScriptSerializer(g, importPrefix: ''),
          ExpressApolloServerConfig(injectContext: injectContext),
        );

    test("@glInjectContext adds context param to that field only, flag off", () {
      final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
      final out = g.services.values.map(serializer(g).serializeService).join('\n');

      expect(out, contains("getCar(id: string, context: GraphLinkContext)"));
      expect(out, contains("listCars(): Promise"));
      expect(out, isNot(contains("listCars(context")));
    });

    test("resolver passes context only for the annotated field", () {
      final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
      final out = serializer(g).serializeResolvers().join('\n');

      expect(out, contains("getCar: async (_, { id }, context) =>"));
      expect(out, contains(".getCar(id, context)"));
      // no context for the un-annotated field
      expect(out, contains("listCars: async (_, __) =>"));
      expect(out, contains(".listCars()"));
    });

    test("global injectContext adds context to every method", () {
      final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema);
      final out = g.services.values.map(serializer(g, injectContext: true).serializeService).join('\n');

      expect(out, contains("listCars(context: GraphLinkContext)"));
    });
  });
}
