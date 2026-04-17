import 'dart:io';

import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
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

  test("test backend handlers 1", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);
    var userCtrl = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userCtrl, "myorg");
    print(result);
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller()',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUser() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUser());',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUserById(@Argument() String id) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserById(id));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<List<User>> getUsers(@Argument() String name, @Argument() String middle) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUsers(name, middle));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<Integer> getUserCount() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserCount());',
        '}',
        '@SubscriptionMapping()',
        'public Flux<User> watchUser(@Argument() String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping()',
        'public Flux<List<Car>> watchCars(@Argument() String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '}',
      ]),
    );
  });

  test("test backend handlers 2", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);
    var userUser = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userUser, "");

    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller()',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUser() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUser());',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUserById(@Argument() String id) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserById(id));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<List<User>> getUsers(@Argument() String name, @Argument() String middle) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUsers(name, middle));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<Integer> getUserCount() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserCount());',
        '}',
        '@SubscriptionMapping()',
        'public Flux<User> watchUser(@Argument() String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping()',
        'public Flux<List<Car>> watchCars(@Argument() String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '}',
      ]),
    );
  });

  test("test backend handlers when shcema generation is on", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g, generateSchema: true);
    var userUser = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userUser, "");
    expect(
      result.split('\n').map((e) => e.trim()).toList(),
      containsAllInOrder([
        '@Controller()',
        'public class UserServiceController {',
        'private final UserService userService;',
        'public UserServiceController(UserService userService) {',
        'this.userService = userService;',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUser() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUser());',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<User> getUserById(@Argument() String id) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserById(id));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<List<User>> getUsers(@Argument() String name, @Argument() String middle) {',
        'return CompletableFuture.supplyAsync(() -> userService.getUsers(name, middle));',
        '}',
        '@QueryMapping()',
        'public CompletableFuture<Integer> getUserCount() {',
        'return CompletableFuture.supplyAsync(() -> userService.getUserCount());',
        '}',
        '@SubscriptionMapping()',
        'public Flux<User> watchUser(@Argument() String userId) {',
        'return userService.watchUser(userId);',
        '}',
        '@SubscriptionMapping()',
        'public Flux<List<Car>> watchCars(@Argument() String userId) {',
        'return userService.watchCars(userId);',
        '}',
        '}',
      ]),
    );

    expect(result, isNot(contains("public String userPassword")));
    expect(result, isNot(contains("throw new graphql.GraphQLException")));
  });

  test("test controller/service returning skipped type ", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer2.graphql")
            .readAsStringSync();

    g.parse(text);

    var userCarService = g.services["UserCarService"]!;
    var userCarCtrl = g.controllers["UserCarServiceController"]!;

    var serialzer = SpringServerSerializer(g);
    var serviceSerial = serialzer.serializeService(userCarService, "");
    var controllerSerial = serialzer.serializeController(userCarCtrl, "");

    expect(
        serviceSerial,
        stringContainsInOrder([
          "User getUserCar();",
        ]));

    expect(
        controllerSerial,
        stringContainsInOrder([
          "public CompletableFuture<User> getUserCar()",
        ]));
  });

  test("test controller/service returning skipped type (batch mapping) ", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer2.graphql")
            .readAsStringSync();

    g.parse(text);

    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimalService"]!;
    var ownerAnimalMappingService =
        g.services[g.serviceMappingName("OwnerWithAnimal")]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    var ownerServiceMappingSerial =
        serialzer.serializeService(ownerAnimalMappingService, "");

    expect(ownerServiceSerial,
        stringContainsInOrder(["List<Owner> getOwnwers();"]));

    expect(
        ownerServiceMappingSerial,
        stringContainsInOrder(
            ["Map<Owner, Animal> ownerWithAnimalAnimal(List<Owner> value);"]));
  });

  test("test controller/service returning skipped type with no mapTo 1", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer2.graphql")
            .readAsStringSync();

    g.parse(text);

    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal2Service"]!;
    var ownerAnimalMappingService =
        g.services[g.serviceMappingName("OwnerWithAnimal2")]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    var ownerServiceMappingSerial =
        serialzer.serializeService(ownerAnimalMappingService, "");
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "Object getOwnerWithAnimal2();",
        ]));
    expect(
        ownerServiceMappingSerial,
        stringContainsInOrder([
          "Owner ownerWithAnimal2Owner(Object value);",
          "Animal ownerWithAnimal2Animal(Object value);"
        ]));
  });

  test("test controller/service returning skipped type with no mapTo 2", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer2.graphql")
            .readAsStringSync();

    g.parse(text);

    var serialzer = SpringServerSerializer(g);

    var ownerAnimalService = g.services["OwnerWithAnimal3Service"]!;
    var ownerAnimalServiceMapping =
        g.services[g.serviceMappingName("OwnerWithAnimal3")]!;
    var ownerServiceSerial = serialzer.serializeService(ownerAnimalService, "");
    var ownerServiceMappingSerial =
        serialzer.serializeService(ownerAnimalServiceMapping, "");
    expect(
        ownerServiceSerial,
        stringContainsInOrder([
          "List<?> getOwnwers3();",
        ]));
    expect(
        ownerServiceMappingSerial,
        stringContainsInOrder([
          "Map<?, Owner> ownerWithAnimal3Owner(List<Object> value);",
          "Map<?, Animal> ownerWithAnimal3Animal(List<Object> value);",
        ]));
  });

  test("test backend handlers with DataFetchingEnvironment injection", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g, injectDataFetching: true);
    var userCtrl = g.controllers["UserServiceController"]!;
    var result = serverSerialzer.serializeController(userCtrl, "");
    expect(
        result,
        stringContainsInOrder([
          "@Controller",
          "public class UserServiceController",
          "private final UserService userService;",
          "public UserServiceController(UserService userService)",
          "this.userService = userService;",
          "CompletableFuture<User> getUser(DataFetchingEnvironment dataFetchingEnvironment) {",
          "return CompletableFuture.supplyAsync(() -> userService.getUser(dataFetchingEnvironment));",
          "CompletableFuture<User> getUserById(@Argument() String id, DataFetchingEnvironment dataFetchingEnvironment)",
          "return CompletableFuture.supplyAsync(() -> userService.getUserById(id, dataFetchingEnvironment));",
          "@SubscriptionMapping",
          "Flux<List<Car>> watchCars(@Argument() String userId, DataFetchingEnvironment dataFetchingEnvironment)",
          "return userService.watchCars(userId, dataFetchingEnvironment);",
        ]));
  });

  test("test serialize Service (User Service)", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService, "");
    expect(
        serializedService,
        stringContainsInOrder([
          "public interface UserService",
          "User getUser();",
          "User getUserById(String id);",
          "List<User> getUsers(String name, String middle);",
          "Integer getUserCount();",
          "Flux<User> watchUser(String userId);",
          "Flux<List<Car>> watchCars(String userId);",
        ]));
  });

  test("test serialize Service (Car Service)", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);

    var carService = g.services["CarService"]!;
    var serializedCarService = serverSerialzer.serializeService(carService, "");
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(String id);",
          "Integer getCarCount(String userId);",
        ]));
  });

  test("test serialize Service with DataFetchingEnvironment", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g, injectDataFetching: true);

    var carService = g.services["CarService"]!;

    var serializedCarService = serverSerialzer.serializeService(carService, "");
    expect(
        serializedCarService,
        stringContainsInOrder([
          "Car getCarById(String id, DataFetchingEnvironment dataFetchingEnvironment);",
          "Integer getCarCount(String userId, DataFetchingEnvironment dataFetchingEnvironment);",
        ]));
  });

  test("test serialize Handler", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/backend/spring_server_serializer.graphql")
            .readAsStringSync();

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var serializedService = serverSerialzer.serializeService(userService, "");
    expect(serializedService, contains("public interface UserService"));
  });

  test("controller should not serialize 'return' on void", () {
    final typeMapping = {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "Integer",
      "Boolean": "Boolean",
      "Null": "null",
      "Long": "Long",
      'void': 'void',
    };

    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    const text = '''
  scalar void

  type User {
    userName: String
  }
 

  type Mutation {
    deleteUser: void ${glServiceName}(name: "UserService")
  }

''';

    g.parse(text);

    var serverSerialzer = SpringServerSerializer(g);
    var userController = g.controllers["UserServiceController"]!;

    var controllerSerial =
        serverSerialzer.serializeController(userController, "com.myorg");

    expect(controllerSerial, contains('public CompletableFuture<Void> deleteUser()'));
    expect(
        controllerSerial, contains('return CompletableFuture.supplyAsync(() -> userService.deleteUser());'));

    print("DONE");
  });

  test(
      'field with arguments on non-root type without @glSkipOnServer throws on serializer construction',
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        vehicles(year: Int): [String]
      }
    ''');
    expect(
      () => SpringServerSerializer(g),
      throwsA(isA<ParseException>()),
    );
  });

  test(
      'field with arguments and batch: true throws on serializer construction',
      () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        vehicles(year: Int): [String] @glSkipOnServer(batch: true)
      }
    ''');
    expect(
      () => SpringServerSerializer(g),
      throwsA(isA<ParseException>()),
    );
  });

  test('field with arguments and batch: false is valid', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        vehicles(year: Int): [String] @glSkipOnServer(batch: false)
      }
    ''');
    expect(() => SpringServerSerializer(g), returnsNormally);
  });

  test('field with arguments on root type (Query) does not throw', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query {
        getUser(id: String): User
      }
      type User { name: String }
    ''');
    expect(() => SpringServerSerializer(g), returnsNormally);
  });

  test('schema mapping with field arguments prints generated code', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query { getUser: User }
      type User {
        name: String
        vehicles(year: Int, category: String): [Vehicle!]! @glSkipOnServer(batch: false)
      }
      type Vehicle {
        id: String
      }
    ''');
    final serializer = SpringServerSerializer(g);
    final ctrl = g.controllers[g.controllerMappingName('User')]!;
    final result = serializer.serializeController(ctrl, 'com.example');
    print(result);
  });

  test('useSpringSecurity wraps CompletableFuture body with SecurityContext capture and try/finally', () {
    final g = GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
      type Query {
        getUser(id: ID!): User!
      }
      type User {
        id: ID!
        name: String!
      }
    ''');
    final serializer = SpringServerSerializer(g, useSpringSecurity: true);
    final ctrl = g.controllers['UserServiceController']!;
    final result = serializer.serializeController(ctrl, 'com.example');
    print(result);
    final lines = result.split('\n').map((e) => e.trim()).toList();
    expect(lines, containsAllInOrder([
      '@QueryMapping()',
      'public CompletableFuture<User> getUser(@Argument() String id) {',
      'SecurityContext securityContext = SecurityContextHolder.getContext();',
      'return CompletableFuture.supplyAsync(() -> {',
      'SecurityContextHolder.setContext(securityContext);',
      'try {',
      'return userService.getUser(id);',
      '} finally {',
      'SecurityContextHolder.clearContext();',
      '}',
      '});',
      '}',
    ]));
  });
}
