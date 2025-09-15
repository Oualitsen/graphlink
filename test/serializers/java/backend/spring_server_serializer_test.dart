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

  test("test backend handlers 1", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userCtrl = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userCtrl, "myorg");
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(final UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping',
        'public User getUser() {',
        'return userService.getUser();',
        '}',
        '@QueryMapping',
        'public User getUserById(@Argument final String id) {',
        'return userService.getUserById(id);',
        '}',
        '@QueryMapping',
        'public List<User> getUsers(@Argument final String name, @Argument final String middle) {',
        'return userService.getUsers(name, middle);',
        '}',
        '@QueryMapping',
        'public Integer getUserCount() {',
        'return userService.getUserCount();',
        '}',
        '@SubscriptionMapping',
        'public Flux<User> watchUser(@Argument final String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping',
        'public Flux<List<Car>> watchCars(@Argument final String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '@BatchMapping(typeName="User", field="cars")',
        'public Map<User, List<Car>> userCars(List<User> value) {',
        'return userService.userCars(value);',
        '}',
        '@SchemaMapping(typeName="User", field="password")',
        'public String userPassword(User value) {',
        'throw new GraphQLException("Access denied to field \'User.password\'");',
        '}',
        '@BatchMapping(typeName="Car", field="owner")',
        'public Map<Car, Owner> carOwner(List<Car> value) {',
        'return userService.carOwner(value);',
        '}',
        '}',
      ]),
    );
  });

  test("test backend handlers 2", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userUser = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userUser, "");

    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(final UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping',
        'public User getUser() {',
        'return userService.getUser();',
        '}',
        '@QueryMapping',
        'public User getUserById(@Argument final String id) {',
        'return userService.getUserById(id);',
        '}',
        '@QueryMapping',
        'public List<User> getUsers(@Argument final String name, @Argument final String middle) {',
        'return userService.getUsers(name, middle);',
        '}',
        '@QueryMapping',
        'public Integer getUserCount() {',
        'return userService.getUserCount();',
        '}',
        '@SubscriptionMapping',
        'public Flux<User> watchUser(@Argument final String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping',
        'public Flux<List<Car>> watchCars(@Argument final String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '@BatchMapping(typeName="User", field="cars")',
        'public Map<User, List<Car>> userCars(List<User> value) {',
        'return userService.userCars(value);',
        '}',
        '@SchemaMapping(typeName="User", field="password")',
        'public String userPassword(User value) {',
        'throw new GraphQLException("Access denied to field \'User.password\'");',
        '}',
        '@BatchMapping(typeName="Car", field="owner")',
        'public Map<Car, Owner> carOwner(List<Car> value) {',
        'return userService.carOwner(value);',
        '}',
        '}',
      ]),
    );
  });

  test("test backend handlers when shcema generation is on", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g, generateSchema: true);
    var userUser = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userUser, "");
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(final UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping',
        'public User getUser() {',
        'return userService.getUser();',
        '}',
        '@QueryMapping',
        'public User getUserById(@Argument final String id) {',
        'return userService.getUserById(id);',
        '}',
        '@QueryMapping',
        'public List<User> getUsers(@Argument final String name, @Argument final String middle) {',
        'return userService.getUsers(name, middle);',
        '}',
        '@QueryMapping',
        'public Integer getUserCount() {',
        'return userService.getUserCount();',
        '}',
        '@SubscriptionMapping',
        'public Flux<User> watchUser(@Argument final String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping',
        'public Flux<List<Car>> watchCars(@Argument final String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '@BatchMapping(typeName="User", field="cars")',
        'public Map<User, List<Car>> userCars(List<User> value) {',
        'return userService.userCars(value);',
        '}',
        '@BatchMapping(typeName="Car", field="owner")',
        'public Map<Car, Owner> carOwner(List<Car> value) {',
        'return userService.carOwner(value);',
        '}',
        '}',
      ]),
    );

    expect(result, isNot(contains("public String userPassword")));
    expect(result, isNot(contains("throw new graphql.GraphQLException")));
  });

  test("test controller/service returning skipped type ", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var userCarService = g.services["UserCarService"]!;
    var userCarCtrl = g.controllers["UserCarServiceController"]!;

    var serialzer = SpringServerSerializer(g);
    var serviceSerial = serialzer.serializeService(userCarService, "");
    var controllerSerial = serialzer.serializeController(userCarCtrl, "");

    expect(
        serviceSerial,
        stringContainsInOrder([
          "User getUserCar();",
          "Car userCarCar(User value);",
        ]));

    expect(
        controllerSerial,
        stringContainsInOrder([
          "public User getUserCar()",
          "return userCarService.getUserCar();",
          "public Car userCarCar(User value)",
          "return userCarService.userCarCar(value);",
        ]));
  });

  test("test controller/service returning skipped type (batch mapping) ", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimalService"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    expect(
        ownerServiceSerial,
        stringContainsInOrder(
            ["List<Owner> getOwnwers();", "Map<Owner, Animal> ownerWithAnimalAnimal(List<Owner> value);"]));
  });

  test("test controller/service returning skipped type with no mapTo 1", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal2Service"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "Object getOwnerWithAnimal2();",
          "Owner ownerWithAnimal2Owner(Object value);",
          "Animal ownerWithAnimal2Animal(Object value);"
        ]));
  });

  test("test controller/service returning skipped type with no mapTo 2", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal3Service"]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    print(ownerServiceSerial);
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "List<?> getOwnwers3();",
          "Map<?, Owner> ownerWithAnimal3Owner(List<Object> value);",
          "Map<?, Animal> ownerWithAnimal3Animal(List<Object> value);",
        ]));
  });

  test("test backend handlers with DataFetchingEnvironment injection", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userCtrl = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userCtrl, "", injectDataFtechingEnv: true);
    expect(
        result,
        stringContainsInOrder([
          "@Controller",
          "public class UserServiceController",
          "private final UserService userService;",
          "public UserServiceController(final UserService userService)",
          "this.userService = userService;",
          "User getUser(DataFetchingEnvironment dataFetchingEnvironment) {",
          "return userService.getUser(dataFetchingEnvironment);",
          "User getUserById(@Argument final String id, DataFetchingEnvironment dataFetchingEnvironment)",
          "return userService.getUserById(id, dataFetchingEnvironment);",
          "@SubscriptionMapping",
          "Flux<List<Car>> watchCars(@Argument final String userId, DataFetchingEnvironment dataFetchingEnvironment)",
          "return userService.watchCars(userId, dataFetchingEnvironment);",
        ]));
  });

  test("test serialize Service (User Service)", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService, "");
    print(serializedService);
    expect(
        serializedService,
        stringContainsInOrder([
          "public interface UserService",
          "User getUser();",
          "User getUserById(final String id);",
          "List<User> getUsers(final String name, final String middle);",
          "Integer getUserCount();",
          "Flux<User> watchUser(final String userId);",
          "Flux<List<Car>> watchCars(final String userId);",
          "Map<User, List<Car>> userCars(List<User> value);",
          "Map<Car, Owner> carOwner(List<Car> value);"
        ]));
  });

  test("test serialize Service (Car Service)", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);

    var carService = g.services["CarService"]!;
    var serializedCarService = serverSerialzer.serializeService(carService, "");
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(final String id);",
          "Integer getCarCount(final String userId);",
        ]));
  });

  test("test serialize Service with DataFetchingEnvironment", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);

    var carService = g.services["CarService"]!;

    var serializedCarService = serverSerialzer.serializeService(carService, "", injectDataFtechingEnv: true);
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(final String id, DataFetchingEnvironment dataFetchingEnvironment);",
          "Integer getCarCount(final String userId, DataFetchingEnvironment dataFetchingEnvironment);",
        ]));
  });

  test("test serialize Handler", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/serializers/java/backend/spring_server_serializer.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService, "");
    expect(serializedService, contains("public interface UserService"));
  });
}
