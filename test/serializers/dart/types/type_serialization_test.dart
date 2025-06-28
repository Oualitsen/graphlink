import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
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
    var id = dartSerialzer.serializeField(idField);
    expect(id, "@Getter @Setter final String id;");

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
  test("Dart type serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.getType("User");
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeTypeDefinition(user);
    print(class_);
  });

  test("Dart input serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.inputs["UserInput"];
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeInputDefinition(user!);
    print(class_);
  });

  test("Dart interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface1"]!;
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("abstract class Interface1 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(dartSerialzer.serializeGetterDeclaration(e)));
    }
  });

  test("Dart interface implementing one interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface2"]!;
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeInterface(entity).trim();

    expect(class_, startsWith("abstract class Interface2 extends IBase {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(dartSerialzer.serializeGetterDeclaration(e)));
    }
  });

  test("Dart interface implementing multiple interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface3"]!;
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("abstract class Interface3 extends IBase, IBase2 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(dartSerialzer.serializeGetterDeclaration(e)));
    }
    print(class_);
  });
}
