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

  test("test schema mapping generation", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var mappings = g.services.values.expand((s) => s.mappings);
    var mappingKeys = g.services.values.expand((s) => s.mappings).map((e) => e.key);
    expect(mappingKeys, containsAll(["carOwner", "userCars", "carUserId", "carOwnerId"]));
    var carOwner = mappings.where((e) => e.key == "carOwner").first;

    expect(carOwner.batch, false);
    expect(carOwner.type.token, "Car");
    expect(carOwner.field.type.token, "Owner");
    expect(carOwner.field.name.token, "owner");

    var userCars = mappings.where((e) => e.key == "userCars").first;
    expect(userCars.batch, true);
    expect(userCars.type.token, "User");
    expect(userCars.field.type.token, "Car");
    expect(userCars.field.name.token, "cars");

    expect(mappings.where((e) => e.key == "carUserId").first.forbid, true);
    expect(mappings.where((e) => e.key == "carOwnerId").first.forbid, true);
  });

  test("test getSchemaByType", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var carSerice = g.services["CarService"]!;
    var car = g.getTypeByName("Car")!;
    var result = carSerice.getSchemaByType(car);
    expect(result.length, 3);
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
    var ctrl = g.controllers["UserWithCarServiceController"]!;
    var serviceSerial = springSerializer.serializeController(ctrl, "");
    expect(
        serviceSerial,
        stringContainsInOrder([
          "public List<User> userWithCarUser(List<User> value) {",
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
    var ctrl = g.controllers["UserWithCarServiceController"]!;
    var serviceSerial = springSerializer.serializeController(ctrl, "");
    expect(serviceSerial, contains("public User userWithCarUser(User value) { return value; }"));
  });
}
