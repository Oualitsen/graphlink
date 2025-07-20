import 'dart:io';

import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';

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

  test("test get annotations", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getType("User");
    var userAnnotations = user.getAnnotations(mode: g.mode);
    expect(userAnnotations, hasLength(3));
  });

  test("test annotation serialization", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getType("User");
    var userAnnotations = user.getAnnotations(mode: g.mode);
    var javaSerial = JavaSerializer(g);
    var annotationSerial = AnnotationSerializer.serializeAnnotation(userAnnotations.first);
    print(annotationSerial);
    expect(annotationSerial, "@lombok.Getter()");
  });

  test("test annotations on inputs and input fields", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.inputs["UserInput"]!;
    var userSerial = javaSerialzer.serializeInputDefinition(user);
    expect(
        userSerial,
        stringContainsInOrder([
          "@lombok.Getter()",
          "public class UserInput {",
          '@Json(value = "my_name")',
          "private String name;"
        ]));
  });

  test("test annotations on interfaces and its fields", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var ibase = g.interfaces["IBase"]!;
    var ibaseSerial = javaSerialzer.serializeInterface(ibase);
    print(ibaseSerial);
    expect(
        ibaseSerial,
        stringContainsInOrder(
            ["@lombok.Getter()", 'public interface IBase', '@Json(value = "my_id")', 'String getId();']));
  });

  test("test annotations on types", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getType("User");
    var userSerial = javaSerialzer.serializeTypeDefinition(user);
    print(userSerial);
    expect(
        userSerial,
        stringContainsInOrder([
          "@lombok.Getter()",
          '@Json(value = "MyJson")',
          '@Query(value = "Select * From User wheere id = 10", native = false)',
          '@lombok.Getter()',
          '@Json(value = "_id")',
        ]));
  });

  test("test annotations on enums and enum values", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/types/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var gender = g.enums["Gender"]!;
    var genderSerial = javaSerialzer.serializeEnumDefinition(gender);
    expect(
        genderSerial,
        stringContainsInOrder(
            ["@lombok.Getter()", "public enum Gender {", 'male, @Json(value = "FEMALE")  female']));
  });

  test("test serializeGetterDeclaration when Boolean is Object", () {
    final GQGrammar g = GQGrammar(identityFields: [
      "id"
    ], typeMap: {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "Integer",
      "Boolean": "Boolean", // Boolean is an object here
      "Null": "null",
      "Long": "Long"
    }, mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boolean_getter_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var person = g.getType("Person");
    var aged = person.fields.where((f) => f.name == "aged").first;

    var agedDeclaration = javaSerialzer.serializeGetterDeclaration(aged, skipModifier: true);
    expect(agedDeclaration, "Boolean getAged()");
  });

  test("test serializeGetterDeclaration when Boolean is a primitive", () {
    final GQGrammar g = GQGrammar(identityFields: [
      "id"
    ], typeMap: {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "Integer",
      "Boolean": "boolean", // Boolean is a primitive
      "Null": "null",
      "Long": "Long"
    }, mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boolean_getter_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var person = g.getType("Person");
    var aged = person.fields.where((f) => f.name == "aged").first;

    var agedDeclaration = javaSerialzer.serializeGetterDeclaration(aged, skipModifier: true);
    expect(agedDeclaration, "boolean isAged()");
  });

  test("test boxed types", () {
    final GQGrammar g = GQGrammar(identityFields: [
      "id"
    ], typeMap: {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "int",
      "Boolean": "boolean",
      "Null": "null",
      "Long": "Long"
    }, mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boxed_types.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var person = g.getType("Person");
    var ids = person.fields.where((f) => f.name == "ids").first;

    var idsSerial = javaSerialzer.serializeGetterDeclaration(ids, skipModifier: true);

    expect(idsSerial, "java.util.List<Integer> getIds()");
  });

  test("primitive types to boxed types when nullable", () {
    final GQGrammar g = GQGrammar(identityFields: [
      "id"
    ], typeMap: {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "int",
      "Boolean": "boolean",
      "Null": "null",
      "Long": "Long"
    }, mode: CodeGenerationMode.server);
    final text = File("test/serializers/java/types/boxed_types.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var person = g.getType("Person");
    var age = person.fields.where((f) => f.name == "age").first;
    var age2 = person.fields.where((f) => f.name == "age2").first;

    var ageSerial = javaSerialzer.serializeField(age);
    var age2Serial = javaSerialzer.serializeField(age2);
    expect(ageSerial, "private Integer age;");
    expect(age2Serial, "private int age2;");
  });
}
