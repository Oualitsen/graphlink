import 'dart:io';

import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("testDecorators", () {
    final GLGrammar g = GLGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_decorators_test.graphql")
        .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var dartSerialzer = DartSerializer(g);

    var user = g.getTypeByName("User")!;

    var idField = user.fields.where((f) => f.name.token == "id").first;
    var nameField = user.fields.where((f) => f.name.token == "name").first;
    var middleNameField = user.fields.where((f) => f.name.token == "middleName").first;
    var id = dartSerialzer.serializeField(idField, true);
    var nameSerial = dartSerialzer.serializeField(nameField, true);
    var middleNameFieldSerial = dartSerialzer.serializeField(middleNameField, true);
    expect(id, stringContainsInOrder(["@Getter", "@Setter", "final String id;"]));
    expect(nameSerial, stringContainsInOrder(["@Getter", "@Setter", "final String name;"]));
    expect(middleNameFieldSerial,
        stringContainsInOrder(['@Getter("value")', 'final String? middleName;']));

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
