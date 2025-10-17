import 'dart:io';

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

  test("test schema mapping generation", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  
type User {
    id: ID!
    name: String!
    middleName: String
    cars: Car! @gqSkipOnServer(batch: false)
}

type Car {
    make: String!
    model: String!
    userId: ID! @gqSkipOnClient
    owner: Owner! @gqSkipOnServer(batch: false)
    ownerId: ID! @gqSkipOnClient
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

    expect(parsed is Success, true);
    var mappings = g.controllers.values.expand((s) => s.mappings).toList();
    var mappingKeys = g.controllers.values.expand((s) => s.mappings).map((e) => e.key).toList();

    expect(mappingKeys, containsAll(["carOwner", "userCars", "carUserId", "carOwnerId"]));

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
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var springSerializer = SpringServerSerializer(g);
    var serice = g.services["UserWithCarService"]!;
    var serviceSerial = springSerializer.serializeService(serice, "");
    expect(serviceSerial, isNot(contains("Map<User, User> userWithCarUser(List<User> value);")));
  });

  test("Controller should implement identity on BatchMappings ", () {
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

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
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging3.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var springSerializer = SpringServerSerializer(g);
    var ctrl = g.controllers[g.controllerMappingName("UserWithCar")]!;
    var serviceSerial = springSerializer.serializeController(ctrl, "");
    print(serviceSerial);
    expect(serviceSerial, contains("public User userWithCarUser(User value) { return value; }"));
  });

  test("Should generate batch mapping when batch = true", () {
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = '''
type ConversationUnread ${gqSkipOnServer}(mapTo: "ConversationView", batch: true) {
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
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var mapping = g.getMappingByName("conversationUnreadUnread")!;
    expect(mapping.batch, isTrue);
  });

  test("Should generate batch mapping when batch = false", () {
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    const text = '''
type ConversationUnread ${gqSkipOnServer}(mapTo: "ConversationView", batch: false) {
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
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var mapping2 = g.getMappingByName("conversationUnreadUnread")!;
    expect(mapping2.batch, isFalse);
  });
}
