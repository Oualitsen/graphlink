import 'dart:io';

import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
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

  test("test skipOn mode = client", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.client);

    final text = File(
            "test/serializers/java/types/type_serialization_skip_on_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var userServer = g.getTypeByName("User")!;
    var result = javaSerialzer.serializeTypeDefinition(userServer, "");
    expect(result, isNot(contains("String companyId")));
  });

  test("test skipOn mode = server", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);

    final text = File(
            "test/serializers/java/types/type_serialization_skip_on_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var userServer = g.getTypeByName("User")!;
    var result = javaSerialzer.serializeTypeDefinition(userServer, "");
    expect(result, isNot(contains("Company company")));

    var input = g.inputs["SkipInput"]!;
    var skippedInputSerialized =
        javaSerialzer.serializeInputDefinition(input, "");
    expect(skippedInputSerialized, "");

    var enum_ = g.enums["Gender"]!;
    var serializedEnum = javaSerialzer.serializeEnumDefinition(enum_, "");
    expect(serializedEnum, "");
    var type = g.getTypeByName("SkipType")!;
    var serilzedType = javaSerialzer.serializeTypeDefinition(type, "");
    expect(serilzedType, "");
  });

  test("testDecorators 2", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text = File(
            "test/serializers/java/types/type_serialization_decorators_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;

    var idField = user.fields.where((f) => f.name.token == "id").first;
    var id = javaSerialzer.serializeField(idField, false, true);
    expect(
        id, stringContainsInOrder(["@Getter", "@Setter", "private String id"]));

    var ibase = g.interfaces["IBase"]!;

    var ibaseText = javaSerialzer.serializeInterface(ibase, getters: true);
    expect(ibaseText.trim(), startsWith("@Logger"));

    var gender = g.enums["Gender"]!;
    var genderText = javaSerialzer.serializeEnumDefinition(gender, "");
    expect(genderText.trim(), startsWith("@Logger"));

    var input = g.inputs["UserInput"]!;
    var inputText = javaSerialzer.serializeInputDefinition(input, "");
    expect(inputText.trim(), contains("@Input"));
  });

  test("serializeField", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var id = javaSerialzer.serializeField(idField, false, true);
    expect(id, "private String id;");
  });

  test("serializeArgument", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var id = javaSerialzer.serializeArgumentField(idField);
    expect(id, "String id");
  });

  test("serializeType", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);
    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var listExample =
        user.fields.where((f) => f.name.token == "listExample").first;
    var id = javaSerialzer.serializeType(idField.type, false);
    var list = javaSerialzer.serializeType(listExample.type, false);
    expect(id, "String");
    expect(list, "List<String>");
  });

  test("serializeEnumDefinition", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g, generateJsonMethods: true);
    var genderEnum = g.enums["Gender"]!;
    var enum_ = javaSerialzer.serializeEnumDefinition(genderEnum, "");
    expect(enum_.split("\n").map((e) => e.trim()).toList(),
        containsAllInOrder(['public enum Gender {', 'male, female;', '}']));
  });

  test("serializeGetterDeclaration", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var marriedField =
        user.fields.where((f) => f.name.token == "married").first;

    var getterWithoutModifier =
        javaSerialzer.serializeGetterDeclaration(idField, skipModifier: true);
    var getterWithModifier =
        javaSerialzer.serializeGetterDeclaration(idField, skipModifier: false);
    var marriedGetter = javaSerialzer.serializeGetterDeclaration(marriedField,
        skipModifier: false);
    expect(getterWithoutModifier, "String getId()");
    expect(getterWithModifier, "public String getId()");
    expect(marriedGetter, "public Boolean getMarried()");
  });

  test("serializeSetter", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var middleName =
        user.fields.where((f) => f.name.token == "middleName").first;

    var setId = javaSerialzer.serializeSetter(idField, user);
    var setMiddleName = javaSerialzer.serializeSetter(middleName, user);
    print(setMiddleName);

    expect(
        setMiddleName.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public void setMiddleName(String middleName) {',
          'this.middleName = middleName;',
          '}',
        ]));

    expect(
      setId.split("\n").map((e) => e.trim()),
      containsAllInOrder(
          ['public void setId(String id) {', 'this.id = id;', '}']),
    );
  });

  test("serializeGetter", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var javaSerialzer = JavaSerializer(g);

    var user = g.getTypeByName("User")!;
    var idField = user.fields.where((f) => f.name.token == "id").first;
    var married = user.fields.where((f) => f.name.token == "married").first;
    var middleName =
        user.fields.where((f) => f.name.token == "middleName").first;

    var getId = javaSerialzer.serializeGetter(idField, user);
    var isMarried = javaSerialzer.serializeGetter(married, user);
    var middleNameText = javaSerialzer.serializeGetter(middleName, user);
    print(getId);

    expect(getId,
        stringContainsInOrder(["public String getId() {", "return id;", "}"]));
    expect(
        middleNameText,
        stringContainsInOrder([
          "public String getMiddleName() {",
          "return middleName;",
          "}",
        ]));
    expect(
        isMarried,
        stringContainsInOrder(
            ["public Boolean getMarried() {", "return married;"]));
  });

  test("Java type serialization", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var user = g.getTypeByName("User")!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeTypeDefinition(user, "");
    expect(
      class_.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "public class User {",
        "private String id;",
        "private String name;",
        "private String middleName;",
        "private Boolean married;",
        "private List<String> listExample;",
        "}"
      ]),
    );
  });

  test("Java input serialization", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/type_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var user = g.inputs["UserInput"];
    var javaSerialzer = JavaSerializer(g,
        immutableInputFields: false, immutableTypeFields: false);
    var class_ = javaSerialzer.serializeInputDefinition(user!, "");

    expect(
      class_.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "public class UserInput {",
        "private String id;",
        "private String name;",
        "private String middleName;",
        "}"
      ]),
    );
  });

  test("Java interface serialization", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/interface_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var entity = g.interfaces["Interface1"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity, getters: true).trim();
    expect(class_, startsWith("public interface Interface1 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(
          class_,
          contains(
              javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
  });

  test("Java interface implementing one interface serialization", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/interface_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var entity = g.interfaces["Interface2"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity, getters: true).trim();
    print(class_);
    expect(class_, startsWith("public interface Interface2 extends IBase {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(
          class_,
          contains(
              javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
  });

  test("Java interface implementing multiple interface serialization", () {
    final GLParser g = GLParser(identityFields: ["id"], typeMap: typeMapping);
    final text =
        File("test/serializers/java/types/interface_serialization_test.graphql")
            .readAsStringSync();

    g.parse(text);

    var entity = g.interfaces["Interface3"]!;
    var javaSerialzer = JavaSerializer(g);
    var class_ = javaSerialzer.serializeInterface(entity, getters: true).trim();
    expect(class_,
        startsWith("public interface Interface3 extends IBase, IBase2 {"));
    expect(class_, endsWith("}"));
    for (var e in entity.fields) {
      expect(
          class_,
          contains(
              javaSerialzer.serializeGetterDeclaration(e, skipModifier: true)));
    }
  });

  test("Repository serialization", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);
    final text = File(
            "test/serializers/java/types/repository_serialization_test.graphql")
        .readAsStringSync();

    g.parse(text);

    var repo = g.repositories["UserRepository"]!;
    var serialzer = SpringServerSerializer(g);
    var repoSerial = serialzer.serializeRepository(repo, "com.myorg");
    expect(
        repoSerial,
        stringContainsInOrder([
          "@Repository",
          "public interface UserRepository extends org.springframework.data.mongodb.repository.MongoRepository<User, String>",
          'User findById(@org.springframework.data.repository.query.Param(value = "id") String id);',
          "}"
        ]));
  });

  test("decorators on interfaces ", () {
    final GLParser g = GLParser(
        identityFields: ["id"],
        typeMap: typeMapping,
        mode: CodeGenerationMode.server);
    g.parse('''
    directive @Id(
    glClass: String = "Id",
    glImport: String = "org.springframework.data.annotation.Id",
    glOnClient: Boolean = false,
    glOnServer: Boolean = true,
    glAnnotation: Boolean = true
)
 on FIELD_DEFINITION | FIELD

  interface BasicEntity {
    id: ID! @Id
  }
  
  type User implements BasicEntity {
    id: ID!
    name: String
  }

''');

    var user = g.getTypeByName("User")!;
    var serializer = JavaSerializer(g);

    print(serializer.serializeTypeDefinition(user, "com.myorg"));
  });

  test("serialize input with null checks", () {
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
    input UserInput {
      id: ID
      name: String!
    }
''');

    var userInput = g.inputs['UserInput']!;
    var serializer = JavaSerializer(g,
        immutableInputFields: false, immutableTypeFields: false);
    var serializedInput =
        serializer.serializeInputDefinition(userInput, "com.myorg");
    // nullcheck on contrcutor
    var lines = serializedInput
        .split('\n')
        .where((element) => element.isNotEmpty)
        .map((e) => e.trim())
        .toList();
    expect(
        lines,
        containsAllInOrder([
          'private UserInput(String id, String name) {',
          'Objects.requireNonNull(name);',
          'this.id = id;',
          'this.name = name;'
        ]));
    // nullcheck on setter
    expect(
        lines,
        containsAllInOrder([
          'public void setName(String name) {',
          'Objects.requireNonNull(name);',
          'this.name = name;'
        ]));

    // nullcheck on getter
    expect(
        lines,
        containsAllInOrder([
          'public String getName() {',
          'Objects.requireNonNull(name);',
          'return name;',
        ]));

    // no nullcheck on setter id
    expect(
        lines,
        containsAllInOrder(
            ['public void setId(String id) {', 'this.id = id;']));

    // no nullcheck on getter id
    expect(
        lines,
        containsAllInOrder([
          'public String getId() {',
          'return id;',
        ]));
  });

  test("serialize no null check on java primitives", () {
    final typeMapping = {
      "ID": "String",
      "String": "String",
      "Float": "Double",
      "Int": "int",
      "Boolean": "Boolean",
      "Null": "null",
      "Long": "Long"
    };
    final GLParser g =
        GLParser(typeMap: typeMapping, mode: CodeGenerationMode.server);
    g.parse('''
    input UserInput {
      
      age: Int!
    }
''');

    var userInput = g.inputs['UserInput']!;
    var serializer = JavaSerializer(g,
        immutableInputFields: false, immutableTypeFields: false);
    var serializedInput =
        serializer.serializeInputDefinition(userInput, "com.myorg");
    // no nullcheck on contrcutor primitives
    var lines = serializedInput
        .split('\n')
        .where((element) => element.isNotEmpty)
        .map((e) => e.trim())
        .toList();
    expect(
        lines,
        containsAllInOrder(
            ['private UserInput(int age) {', 'this.age = age;', '}']));
    // no nullcheck on setter
    expect(
        lines,
        containsAllInOrder(
            ['public void setAge(int age) {', 'this.age = age;', '}']));

    // no nullcheck on getter
    expect(lines,
        containsAllInOrder(['public int getAge() {', 'return age;', '}']));

    // no nullcheck on setter id
  });

  test(
      "serialize input: final field with no getter when immutableInputFields = true",
      () {
    final GLParser g = GLParser(typeMap: {}, mode: CodeGenerationMode.server);
    g.parse('''
    input UserInput {
      age: String
    }
''');

    var userInput = g.inputs['UserInput']!;
    var serializer = JavaSerializer(g,
        immutableInputFields: true, immutableTypeFields: false);
    var serializedInput =
        serializer.serializeInputDefinition(userInput, "com.myorg");

    print(serializedInput);
    expect(serializedInput, contains("private final String age;"));
    expect(serializedInput, contains("public String getAge()"));
    expect(serializedInput, isNot(contains("public void setAge")));
  });

  test(
      "serialize type: final field with no getter when immutableTypeFields = true",
      () {
    final GLParser g = GLParser(typeMap: {}, mode: CodeGenerationMode.server);
    g.parse('''
    type UserInput {
      age: String
    }
''');

    var userInput = g.types['UserInput']!;
    var serializer = JavaSerializer(g,
        immutableInputFields: true, immutableTypeFields: true);
    var serializedInput =
        serializer.serializeTypeDefinition(userInput, "com.myorg");

    print(serializedInput);
    expect(serializedInput, contains("private final String age;"));
    expect(serializedInput, contains("public String getAge()"));
    expect(serializedInput, isNot(contains("public void setAge")));
  });
}
