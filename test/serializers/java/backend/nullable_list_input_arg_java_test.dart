import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('mutation with nullable list of input argument serializes controller',
      () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);

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

    g.parse(schema);

    final serializer = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrl = g.controllers['UpdateItemsServiceController']!;
    final result = serializer.serializeController(ctrl);

    expect(result, contains('itemsAsMap == null ? null : itemsAsMap.stream()'));
  });

  test('mutation with nullable list of nullable list of input argument serializes controller',
      () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);

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

    g.parse(schema);

    final serializer = JavaSpringServerSerializer(g, packageName: 'com.example');
    final ctrl = g.controllers['UpdateMatrixServiceController']!;
    final result = serializer.serializeController(ctrl);

    // Outer list null-guarded before the outer stream() call, and each inner
    // list null-guarded before its own stream() call.
    expect(result, contains('itemsAsMap == null ? null : itemsAsMap.stream()'));
    expect(result, contains('__gl_m0__ == null ? null : __gl_m0__.stream()'));
  });
}
