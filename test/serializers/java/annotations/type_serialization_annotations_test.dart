import 'dart:io';

import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';

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
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    expect(userAnnotations, hasLength(3));
  });

  test("test annotation serialization", () {
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    var annotationSerial = AnnotationSerializer.serializeAnnotation(userAnnotations.first);
    expect(annotationSerial, "@lombok.Getter()");
  });

  test("test annotations on inputs and input fields", () {
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g, immutableTypeFields: false, immutableInputFields: false);

    var user = g.inputs["UserInput"]!;
    var userSerial = javaSerialzer.serializeInputDefinition(user, "");
    print(userSerial);
    expect(
        userSerial,
        stringContainsInOrder([
          "@lombok.Getter()",
          "public class UserInput {",
          '@Json(value = "my_name")',
          "private String name;",
        ]));
  });

  test("test annotations on interfaces and its fields", () {
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var ibase = g.interfaces["IBase"]!;
    var ibaseSerial = javaSerialzer.serializeInterface(ibase, getters: true);

    expect(
        ibaseSerial,
        stringContainsInOrder([
          "@lombok.Getter()",
          'public interface IBase',
          '@Json(value = "my_id")',
          'String getId();'
        ]));
  });

  test("test annotations on types", () {
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
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
    final GLGrammar g =
        GLGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);
    final text =
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var gender = g.enums["Gender"]!;
    var genderSerial = javaSerialzer.serializeEnumDefinition(gender, "");
    expect(
        genderSerial,
        stringContainsInOrder(
            ["@lombok.Getter()", "public enum Gender {", 'male, @Json(value = "FEMALE")  female']));
  });

  test("annotations on controllers", () {
    final GLGrammar g = GLGrammar(identityFields: [
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
        File("test/serializers/java/annotations/type_serialization_annotations_test.graphql")
            .readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var springSerialzer = SpringServerSerializer(g);
    var userCtrl = g.controllers["UserServiceController"]!;
    var userController = springSerialzer.serializeController(userCtrl, "");
    expect(userController,
        stringContainsInOrder(["@LoggedIn()", "@QueryMapping()", "public User getUser()"]));
  });

  test("annotations on interfaces", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);
    var parsed = g.parse('''
    directive @Id(glClass: String = "Id",
     glImport: String = "org.springframework.data.annotation.Id",
    glOnClient: Boolean = false,
    glOnServer: Boolean = true,
    glAnnotation: Boolean = true
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
    var javaSerial = serialzer.serializeTypeDefinition(iface, "com.myorg");
    var dartSerial = dartSerialzer.serializeTypeDefinition(iface, "com.myorg");

    expect(javaSerial,
        stringContainsInOrder(['public interface BasicEntity', '@Id()', 'String getId();']));

    expect(dartSerial,
        stringContainsInOrder(['abstract class BasicEntity ', '@Id()', 'String get id;']));

    print(serialzer.serializeTypeDefinition(iface, "com.myorg"));
    print(dartSerialzer.serializeTypeDefinition(iface, "com.myorg"));
  });

  test("annotations glApplyOnFields", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);
    var parsed = g.parse('''
    directive @auth(
      glClass: String = "Auth",
      glOnClient: Boolean = false,
      glOnServer: Boolean = true,
      glAnnotation: Boolean = true
      glApplyOnFields: Boolean = false
      )
 on FIELD_DEFINITION | FIELD

 directive @auth2(
      glClass: String = "Auth2",
      glOnClient: Boolean = false,
      glOnServer: Boolean = true,
      glAnnotation: Boolean = true
      glApplyOnFields: Boolean = false
      )
 on FIELD_DEFINITION | FIELD

 type Query @auth(glApplyOnFields: true) {
  countUsers: Int ${glServiceName}(name: "MainService")
 }

 extend type Query @auth2(glApplyOnFields: true) {
  countAnimals: Int ${glServiceName}(name: "MainService")
 }
 
 
''');
    expect(parsed is Success, true);
    var query = g.types["Query"]!;

    var countUsers = query.getFieldByName("countUsers")!;
    expect(countUsers.getDirectiveByName("@auth"), isNotNull);
    var countAnimals = query.getFieldByName("countAnimals")!;
    expect(countAnimals.getDirectiveByName("@auth2"), isNotNull);
    expect(countAnimals.getDirectiveByName("@auth"), isNull);
    var springSerial = SpringServerSerializer(g);
    var mainController = g.controllers["MainServiceController"]!;
    print(springSerial.serializeController(mainController, "com.myorg"));

    //print(serializer.serializeTypeDefinition(query, "com.myorg"));
  });
}
