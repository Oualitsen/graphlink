import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("testDecorators", () {
    final GLParser g = GLParser(identityFields: ["id"]);
    final text = File(
            "test/serializers/dart/types/type_serialization_decorators_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var dartSerialzer = DartSerializer(g);

    var user = g.getTypeByName("User")!;

    var idField = user.fields.where((f) => f.name.token == "id").first;
    var nameField = user.fields.where((f) => f.name.token == "name").first;
    var middleNameField =
        user.fields.where((f) => f.name.token == "middleName").first;
    var id = dartSerialzer.serializeField(idField, true);
    var nameSerial = dartSerialzer.serializeField(nameField, true);
    var middleNameFieldSerial =
        dartSerialzer.serializeField(middleNameField, true);
    expect(
        id, stringContainsInOrder(["@Getter", "@Setter", "final String id;"]));
    expect(nameSerial,
        stringContainsInOrder(["@Getter", "@Setter", "final String name;"]));
    expect(
        middleNameFieldSerial,
        stringContainsInOrder(
            ['@Getter("value")', 'final String? middleName;']));

    var ibase = g.interfaces["IBase"]!;

    var ibaseText = dartSerialzer.serializeInterface(ibase);
    expect(ibaseText.trim(), startsWith("@Logger"));

    var gender = g.enums["Gender"]!;
    var genderText = dartSerialzer.serializeEnumDefinition(gender, "");
    expect(genderText.trim(), startsWith("@Logger"));

    var input = g.inputs["UserInput"]!;
    var inputText = dartSerialzer.serializeInputDefinition(input, "");
    expect(inputText.trim(), startsWith("@Input"));
  });
}
