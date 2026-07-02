import 'dart:io';

import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/serializers/annotation_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/java_spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';


void main() {
 

  test("test get annotations", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    expect(userAnnotations, hasLength(3));
  });

  test("test annotation serialization", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var user = g.getTypeByName("User")!;
    var userAnnotations = user.getAnnotations(mode: g.mode);
    var annotationSerial =
        AnnotationSerializer.serializeAnnotation(userAnnotations.first);
    expect(annotationSerial, "@lombok.Getter()");
  });

  test("test annotations on inputs and input fields", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g, importPrefix: "",
        immutableTypeFields: false, immutableInputFields: false);

    var user = g.inputs["UserInput"]!;
    var userSerial = javaSerialzer.serializeInputDefinition(user);
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
    final GLParser g = GLParser(
        identityFields: ["id"],
        
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g, importPrefix: "");

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
    final GLParser g = GLParser(
        identityFields: ["id"],
        
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g, importPrefix: "");

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
    final GLParser g = GLParser(
        identityFields: ["id"],
        
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g, importPrefix: "");

    var gender = g.enums["Gender"]!;
    var genderSerial = javaSerialzer.serializeEnumDefinition(gender);
    expect(
        genderSerial,
        stringContainsInOrder([
          "@lombok.Getter()",
          "public enum Gender {",
          'male, @Json(value = "FEMALE")  female'
        ]));
  });

  test("annotations on controllers", () {
    final GLParser g = GLParser(identityFields: [
      "id"
    ], mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/annotations/type_serialization_annotations_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var springSerialzer = JavaSpringServerSerializer(g, packageName: "");
    var userCtrl = g.controllers["UserServiceController"]!;
    var userController = springSerialzer.serializeController(userCtrl);
    print(userController);
    expect(
        userController,
        stringContainsInOrder(
            ["@LoggedIn()", "@QueryMapping()", "public CompletableFuture<Map<String, Object>> getUser()"]));
  });

  test("annotations on interfaces", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.client);
    g.parse('''
    directive @Id(glClass: String = "Id",
     glImport: String = "org.springframework.data.annotation.Id",
    glOnClient: Boolean = true,
    glOnServer: Boolean = true,
    glAnnotation: Boolean = true
      )
 on FIELD_DEFINITION | FIELD
 
 interface BasicEntity {
  id: ID! @Id
 }
''');

    var serialzer = JavaSerializer(g, importPrefix: "");
    var dartSerialzer = DartSerializer(g, importPrefix: "");
    var iface = g.interfaces['BasicEntity']!;
    var javaSerial = serialzer.serializeTypeDefinition(iface);
    var dartSerial = dartSerialzer.serializeTypeDefinition(iface);

    print(javaSerial);

    expect(
        javaSerial,
        stringContainsInOrder(
            ['public interface BasicEntity', '@Id()', 'String getId();']));
    expect(
        dartSerial,
        stringContainsInOrder(
            ['abstract class BasicEntity ', '@Id()', 'String get id;']));

    
  });

  test("annotations glApplyOnFields", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);
    g.parse('''
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

    var query = g.types["Query"]!;

    var countUsers = query.getFieldByName("countUsers")!;
    expect(countUsers.getDirectiveByName("@auth"), isNotNull);
    var countAnimals = query.getFieldByName("countAnimals")!;
    expect(countAnimals.getDirectiveByName("@auth2"), isNotNull);
    expect(countAnimals.getDirectiveByName("@auth"), isNull);
    var springSerial = JavaSpringServerSerializer(g, packageName: "");
    var mainController = g.controllers["MainServiceController"]!;
    print(springSerial.serializeController(mainController));

    //print(serializer.serializeTypeDefinition(query, "com.myorg"));
  });
}
