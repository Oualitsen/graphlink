import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  final typeMapping = {
    "ID": "String",
    "String": "String",
    "Float": "Double",
    "Int": "Integer",
    "Boolean": "Boolean",
    "Null": "null",
    "Long": "Long"
  };

  test("handle repositories", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text = File("test/server/repository/repository_test.graphql")
        .readAsStringSync();

    g.parse(text);

    expect(g.interfaces.keys, contains("Entity"));
    expect(g.interfaces.keys, hasLength(1));
    expect(
        g.repositories.keys, containsAll(["UserRepository", "CarRepository"]));
    expect(g.repositories, hasLength(2));
  });

  test("external types/inputs serialization", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/server/repository/repository_test_external_types.graphql")
            .readAsStringSync();

    g.parse(text);

    var type = g.scalars["ExternalUser"]!;
    var input = g.scalars["Pagebale"]!;

    expect(type.getDirectiveByName(glSkipOnClient), isNotNull);
    expect(type.getDirectiveByName(glSkipOnServer), isNotNull);

    expect(input.getDirectiveByName(glSkipOnClient), isNotNull);
    expect(input.getDirectiveByName(glSkipOnServer), isNotNull);

    var userRepository = g.repositories["UserRepository"]!;

    var serializer = SpringServerSerializer(g);
    var result = serializer.serializeRepository(userRepository, "com.myorg");
    expect(
        result,
        stringContainsInOrder([
          "List<com.mycompany.ExternalUser> findAll(org.springframework.data.domain.Pageable pagebale);"
        ]));
  });

  test("check type == null", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @glRepository(glIdType: "id") {
          _: String
        }
        """;

    expect(
      () => g.parse(text),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              'glType is required on @glRepository directive line: 4 column: 35'),
        ),
      ),
    );
  });

  test("check id = null", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: String!
        }
        interface UserRepository @glRepository(glType: "User") {
          _: String
        }
        """;

    expect(
      () => g.parse(text),
      throwsA(
        isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("glIdType is required on @glRepository directive"),
        ),
      ),
    );
  });

  test("should serialize directives on methods", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    const text = """
      directive @gqQuery(
        value: String
        count: Boolean
        exists: Boolean
        delete: Boolean
        fields: String
        sort: String
        glClass: String = "@Query"
        glImport: String = "org.springframework.data.mongodb.repository.Query"
        glOnClient: Boolean = false
        glOnServer: Boolean = true
        glAnnotation: Boolean = true
    ) on FIELD_DEFINITION

        type User {
          id: ID!
        }
        interface UserRepository @glRepository(glIdType: "id", glType: "User") {
          findUsers: [User!]! @gqQuery(value: "select * from User")
        }
        """;
    g.parse(text);

    var springSerializer = SpringServerSerializer(g);
    var userRepo = g.repositories["UserRepository"]!;
    var repoSerial = springSerializer.serializeRepository(userRepo, "myorg");
    expect(
        repoSerial.split("\n").map((e) => e.trim()),
        containsAll([
          '@Query(value = "select * from User")',
          'List<User> findUsers();'
        ]));
  });
}
