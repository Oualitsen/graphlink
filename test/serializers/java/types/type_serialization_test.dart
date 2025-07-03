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

  test("test list as array", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.client);

    final text =
        File("test/serializers/java/types/type_serialization_list_as_array.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var userServer = g.getType("User");
    var result = javaSerialzer.serializeTypeDefinition(userServer);
    expect(result, contains("String[] array"));
    expect(result, contains("String[][] arrayOfArrays"));
    expect(result, contains("java.util.List<java.util.List<String>> listOfLists"));
  });

  test("test skipOn mode = client", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.client);

    final text =
        File("test/serializers/java/types/type_serialization_skip_on_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var userServer = g.getType("User");
    var result = javaSerialzer.serializeTypeDefinition(userServer);
    expect(result, isNot(contains("String companyId")));
  });

  test("test skipOn mode = server", () {
    final GQGrammar g =
        GQGrammar(identityFields: ["id"], typeMap: typeMapping, mode: CodeGenerationMode.server);

    final text =
        File("test/serializers/java/types/type_serialization_skip_on_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var userServer = g.getType("User");
    var result = javaSerialzer.serializeTypeDefinition(userServer);
    expect(result, isNot(contains("Company company")));

    var input = g.inputs["SkipInput"]!;
    var skipedInputSerialized = javaSerialzer.serializeInputDefinition(input);
    expect(skipedInputSerialized, "");

    var enum_ = g.enums["Gender"]!;
    var serializedEnum = javaSerialzer.serializeEnumDefinition(enum_);
    expect(serializedEnum, "");
    var type = g.getType("SkipType");
    var serilzedType = javaSerialzer.serializeTypeDefinition(type);
    expect(serilzedType, "");
  });

  test("testDecorators", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_decorators_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);

    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getType("User");

    var idField = user.fields.where((f) => f.name == "id").first;
    var id = javaSerialzer.serializeField(idField);
    expect(id, "@Getter @Setter private String id;");

    var ibase = g.interfaces["IBase"]!;

    var ibaseText = javaSerialzer.serializeInterface(ibase);
    expect(ibaseText.trim(), startsWith("@Logger"));

    var gender = g.enums["Gender"]!;
    var genderText = javaSerialzer.serializeEnumDefinition(gender);
    expect(genderText.trim(), startsWith("@Logger"));

    var input = g.inputs["UserInput"]!;
    var inputText = javaSerialzer.serializeInputDefinition(input);
    expect(inputText.trim(), startsWith("@Input"));
  });

  test("serializeField", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var id = javaSerialzer.serializeField(idField);
    expect(id, "private String id;");
  });

  test("serializeArgument", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var id = javaSerialzer.serializeArgument(idField);
    expect(id, "final String id");
  });

  test("serializeType", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var listExample = user.fields.where((f) => f.name == "listExample").first;
    var id = javaSerialzer.serializeType(idField.type, false);
    var list = javaSerialzer.serializeType(listExample.type, false);
    expect(id, "String");
    expect(list, "java.util.List<String>");
  });

  test("serializeEnumDefinition", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);
    var genderEnum = g.enums["Gender"]!;
    var enum_ = javaSerialzer.serializeEnumDefinition(genderEnum);
    expect(
        enum_.trim(),
        """
public enum Gender {
\tmale, female
}
"""
            .trim());
  });

  test("serializeGetterDeclaration", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var marriedField = user.fields.where((f) => f.name == "married").first;

    var getterWithoutModifier = javaSerialzer.serializeGetterDeclaration(idField, skipModifier: true);
    var getterWithModifier = javaSerialzer.serializeGetterDeclaration(idField, skipModifier: false);
    var marriedGetter = javaSerialzer.serializeGetterDeclaration(marriedField, skipModifier: false);
    expect(getterWithoutModifier, "String getId()");
    expect(getterWithModifier, "public String getId()");
    expect(marriedGetter, "public Boolean isMarried()");
  });

  test("serializeSetter", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var middleName = user.fields.where((f) => f.name == "middleName").first;

    var setId = javaSerialzer.serializeSetter(idField);
    var setMiddleName = javaSerialzer.serializeSetter(middleName);

    expect(
        setMiddleName,
        """
public void setMiddleName(final String middleName) {
\tthis.middleName = middleName;
}
"""
            .trim());

    expect(
        setId,
        """
public void setId(final String id) {
\tjava.util.Objects.requireNonNull(id);
\tthis.id = id;
}
"""
            .trim());
  });

  test("serializeGetter", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);
    var javaSerialzer = JavaSerializer(g);

    var user = g.getType("User");
    var idField = user.fields.where((f) => f.name == "id").first;
    var married = user.fields.where((f) => f.name == "married").first;
    var middleName = user.fields.where((f) => f.name == "middleName").first;

    var getId = javaSerialzer.serializeGetter(idField);
    var isMarried = javaSerialzer.serializeGetter(married);
    var middleNameText = javaSerialzer.serializeGetter(middleName);

    expect(
        getId,
        stringContainsInOrder(
            ["public String getId() {", "java.util.Objects.requireNonNull(id);", "return id;", "}"]));
    expect(
        middleNameText,
        stringContainsInOrder([
          "public String getMiddleName() {",
          "return middleName;",
          "}",
        ]));
    expect(
        isMarried,
        stringContainsInOrder([
          "public Boolean isMarried() {",
          "java.util.Objects.requireNonNull(married);",
          "return married;"
        ]));
  });

  test("Java type serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.getType("User");
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeTypeDefinition(user);
    print(class_);
  });

  test("Java input serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/type_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var user = g.inputs["UserInput"];
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInputDefinition(user!);
    print(class_);
  });

  test("Java interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface1"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("public interface Interface1 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
    print(class_);
  });

  test("Java interface implementing one interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface2"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();

    expect(class_, startsWith("public interface Interface2 extends IBase {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
  });

  test("Java interface implementing multiple interface serialization", () {
    final GQGrammar g = GQGrammar(identityFields: ["id"], typeMap: typeMapping);
    final text = File("test/serializers/java/types/interface_serialization_test.graphql").readAsStringSync();
    var parser = g.buildFrom(g.fullGrammar().end());
    var parsed = parser.parse(text);
    expect(parsed is Success, true);

    var entity = g.interfaces["Interface3"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity).trim();
    expect(class_, startsWith("public interface Interface3 extends IBase, IBase2 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(class_, contains(javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
  });
}
