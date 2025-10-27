import 'dart:io';

import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("dart test skipOn mode = client", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], mode: CodeGenerationMode.client);

    final text = File("test/serializers/dart/types/type_serialization_skip_on_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = DartSerializer(g);
    var user = g.getTypeByName("User")!;
    var result = javaSerialzer.serializeTypeDefinition(user, "");
    expect(result, isNot(contains("String companyId")));
  });

  test("dart test skipOn mode = server", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], mode: CodeGenerationMode.server);

    final text = File("test/serializers/dart/types/type_serialization_skip_on_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = DartSerializer(g);
    var user = g.getTypeByName("User")!;
    var result = javaSerialzer.serializeTypeDefinition(user, "");
    expect(result, isNot(contains("Company company")));

    var input = g.inputs["SkipInput"]!;
    var skippedInputSerialized = javaSerialzer.serializeInputDefinition(input, "");
    expect(skippedInputSerialized, "");

    var enum_ = g.enums["Gender"]!;
    var serializedEnum = javaSerialzer.serializeEnumDefinition(enum_, "");
    expect(serializedEnum, "");
    var type = g.getTypeByName("SkipType")!;
    var serilzedType = javaSerialzer.serializeTypeDefinition(type, "");
    expect(serilzedType, "");
  });

  test("Dart type serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.getTypeByName("User")!;
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeTypeDefinition(user, "");
    expect(
      class_.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "class User {",
        "final String id;",
        "final String name;",
        "final String? middleName;",
        "User({required this.id, required this.name, this.middleName});",
        "}"
      ]),
    );
  });

  test("Dart input serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"]);
    final text = File("test/serializers/dart/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.inputs["UserInput"];
    var dartSerialzer = DartSerializer(g);
    var class_ = dartSerialzer.serializeInputDefinition(user!, "");
    expect(
      class_.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "class UserInput {",
        "final String? id;",
        "final String name;",
        "final String? middleName;",
        "UserInput({",
        "this.id,",
        "required this.name,",
        "this.middleName,",
        "});",
        "}"
      ]),
    );
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
  });
}
