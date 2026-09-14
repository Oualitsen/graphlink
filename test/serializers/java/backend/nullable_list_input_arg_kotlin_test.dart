import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/kotlin_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test('mutation with nullable list of input argument serializes controller (Kotlin)',
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

    final serializer = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrl = g.controllers['UpdateItemsServiceController']!;
    final result = serializer.serializeController(ctrl);

    // The safe cast + safe call already short-circuits to null for a null
    // list argument, so no separate null guard is needed (unlike Java's
    // stream()-based conversion, which required an explicit null check).
    expect(result, contains('(itemsAsMap as? List<*>)?.map'));
  });

  test('mutation with nullable list of nullable list of input argument serializes controller (Kotlin)',
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

    final serializer = KotlinSpringServerSerializer(g, packageName: 'com.example');
    final ctrl = g.controllers['UpdateMatrixServiceController']!;
    final result = serializer.serializeController(ctrl);

    // Every level of nesting uses a safe cast + safe call, so a null outer
    // list, a null inner list, and a null element all short-circuit cleanly.
    expect(result, contains('(itemsAsMap as? List<*>)?.map'));
    expect(result, contains('(__gl_m0__ as? List<*>)?.map'));
  });
}
