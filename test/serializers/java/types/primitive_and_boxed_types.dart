import 'dart:io';

import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';

void main() {
  
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
