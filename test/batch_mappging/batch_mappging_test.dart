import 'dart:io';

import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';

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

  test("test schema mapping generation", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    g.parse('''
  
type User {
    id: ID!
    name: String!
    middleName: String
    cars: Car! @glSkipOnServer(batch: false)
}

type Car {
    make: String!
    model: String!
    userId: ID! @glSkipOnClient
    owner: Owner! @glSkipOnServer(batch: false)
    ownerId: ID! @glSkipOnClient
}

type Owner {
    id: ID!
}

type Query {

   getUser: User
   getUserById(id: ID!): User
   getUsers(name: String, middle: String): [User!]!
   getCarById(id: ID!): Car!

}

''');

    var mappings = g.controllers.values.expand((s) => s.mappings).toList();
    var mappingKeys = g.controllers.values
        .expand((s) => s.mappings)
        .map((e) => e.key)
        .toList();

    expect(mappingKeys,
        containsAll(["carOwner", "userCars", "carUserId", "carOwnerId"]));

    var carOwner = mappings.where((e) => e.key == "carOwner").first;

    expect(carOwner.isBatch, false);
    expect(carOwner.type.token, "Car");
    expect(carOwner.field.type.token, "Owner");
    expect(carOwner.field.name.token, "owner");

    var userCars = mappings.where((e) => e.key == "userCars").first;
    expect(userCars.isBatch, true);
    expect(userCars.type.token, "User");
    expect(userCars.field.type.token, "Car");
    expect(userCars.field.name.token, "cars");

    expect(mappings.where((e) => e.key == "carUserId").first.forbid, true);
    expect(mappings.where((e) => e.key == "carOwnerId").first.forbid, true);
  });

  test("Service should not have identity schema mapping", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/batch_mappging/batch_mappging2.graphql").readAsStringSync();

    g.parse(text);

    var springSerializer = SpringServerSerializer(g);
    var serice = g.services["UserWithCarService"]!;
    var serviceSerial = springSerializer.serializeService(serice, "");
    expect(serviceSerial,
        isNot(contains("Map<User, User> userWithCarUser(List<User> value);")));
  });

  test("Controller should implement identity on BatchMappings ", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/batch_mappging/batch_mappging2.graphql").readAsStringSync();

    g.parse(text);

    var springSerializer = SpringServerSerializer(g);
    var ctrl = g.controllers[g.controllerMappingName("UserWithCar")]!;
    var serviceSerial = springSerializer.serializeController(ctrl, "");
    expect(
        serviceSerial,
        stringContainsInOrder([
          '@SchemaMapping(typeName="UserWithCar", field="user")',
          "public User userWithCarUser(User value) {",
          "return value;",
          "}",
        ]));
  });

  test("Controller should implement identity on SchemaMappings ", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/batch_mappging/batch_mappging3.graphql").readAsStringSync();

    g.parse(text);

    var springSerializer = SpringServerSerializer(g);
    var ctrl = g.controllers[g.controllerMappingName("UserWithCar")]!;
    var serviceSerial = springSerializer.serializeController(ctrl, "");
    expect(
        serviceSerial,
        stringContainsInOrder([
          "public User userWithCarUser(User value) {",
          "return value;",
          "}"
        ]));
  });

  test("Should generate batch mapping when batch = true", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = '''
type ConversationUnread ${glSkipOnServer}(mapTo: "ConversationView", batch: true) {
    view: ConversationView!
    unread: Int!
}

type ConversationView  {
    customName: String
}

type Query {
  getConverstation: ConversationUnread
}


''';

    g.parse(text);

    var mapping = g.getMappingByName("conversationUnreadUnread")!;
    expect(mapping.batch, isTrue);
  });

  test("Should not generate batch mapping when batch = false", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = '''
type ConversationUnread ${glSkipOnServer}(mapTo: "ConversationView", batch: false) {
    view: ConversationView!
    unread: Int!
}

type ConversationView  {
    customName: String
}

type Query {
  getConverstation: ConversationUnread
}
''';

    g.parse(text);

    var mapping2 = g.getMappingByName("conversationUnreadUnread")!;
    expect(mapping2.batch, isFalse);
  });

  test(
      "should inject DataFetchingEnvironment for mappings when injectDataFetching = true",
      () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    const text = '''
    type User {
      name: String!
      car: Car ${glSkipOnServer}
    }
    type Car {
      model: String!
    }
    type Query {
      getUser: User
    }
''';

    g.parse(text);

    var mappingService = g.services[g.serviceMappingName('User')]!;
    var mappingController = g.controllers[g.controllerMappingName('User')]!;
    var serialService = serializer.serializeService(mappingService, "myOrg");
    var serialController =
        serializer.serializeController(mappingController, "myOrg");
    expect(
        serialService,
        contains(
            'Map<User, Car> userCar(List<User> value, DataFetchingEnvironment dataFetchingEnvironment);'));
    expect(
        serialController,
        contains(
            'Map<User, Car> userCar(List<User> value, DataFetchingEnvironment dataFetchingEnvironment)'));
    expect(
        serialController,
        contains(
            ' return userSchemaMappingsService.userCar(value, dataFetchingEnvironment);'));
  });
}
