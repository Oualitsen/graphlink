import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

void main() {
  test('mutation with nullable list of input argument serializes resolver (TypeScript)',
      () {
    const schema = '''
      type Query {
        getUser(id: ID!): User!
      }

      type Mutation {
        updateItems(items: [ItemInput!]): Boolean
      }

      input ItemInput {
        id: ID!
        name: String
      }

      type User {
        id: ID!
        name: String
      }
    ''';

    final parser = GLParser(mode: CodeGenerationMode.server)..parse(schema);
    final serializer = ExpressApolloServerSerializer(
      parser,
      TypeScriptSerializer(parser, importPrefix: ''),
      ExpressApolloServerConfig(),
    );

    final serviceOut =
        serializer.grammar.services.values.map(serializer.serializeService).join('\n');
    final resolverOut = serializer.serializeResolvers().join('\n');

    // No fromJson-style deserialization step exists for TS/Apollo resolvers —
    // GraphQL-JS already hands the resolver a plain object matching the input
    // shape, so a nullable list argument is passed straight through with no
    // unguarded call to break (unlike the Java stream()-based conversion).
    expect(serviceOut, contains('updateItems(items: ItemInput[] | null): Promise<boolean | null>;'));
    expect(resolverOut, contains('return updateItemsService.updateItems(items);'));
  });

  test('mutation with nullable list of nullable list of input argument serializes resolver (TypeScript)',
      () {
    const schema = '''
      type Query {
        getUser(id: ID!): User!
      }

      type Mutation {
        updateMatrix(items: [[ItemInput]]): Boolean
      }

      input ItemInput {
        id: ID!
        name: String
      }

      type User {
        id: ID!
        name: String
      }
    ''';

    final parser = GLParser(mode: CodeGenerationMode.server)..parse(schema);
    final serializer = ExpressApolloServerSerializer(
      parser,
      TypeScriptSerializer(parser, importPrefix: ''),
      ExpressApolloServerConfig(),
    );

    final serviceOut =
        serializer.grammar.services.values.map(serializer.serializeService).join('\n');
    final resolverOut = serializer.serializeResolvers().join('\n');

    // Nesting depth changes only the TS type shape, never introduces a
    // deserialization call — still passed straight through unguarded.
    expect(serviceOut,
        contains('updateMatrix(items: ((ItemInput | null)[] | null)[] | null): Promise<boolean | null>;'));
    expect(resolverOut, contains('return updateMatrixService.updateMatrix(items);'));
  });
}
