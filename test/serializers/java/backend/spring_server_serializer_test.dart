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
          "public User getUserById(@org.springframework.graphql.data.method.annotation.Argument final String id)",
          "@org.springframework.graphql.data.method.annotation.SubscriptionMapping",
          "public reactor.core.publisher.Flux<java.util.List<Car>> watchCars(@org.springframework.graphql.data.method.annotation.Argument final String userId)",
          "@org.springframework.graphql.data.method.annotation.SubscriptionMapping",
          "public reactor.core.publisher.Flux<User> watchUser(@org.springframework.graphql.data.method.annotation.Argument final String userId)",
          '@org.springframework.graphql.data.method.annotation.SchemaMapping(type="User", field="password")',
          "public String userPassword(User user)",
          """throw new graphql.GraphQLException("Access denied to field 'User.password'");"""
        ]));
  });

  test("test controller/service returning skipped type ", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var userCarService = g.services["UserCarService"]!;

    var serialzer = SpringServerSerializer(g);
    var serviceSerial = serialzer.serializeService(userCarService);
    var controllerSerial = serialzer.serializeController(userCarService);

    expect(
        serviceSerial,
        stringContainsInOrder([
          "User getUserCar();",
          "Car userCarCar(User user);",
          "User userCarUser(User user);",
        ]));

    expect(
        controllerSerial,
        stringContainsInOrder([
          "public User getUserCar()",
          "return userCarService.getUserCar();",
          "public Car userCarCar(User user)",
          "return userCarService.userCarCar(car);",
          "User userCarUser(User user)",
          "return userCarService.userCarUser(user);"
        ]));
  });

  test("test controller/service returning skipped type (batch mapping) ", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimalService"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService);
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "java.util.List<Owner> getOwnwers();",
          "java.util.Map<Owner, Owner> ownerWithAnimalOwner(java.util.List<Owner> ownerList);",
          "java.util.Map<Owner, Animal> ownerWithAnimalAnimal(java.util.List<Owner> ownerList);"
        ]));
  });

  test("test controller/service returning skipped type with no mapTo", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal2Service"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService);
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "Object getOwnerWithAnimal2();",
          "Owner ownerWithAnimal2Owner(Object object);",
          "Animal ownerWithAnimal2Animal(Object object);"
        ]));
  });

  test("test controller/service returning skipped type with no mapTo", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal3Service"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService);
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "java.util.List<Object> getOwnwers3();",
          "java.util.Map<Object, Owner> ownerWithAnimal3Owner(java.util.List<Object> objectList);",
          "java.util.Map<Object, Animal> ownerWithAnimal3Animal(java.util.List<Object> objectList);",
        ]));
  });

  test("test backend handlers with DataFetchingEnvironment injection", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userUser = g.services["UserService"]!;
    var result = serverSerialzer.serializeController(userUser, injectDataFtechingEnv: true);
    expect(
        result,
        stringContainsInOrder([
          "@org.springframework.stereotype.Controller",
          "public class UserServiceController",
          "private final UserService userService;",
          "public UserServiceController(final UserService userService)",
          "this.userService = userService;",
          "User getUser(graphql.schema.DataFetchingEnvironment dataFetchingEnvironment) {",
          "return userService.getUser(dataFetchingEnvironment);",
          "User getUserById(@org.springframework.graphql.data.method.annotation.Argument final String id, graphql.schema.DataFetchingEnvironment dataFetchingEnvironment)",
          "return userService.getUserById(id, dataFetchingEnvironment);",
          "@org.springframework.graphql.data.method.annotation.SubscriptionMapping",
          "reactor.core.publisher.Flux<java.util.List<Car>> watchCars(@org.springframework.graphql.data.method.annotation.Argument final String userId, graphql.schema.DataFetchingEnvironment dataFetchingEnvironment)",
          "return userService.watchCars(userId, dataFetchingEnvironment);",
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
          "reactor.core.publisher.Flux<java.util.List<Car>> watchCars(final String userId);",
          "reactor.core.publisher.Flux<User> watchUser(final String userId);",
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

    serializedCarService = serverSerialzer.serializeService(carService, injectDataFtechingEnv: true);
    print(serializedCarService);
  });

  test("test serialize Service with DataFetchingEnvironment", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);

    var carService = g.services["CarService"]!;

    var serializedCarService = serverSerialzer.serializeService(carService, injectDataFtechingEnv: true);
    print(serializedCarService);
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(final String id, graphql.schema.DataFetchingEnvironment dataFetchingEnvironment);",
          "Integer getCarCount(final String userId, graphql.schema.DataFetchingEnvironment dataFetchingEnvironment);",
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
