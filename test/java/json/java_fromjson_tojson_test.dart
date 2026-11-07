import 'dart:io';

import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void saveToFile(String data, String fileName) {
  File(fileName).writeAsStringSync(data);
}

void main() {
  test("Java enum to json", () {
    final GLParser g = GLParser();

    g.parse('''
  enum Gender {male, female}
''');

    var gender = g.enums["Gender"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var genderSerial = serializer.serializeEnumDefinition(gender);
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "public String toJson() {",
          "switch(this) {",
          "case male:",
          'return "male";',
          "case female:",
          'return "female";',
          "}",
        ]));
  });

  test("Java enum from json", () {
    final GLParser g = GLParser();

    g.parse('''
  enum Gender {male, female}
''');

    var gender = g.enums["Gender"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var genderSerial = serializer.serializeEnumDefinition(gender);
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "public static Gender fromJson(String value) {",
          "if (value == null) {",
          "return null;",
          "}",
          "switch(value) {",
          'case "male":',
          "return male;",
          'case "female":',
          "return female;",
          "}",
        ]));
  });

  test("Java input tojson", () {
    final GLParser g = GLParser();

    g.parse('''
  scalar Long
  enum Gender {male, female}
  input CityInput {
    name: String!
  }
  input UserInput {
    id: ID
    name: String!
    middleName: String
    dateOfBirth: Long
    gender: Gender
    gender2: Gender!
    names: [String!]!
    deepGender: [[Gender]]!
    genders1: [Gender!]!
    genders2: [Gender]!
    genders3: [Gender!]
    city: CityInput
    city2: CityInput!
  }
''');

    var userInput = g.inputs["UserInput"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
      inputSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> glMap__ = new HashMap<>();',
        'glMap__.put("id", id);',
        'glMap__.put("name", name);',
        'glMap__.put("middleName", middleName);',
        'glMap__.put("dateOfBirth", dateOfBirth);',
        'glMap__.put("gender", gender == null ? null : gender.toJson());',
        'glMap__.put("gender2", gender2.toJson());',
        'glMap__.put("names", names.stream().collect(Collectors.toList()));',
        'glMap__.put("deepGender", deepGender.stream().map(e0 -> e0 == null ? null : e0.stream().map(e1 -> e1 == null ? null : e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList()));',
        'glMap__.put("genders1", genders1.stream().map(e0 -> e0.toJson()).collect(Collectors.toList()));',
        'glMap__.put("genders2", genders2.stream().map(e0 -> e0 == null ? null : e0.toJson()).collect(Collectors.toList()));',
        'glMap__.put("genders3", genders3 == null ? null : genders3.stream().map(e0 -> e0.toJson()).collect(Collectors.toList()));',
        'glMap__.put("city", city == null ? null : city.toJson());',
        'glMap__.put("city2", city2.toJson());',
        'return glMap__;',
        '}'
      ]),
    );
  });

  

  test("Java input tojson list of lists", () {
    final GLParser g = GLParser();

    g.parse('''
  scalar Long
  enum Gender {male, female}
  
  input UserInput {
    genders: [[Gender]]
  }
''');

    var userInput = g.inputs["UserInput"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
      inputSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> glMap__ = new HashMap<>();',
        'glMap__.put("genders", genders == null ? null : genders.stream().map(e0 -> e0 == null ? null : e0.stream().map(e1 -> e1 == null ? null : e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList()));',
        'return glMap__;',
        '}'
      ]),
    );
  });

  test("Java type tojson", () {
    final GLParser g = GLParser();

    g.parse('''
  scalar Long
  enum Gender {male, female}
  type City {
    name: String!
  }
  type User {
    id: ID
    name: String!
    middleName: String
    dateOfBirth: Long
    gender: Gender
    gender2: Gender!
    genders1: [Gender]
    genders2: [Gender!]!
    genders3: [Gender]!
    city: City
    cities: [City]
  }
''');

    var useer = g.types["User"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var userSerial = serializer.doSerializeTypeDefinition(useer);

    // same as input, so we only check for the existance of toJson method
    expect(
      userSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> glMap__ = new HashMap<>();',
        "}"
      ]),
    );
  });

  test("Java input fromJson nullable string", () {
    final GLParser g = GLParser();

    g.parse('''
  input UserInput {
    name: String
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);

    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          'json.get("name") == null ? null : (String)json.get("name")',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson non nullable string", () {
    final GLParser g = GLParser();

    g.parse('''
  input UserInput {
    name: String!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);

    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '(String)json.get("name")',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson list of  nonnullable string", () {
    final GLParser g = GLParser();

    g.parse('''
  input UserInput {
    name: [String!]!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);

    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<?>)json.get("name")).stream().map(e0 -> (String)e0).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson number", () {
    final GLParser g = GLParser();

    g.parse('''
  input UserInput {
    age: Int!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);

    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((Number)json.get("age")).intValue()',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson list of numbers", () {
    final GLParser g = GLParser();

    g.parse('''
  input UserInput {
    age: [Int!]!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<?>)json.get("age")).stream().map(e0 -> ((Number)e0).intValue()).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson enum", () {
    final GLParser g = GLParser();

    g.parse('''
  enum Gender {male female}
  input UserInput {
    gender: Gender!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          'Gender.fromJson((String)json.get("gender"))',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson list of enum", () {
    final GLParser g = GLParser();

    g.parse('''
  enum Gender {male female}
  input UserInput {
    gender: [Gender!]!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<?>)json.get("gender")).stream().map(e0 -> Gender.fromJson((String)e0)).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson input", () {
    final GLParser g = GLParser();

    g.parse('''
  input AgeInput {
    age: Int!
  }
  input UserInput {
    age: AgeInput!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          'AgeInput.fromJson((Map<String, Object>)json.get("age"))',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson input", () {
    final GLParser g = GLParser();

    g.parse('''
  input AgeInput {
    age: Int!
  }
  input UserInput {
    age: [AgeInput!]!
  }
''');

    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, importPrefix: "");
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<?>)json.get("age")).stream().map(e0 -> AgeInput.fromJson((Map<String, Object>)e0)).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java interface fromJson", () {
    final GLParser g = GLParser();

    g.parse('''
  interface BasicEntity {
    id: ID!
  }

  type User implements BasicEntity {
    id: ID!
    name: String!
  }

  type Animal implements BasicEntity {
    id: ID!
    name: String!
    ownerId: ID!
  }
''');

    var user = g.interfaces["BasicEntity"]!;
    var serializer = JavaSerializer(g, importPrefix: "");
    var userSerial = serializer.interfaces.serializeInterface(user, getters: true);

    expect(
      userSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'public interface BasicEntity {',
        'String getId();',
        'Map<String, Object> toJson();',
        'static BasicEntity fromJson(Map<String, Object> json) {',
        'String typename = (String)json.get("__typename");',
        'switch(typename) {',
        'case "User":',
        'return User.fromJson(json);',
        'case "Animal":',
        'return Animal.fromJson(json);',
        'default:',
        'throw new RuntimeException(String.format("Invalid type %s. %s does not implement BasicEntity or not defined", typename, typename));',
        '}',
        '}',
        '}'
      ]),
    );
  });
}
