import 'dart:io';

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

  test("input and type serialization as records", () {
    final GQGrammar g = GQGrammar(
      identityFields: ["id"],
      typeMap: typeMapping,
      mode: CodeGenerationMode.server,
      javaInputsAsRecord: true,
      javaTypesAsRecord: true,
    );
    final text = File("test/serializers/java/types/record_serialization.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var javaSerial = JavaSerializer(g);
    var input = g.inputs["PersonInput"]!;
    var inputSerial = javaSerial.serializeInputDefinition(input);
    expect(inputSerial.trim(), "public record PersonInput (String name, Integer age) {}");

    var type = g.getType("Person");
    var typeSerial = javaSerial.serializeTypeDefinition(type);
    expect(typeSerial.trim(), "public record Person (String name, Integer age, Boolean married) {}");
  });

  test("input and type serialization as records with decorators", () {
    final GQGrammar g = GQGrammar(
      identityFields: ["id"],
      typeMap: typeMapping,
      mode: CodeGenerationMode.server,
      javaInputsAsRecord: true,
      javaTypesAsRecord: true,
    );
    final text = File("test/serializers/java/types/record_serialization.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var javaSerial = JavaSerializer(g);

    var type = g.getType("Car");
    var typeSerial = javaSerial.serializeTypeDefinition(type);
    expect(
        typeSerial,
        stringContainsInOrder([
          "@lombok.experimental.FieldNameConstants()",
          "public record Car",
          '@com.fasterxml.jackson.annotation.JsonProperty(value = "car_model")',
          "String model,",
          '@com.fasterxml.jackson.annotation.JsonProperty(value = "car_make")',
          " String make",
          "{}"
        ]));

    var input = g.inputs["CarInput"]!;
    var inputSerial = javaSerial.serializeInputDefinition(input);
    expect(
        inputSerial,
        stringContainsInOrder([
          "@lombok.experimental.FieldNameConstants()",
          "public record CarInput",
          '@com.fasterxml.jackson.annotation.JsonProperty(value = "car_model")',
          "String model,",
          '@com.fasterxml.jackson.annotation.JsonProperty(value = "car_make")',
          " String make",
          "{}"
        ]));
  });

  test("interface serialization when types as records", () {
    final GQGrammar g = GQGrammar(
      identityFields: ["id"],
      typeMap: typeMapping,
      mode: CodeGenerationMode.server,
      javaInputsAsRecord: true,
      javaTypesAsRecord: true,
    );
    final text = File("test/serializers/java/types/record_serialization.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var javaSerial = JavaSerializer(g);

    var iface = g.interfaces["Entity"]!;
    var interfaceSerial = javaSerial.serializeTypeDefinition(iface);

    expect(interfaceSerial,
        stringContainsInOrder(["public interface Entity {", "String id();", "String creationDate();"]));
  });

  test("type serialization records when implementing interfaces", () {
    final GQGrammar g = GQGrammar(
      identityFields: ["id"],
      typeMap: typeMapping,
      mode: CodeGenerationMode.server,
      javaInputsAsRecord: true,
      javaTypesAsRecord: true,
    );
    final text = File("test/serializers/java/types/record_serialization.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var javaSerial = JavaSerializer(g);

    var iface = g.getType("MyType");
    var typeSerial = javaSerial.serializeTypeDefinition(iface);
    expect(typeSerial, contains("MyType implements Entity"));
  });
}
