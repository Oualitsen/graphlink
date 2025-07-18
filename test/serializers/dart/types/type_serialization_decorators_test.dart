import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("testDecorators", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text =
        File("test/serializers/dart/types/type_serialization_decorators_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var dartSerialzer = DartSerializer(g);

    var user = g.getType("User");

    var idField = user.fields.where((f) => f.name == "id").first;
    var nameField = user.fields.where((f) => f.name == "name").first;
    var middleNameField = user.fields.where((f) => f.name == "middleName").first;
    var id = dartSerialzer.serializeField(idField);
    var nameSerial = dartSerialzer.serializeField(nameField);
    var middleNameFieldSerial = dartSerialzer.serializeField(middleNameField);
    expect(id, "@Getter @Setter final String id;");
    expect(nameSerial, "@Getter @Setter final String name;");
    expect(middleNameFieldSerial, '@Getter("value") final String? middleName;');

    var ibase = g.interfaces["IBase"]!;

    var ibaseText = dartSerialzer.serializeInterface(ibase);
    expect(ibaseText.trim(), startsWith("@Logger"));

    var gender = g.enums["Gender"]!;
    var genderText = dartSerialzer.serializeEnumDefinition(gender);
    expect(genderText.trim(), startsWith("@Logger"));

    var input = g.inputs["UserInput"]!;
    var inputText = dartSerialzer.serializeInputDefinition(input);
    expect(inputText.trim(), startsWith("@Input"));
  });
}
