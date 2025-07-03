import 'dart:io';

import 'package:retrofit_graphql/src/serializers/language.dart';
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

    final text =
        File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    expect(g.schemaMappings.keys, containsAll(["carOwner", "userCars", "carUserId", "carOwnerId"]));
    var carOwner = g.schemaMappings["carOwner"]!;
    
    expect(carOwner.batch, false);
    expect(carOwner.type.token, "Car");
    expect(carOwner.field.type.token, "Owner");
    expect(carOwner.field.name, "owner");

    var userCars = g.schemaMappings["userCars"]!;
    expect(userCars.batch, true);
    expect(userCars.type.token, "User");
    expect(userCars.field.type.token, "Car");
    expect(userCars.field.name, "cars");

    expect(g.schemaMappings["carUserId"]!.forbid, true);
    expect(g.schemaMappings["carOwnerId"]!.forbid, true);
    
  });

  test("test getSchemaByType", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/batch_mappging/batch_mappging.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var car = g.getType("Car");
    var result = g.getSchemaByType(car);
    expect(result.length, 3);
    
  });
}