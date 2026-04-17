import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
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

  test("test schema mapping generation2", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text =
        File("test/server/services/service_gen.graphql").readAsStringSync();

    g.parse(text);

    expect(g.services.keys,
        containsAll(["UserService", "CarService", "AzulService"]));

    var userService = g.services["UserService"]!;
    var carService = g.services["CarService"]!;
    var azulService = g.services["AzulService"]!;

    expect(azulService.getFieldByName("getAzuls"), isNotNull);
    expect(carService.getFieldByName("getCarById"), isNotNull);
    expect(carService.getFieldByName("countCars"), isNotNull);
    expect(userService.getFieldByName("getUser"), isNotNull);
    expect(userService.getFieldByName("getUsers"), isNotNull);
  });
}
