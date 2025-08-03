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

  test("test schema mapping generation2", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/server/services/service_gen.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    expect(g.services.keys, containsAll(["UserService", "CarService", "AzulService"]));

    var userService = g.services["UserService"]!;
    var carService = g.services["CarService"]!;
    var azulService = g.services["AzulService"]!;

    expect(azulService.getMethod("getAzuls"), isNotNull);
    expect(carService.getMethod("getCarById"), isNotNull);
    expect(carService.getMethod("countCars"), isNotNull);
    expect(userService.getMethod("getUser"), isNotNull);
    expect(userService.getMethod("getUsers"), isNotNull);

    
  });

}