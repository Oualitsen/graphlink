import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';

void main() {
  test("test serializeGetterDeclaration when Boolean is Object", () {
    final GLParser g = GLParser(identityFields: [
      "id"
    ], mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boolean_getter_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var person = g.getTypeByName("Person")!;
    var aged = person.fields.where((f) => f.name.token == "aged").first;

    var agedDeclaration =
        javaSerialzer.serializeGetterDeclaration(aged, skipModifier: true);
    expect(agedDeclaration, "Boolean getAged()");
  });

  test("test serializeGetterDeclaration when Boolean is a primitive", () {
    final GLParser g = GLParser(identityFields: [
      "id"
    ], mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boolean_getter_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var person = g.getTypeByName("Person")!;
    var aged = person.fields.where((f) => f.name.token == "aged").first;

    var agedDeclaration =
        javaSerialzer.serializeGetterDeclaration(aged, skipModifier: true);
    expect(agedDeclaration, "boolean isAged()");
  });

  test("test boxed types", () {
    final GLParser g = GLParser(identityFields: [
      "id"
    ], mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boxed_types.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var person = g.getTypeByName("Person")!;
    var ids = person.fields.where((f) => f.name.token == "ids").first;

    var idsSerial =
        javaSerialzer.serializeGetterDeclaration(ids, skipModifier: true);

    expect(idsSerial, "java.util.List<Integer> getIds()");
  });

  test("primitive types to boxed types when nullable", () {
    final GLParser g = GLParser(identityFields: [
      "id"
    ], mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boxed_types.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var person = g.getTypeByName("Person")!;
    var age = person.fields.where((f) => f.name.token == "age").first;
    var age2 = person.fields.where((f) => f.name.token == "age2").first;

    var ageSerial = javaSerialzer.serializeField(age, false, true);
    var age2Serial = javaSerialzer.serializeField(age2, false, true);
    expect(ageSerial, "private Integer age;");
    expect(age2Serial, "private int age2;");
  });
}
