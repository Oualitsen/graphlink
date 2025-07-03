import 'dart:io';

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

  test("test backend handlers", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userUser = g.services["UserService"]!;
    var result = serverSerialzer.serializeController(userUser);
    expect(
        result,
        stringContainsInOrder([
          "@org.springframework.stereotype.Controller",
          "public class UserServiceController",
          "private final UserService userService;",
          "public UserServiceController(final UserService userService)",
          "this.userService = userService;",
          "User getUserById(@org.springframework.graphql.data.method.annotation.Argument final String id)",
          "@org.springframework.graphql.data.method.annotation.SubscriptionMapping",
          "reactor.core.publisher.Flux<java.util.List<Car>> watchCars(@org.springframework.graphql.data.method.annotation.Argument final String userId)",
          "@org.springframework.graphql.data.method.annotation.SubscriptionMapping",
          "reactor.core.publisher.Flux<User> watchUser(@org.springframework.graphql.data.method.annotation.Argument final String userId)",
          '@org.springframework.graphql.data.method.annotation.SchemaMapping(type="User", field="password")',
          "public String userPassword(User user)",
          """throw new graphql.GraphQLException("Access denied to field 'User.password'");"""
        ]));
  });

  test("test serialize Service", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService);
    expect(serializedService, startsWith("public interface UserService"));
    expect(
        serializedService,
        stringContainsInOrder([
          "User getUser();",
          "User getUserById(final String id);",
          "Integer getUserCount();",
          "java.util.List<User> getUsers(final String name, final String middle);",
          "reactor.core.publisher.Flux<Car> watchCars(final String userId);",
          "reactor.core.publisher.Mono<User> watchUser(final String userId);",
          "java.util.Map<User, java.util.List<Car>> userCars(java.util.List<User> userList);"
        ]));
    var carService = g.services["CarService"]!;
    var serializedCarService = serverSerialzer.serializeService(carService);
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(final String id);",
          "Integer getCarCount(final String userId);",
          "Owner carOwner(Car car);",
        ]));
  });

  test("test serialize Handler", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService);
    expect(serializedService, startsWith("public interface UserService"));
  });
}
