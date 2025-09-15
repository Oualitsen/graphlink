import 'dart:io';

import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/server/repository/repository_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);

    expect(g.interfaces.keys, contains("Entity"));
    expect(g.interfaces.keys, hasLength(1));
    expect(g.repositories.keys, containsAll(["UserRepository", "CarRepository"]));
    expect(g.repositories, hasLength(2));
  });

  test("external types/inputs serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/server/repository/repository_test_external_types.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var type = g.scalars["ExternalUser"]!;
    var input = g.scalars["Pagebale"]!;

    expect(type.getDirectiveByName(gqSkipOnClient), isNotNull);
    expect(type.getDirectiveByName(gqSkipOnServer), isNotNull);

    expect(input.getDirectiveByName(gqSkipOnClient), isNotNull);
    expect(input.getDirectiveByName(gqSkipOnServer), isNotNull);

    var userRepository = g.repositories["UserRepository"]!;

    var serializer = SpringServerSerializer(g);
    var result = serializer.serializeRepository(userRepository, "com.myorg");
    expect(
        result,
        stringContainsInOrder(
            ["List<com.mycompany.ExternalUser> findAll(final org.springframework.data.domain.Pageable pagebale);"]));
  });

  test("check type == null", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @gqRepository(gqTypeId: "id") {
          _: String
        }
        """;
    var parser = g.buildFrom(g.fullGrammar().end());
    expect(
      () => parser.parse(text),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains('gqType is required on @gqRepository directive line: 4 column: 35'),
        ),
      ),
    );
  });

  test("check id = null", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: String!
        }
        interface UserRepository @gqRepository(gqType: "User") {
          _: String
        }
        """;
    var parser = g.buildFrom(g.fullGrammar().end());
    expect(
      () => parser.parse(text),
      throwsA(
        isA<ParseException>().having(
          (e) => e.message,
          'message',
          contains("gqIdType is required on @gqRepository directive"),
        ),
      ),
    );
  });
}
