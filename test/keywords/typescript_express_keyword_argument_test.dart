import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

/// In TypeScript, reserved words are legal as object-property names (so fields
/// and JSON keys are NOT sanitized), but they are ILLEGAL as parameter binding
/// identifiers. A generated Express/Apollo resolver whose argument is named
/// after a reserved word (`return`) must therefore sanitize the *parameter*
/// (`return_`) while keeping the original `return` as the GraphQL wire name
/// (the destructuring key from the `args` object).
void main() {
  ExpressApolloServerSerializer serializer(String schema) {
    final parser = GLParser(
      mode: CodeGenerationMode.server,
      parameterReservedWords: typescriptParameterReservedWords,
    )..parse(schema);
    return ExpressApolloServerSerializer(
      parser,
      TypeScriptSerializer(parser, importPrefix: ''),
      ExpressApolloServerConfig(),
    );
  }

  const schema = '''
    type Query { getCar(return: ID!): Car! }
    type Car { id: ID! }
  ''';

  test("service interface param is sanitized, not a bare keyword", () {
    final ser = serializer(schema);
    final out =
        ser.grammar.services.values.map(ser.serializeService).join('\n');

    // parameter binding identifier must be safe.
    expect(out, contains('return_:'));
    // never an illegal bare `return` parameter.
    expect(out, isNot(contains('getCar(return:')));
  });

  test("resolver destructures wire name into a safe identifier and calls it",
      () {
    final ser = serializer(schema);
    final out = ser.serializeResolvers().join('\n');

    // destructure renames the wire property to the safe local:
    //   const { return: return_ } = args
    expect(out, contains('return: return_'));
    // the call passes the safe identifier, never a bare `return`.
    expect(out, isNot(contains('(return,')));
    expect(out, isNot(contains('(return)')));
  });

  group('type-field (schema mapping) argument', () {
    // A non-root type field with an argument generates a schema-mapping resolver
    // (`Car.related`). Its argument must be sanitized in the service method, the
    // destructuring, and the call — same wire/code split as a root resolver.
    const mappingSchema = '''
      type Query { car(id: ID!): Car }
      type Car {
        id: ID!
        related(return: Int): [Car] @glSkipOnServer(batch: false)
      }
    ''';

    test("service mapping method param is sanitized, not a bare keyword", () {
      final ser = serializer(mappingSchema);
      final out =
          ser.grammar.services.values.map(ser.serializeService).join('\n');
    print(out);
      // sanitized parameter on the mapping method.
      expect(out, contains('return_: number'));
      // never an illegal bare `return` parameter.
      expect(out, isNot(contains('return: number')));
    });

    test("type mapping resolver destructures + calls with the safe identifier",
        () {
      final ser = serializer(mappingSchema);
      
      final out = ser.serializeResolvers().join('\n');
      print(out);
      // destructure renames the wire property; call uses the safe identifier.
      expect(out, contains('{ return: return_, value }'));
      expect(out, contains('carRelated(parent, return_, value, context)'));
      // never a bare `return` binding/reference.

      expect(out, isNot(contains('{ return }')));
      expect(out, isNot(contains('parent, return,')));
    });
  });
}
