import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';

void main() {

  test("input serialization as records", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial = JavaSerializer(
      g,
      inputsAsRecords: true,
      typesAsRecords: true,
      generateJsonMethods: false,
    );
    var input = g.inputs["PersonInput"]!;
    var inputSerial = javaSerial.serializeInputDefinition(input, "").trim();
    expect(inputSerial,
        startsWith("public record PersonInput(String name, Integer age) {"));
    expect(inputSerial, endsWith("}"));
  });

  test("type serialization as records", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial = JavaSerializer(g,
        inputsAsRecords: true,
        typesAsRecords: true,
        generateJsonMethods: false);

    var type = g.getTypeByName("Person")!;

    var typeSerial = javaSerial.serializeTypeDefinition(type, "").trim();
    expect(
        typeSerial,
        startsWith(
            "public record Person(String name, Integer age, Boolean married) {"));
    expect(typeSerial, endsWith("}"));
  });

  test("type serialization as records with decorators", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial =
        JavaSerializer(g, inputsAsRecords: true, typesAsRecords: true);

    var type = g.getTypeByName("Car")!;
    var typeSerial = javaSerial.serializeTypeDefinition(type, "");

    expect(
        typeSerial.split("\n").map((e) => e.trim()).toList(),
        containsAllInOrder([
          '@lombok.experimental.FieldNameConstants()',
          'public record Car(@com.fasterxml.jackson.annotation.JsonProperty(value = "car_model")  String model, @com.fasterxml.jackson.annotation.JsonProperty(value = "car_make")  String make) {',
          '}'
        ]));
  });

  test("input serialization as records with decorators", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial =
        JavaSerializer(g, inputsAsRecords: true, typesAsRecords: true);

    var input = g.inputs["CarInput"]!;
    var inputSerial = javaSerial.serializeInputDefinition(input, "");
    expect(
        inputSerial,
        stringContainsInOrder([
          "@lombok.experimental.FieldNameConstants()",
          'public record CarInput(@com.fasterxml.jackson.annotation.JsonProperty(value = "car_model")  String model, @com.fasterxml.jackson.annotation.JsonProperty(value = "car_make")  String make) {',
          '}'
        ]));
  });

  test("interface serialization when types as records", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial =
        JavaSerializer(g, inputsAsRecords: true, typesAsRecords: true);

    var iface = g.interfaces["Entity"]!;
    var interfaceSerial = javaSerial.serializeTypeDefinition(iface, "");

    expect(
        interfaceSerial,
        stringContainsInOrder([
          "public interface Entity {",
          "String id();",
          "String creationDate();"
        ]));
  });

  test("type serialization records when implementing interfaces", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial =
        JavaSerializer(g, inputsAsRecords: true, typesAsRecords: true);

    var iface = g.getTypeByName("MyType")!;
    var typeSerial = javaSerial.serializeTypeDefinition(iface, "");
    expect(
        typeSerial,
        contains(
            "MyType(String id, String creationDate, String name) implements Entity"));
  });

  test("input record with @glMapsTo generates toXxx and fromXxx methods", () {
    final GLParser g = GLParser(
      identityFields: ["id"],
     
      mode: CodeGenerationMode.server,
    );
    final text =
        File("test/serializers/java/types/record_serialization.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerial =
        JavaSerializer(g, inputsAsRecords: true, typesAsRecords: true);

    var input = g.inputs["CreateAddressInput"]!;
    var inputSerial = javaSerial.serializeInputDefinition(input, "");

    expect(inputSerial, contains("public record CreateAddressInput("));
    expect(inputSerial, contains("public Address toAddress()"));
    expect(inputSerial, contains("public static CreateAddressInput fromAddress("));
  });
}
