import 'dart:io';

import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
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
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

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
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

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
    var result = serializer.serializeRepository(userRepository);
    expect(result, stringContainsInOrder(["java.util.List<com.mycompany.ExternalUser> findAll(final org.springframework.data.domain.Pageable pagebale);"]));
  });


  test("check type == null", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @gqRepository(id: "id") {
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
          contains('onType is required on @gqRepository directive'),
        ),
      ),
    );
  });

  test("check type = null but onType is not defined", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @gqRepository(id: "id", onType: "NOT_DEFINED") {
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
          contains("Type 'NOT_DEFINED' referenced by directive '@gqRepository' is not defined or skipped"),
        ),
      ),
    );
  });

  test("ID is consedered as an id if no annotation found", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @gqRepository(onType: "User") {
          _: String
        }
        """;
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });

  test("check id = null", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: String!
        }
        interface UserRepository @gqRepository(onType: "User") {
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
          contains("id is required on @gqRepository directive"),
        ),
      ),
    );
  });

  test("check id is not defined on target type", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID!
        }
        interface UserRepository @gqRepository(onType: "User", id:"name") {
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
          contains("Field 'User.name' referenced by directive '@gqRepository' is not defined or skipped"),
        ),
      ),
    );
  });

  test("check id = null but type has a field with @gqId directive", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = """
        type User {
          id: ID! @gqId
        }
        interface UserRepository @gqRepository(onType: "User") {
          _: String
        }
        """;
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
  });
}
