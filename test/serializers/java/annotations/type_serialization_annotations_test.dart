import 'dart:io';

import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
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
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    expect(userAnnotations, hasLength(3));
  });

  test("test annotation serialization", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    var annotationSerial = AnnotationSerializer.serializeAnnotation(userAnnotations.first);
    expect(annotationSerial, "@lombok.Getter()");
  });

  test("test annotations on inputs and input fields", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
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
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var ibase = g.interfaces["IBase"]!;
    var ibaseSerial = javaSerialzer.serializeInterface(ibase);
    
    expect(
        ibaseSerial,
        stringContainsInOrder(
            ["@lombok.Getter()", 'public interface IBase', '@Json(value = "my_id")', 'String getId();']));
  });

  test("test annotations on types", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;
    var userSerial = javaSerialzer.serializeTypeDefinition(user);
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
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
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


  test("annotations on controllers", () {
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
    final text = File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var springSerialzer = SpringServerSerializer(g);
    var userService = g.services["UserService"]!;
    var userController = springSerialzer.serializeController(userService);

    expect(userController, stringContainsInOrder([
      "@LoggedIn()",
      "@org.springframework.graphql.data.method.annotation.QueryMapping",
      "public User getUser()"
    ]));

    
  });
}
