import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() async {
  test("common interface fields 1", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_test.graphql")
        .readAsStringSync();
    final GLParser g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

    var basicEntityInterface = g.projectedInterfaces["BasicEntity_Id"]!;
    expect(basicEntityInterface.fieldNames.length, 1);
    expect(basicEntityInterface.fieldNames, containsAll(["id"]));
    expect(basicEntityInterface.implementations.length, 2);
  });

  test("common interface fields 2", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_test2.graphql")
        .readAsStringSync();
    final GLParser g =
        GLParser(autoGenerateQueries: false, generateAllFieldsFragments: true);

    g.parse(text);

    var basicEntityInterface = g.projectedInterfaces["BasicEntity"]!;

    expect(basicEntityInterface.fieldNames.length, 3);

    expect(basicEntityInterface.fieldNames,
        containsAll(["id", "createdBy", "creationDate"]));
  });

  test("common interface fields 3", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_test3.graphql")
        .readAsStringSync();
    final GLParser g =
        GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);

    g.parse(text);

    var basicEntityInterface = g.projectedInterfaces["BasicEntity"]!;
    expect(
        basicEntityInterface.fieldNames,
        containsAll(
            ["id", "createdBy", "creationDate", "lastUpdate", "lastUpdateBy"]));
    expect(basicEntityInterface.fieldNames, isNot(contains("firstName")));
    expect(basicEntityInterface.fieldNames, isNot(contains("lastName")));
  });

  test("common interface (union) fields 1", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_union_test.graphql")
        .readAsStringSync();
    final GLParser g = GLParser();

    g.parse(text);

    var vehicle = g.projectedInterfaces["Vehicle"]!;
    expect(vehicle.fieldNames.length, 2);
    expect(vehicle.fieldNames, containsAll(["make", "model"]));
    print(
        "implementations = ${vehicle.implementations.map((e) => e.token).toList()}");
    var serial = DartSerializer(g);
    print(serial.serializeTypeDefinition(vehicle, ''));
    expect(vehicle.implementations.length, 2);
  });

  test("common interface (union) fields 2", () {
    final text = File(
            "test/interface_common_fields/interface_common_fields_union_test2.graphql")
        .readAsStringSync();
    final GLParser g =
        GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true);
    g.parse(text);

    var vehicle = g.projectedInterfaces["Vehicle"]!;
    expect(vehicle.fieldNames.length, 2);
    expect(vehicle.fieldNames, containsAll(["make", "model"]));

    expect(vehicle.implementations.length, 2);
  });
}
