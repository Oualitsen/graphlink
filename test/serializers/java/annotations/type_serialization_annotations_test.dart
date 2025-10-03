import 'dart:io';

import 'package:retrofit_graphql/src/serializers/annotation_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.inputs["UserInput"]!;
    var userSerial = javaSerialzer.serializeInputDefinition(user, "");
    expect(
        userSerial,
        stringContainsInOrder(
            ["@lombok.Getter()", "public class UserInput {", '@Json(value = "my_name")', "private String name;"]));
  });

  test("test annotations on interfaces and its fields", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;
    var userSerial = javaSerialzer.serializeTypeDefinition(user, "");
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
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var gender = g.enums["Gender"]!;
    var genderSerial = javaSerialzer.serializeEnumDefinition(gender, "");
    expect(genderSerial,
        stringContainsInOrder(["@lombok.Getter()", "public enum Gender {", 'male, @Json(value = "FEMALE")  female']));
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
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var springSerialzer = SpringServerSerializer(g);
    var userCtrl = g.controllers["UserServiceController"]!;
    var userController = springSerialzer.serializeController(userCtrl, "");

    expect(userController, stringContainsInOrder(["@LoggedIn()", "@QueryMapping", "public User getUser()"]));
  });

  test("annotations on interfaces", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);
    var parsed = g.parse('''
    directive @Id(gqClass: String = "Id",
     gqImport: String = "org.springframework.data.annotation.Id",
    gqOnClient: Boolean = false,
    gqOnServer: Boolean = true,
    gqAnnotation: Boolean = true
      )
 on FIELD_DEFINITION | FIELD
 
 interface BasicEntity {
  id: ID! @Id
 }
''');
    expect(parsed is Success, true);
    var serialzer = JavaSerializer(g);
    var dartSerialzer = DartSerializer(g);
    var iface = g.interfaces['BasicEntity']!;

    print(serialzer.serializeTypeDefinition(iface, "com.myorg"));
    print(dartSerialzer.serializeTypeDefinition(iface, "com.myorg"));
  });
}
