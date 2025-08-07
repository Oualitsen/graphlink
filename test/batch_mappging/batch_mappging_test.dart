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
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    expect(g.schemaMappings.keys, containsAll(["carOwner", "userCars", "carUserId", "carOwnerId"]));
    var carOwner = g.schemaMappings["carOwner"]!;

    expect(carOwner.batch, false);
    expect(carOwner.type.token, "Car");
    expect(carOwner.field.type.token, "Owner");
    expect(carOwner.field.name.token, "owner");

    var userCars = g.schemaMappings["userCars"]!;
    expect(userCars.batch, true);
    expect(userCars.type.token, "User");
    expect(userCars.field.type.token, "Car");
    expect(userCars.field.name.token, "cars");

    expect(g.schemaMappings["carUserId"]!.forbid, true);
    expect(g.schemaMappings["carOwnerId"]!.forbid, true);
  });

  test("test getSchemaByType", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var car = g.getTypeByName("Car")!;
    var result = g.getSchemaByType(car);
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
    var serviceSerial = springSerializer.serializeService(serice);
    expect(serviceSerial,
        isNot(contains("java.util.Map<User, User> userWithCarUser(java.util.List<User> value);")));
  });

  test("Controller should implement identity on BatchMappings ", () {
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging2.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var springSerializer = SpringServerSerializer(g);
    var serice = g.services["UserWithCarService"]!;
    var serviceSerial = springSerializer.serializeController(serice);
    expect(
        serviceSerial,
        contains(
            "public java.util.List<User> userWithCarUser(java.util.List<User> value) { return value; }"));
  });

  test("Controller should implement identity on SchemaMappings ", () {
    final GQGrammar g = GQGrammar(typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text = File("test/batch_mappging/batch_mappging3.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var springSerializer = SpringServerSerializer(g);
    var serice = g.services["UserWithCarService"]!;
    var serviceSerial = springSerializer.serializeController(serice);
    expect(serviceSerial, contains("public User userWithCarUser(User value) { return value; }"));
  });
}
