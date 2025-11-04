import 'dart:io';

import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void saveToFile(String data, String fileName) {
  File(fileName).writeAsStringSync(data);
}

void main() {
  test("Java enum to json", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male, female}
''');
    expect(parsed is Success, true);
    var gender = g.enums["Gender"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var genderSerial = serializer.serializeEnumDefinition(gender, "");
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "public String toJson() {",
          "return name();",
          "}",
        ]));
  });

  test("Java enum from json", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male, female}
''');
    expect(parsed is Success, true);
    var gender = g.enums["Gender"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var genderSerial = serializer.serializeEnumDefinition(gender, "");
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "public static Gender fromJson(String value) {",
          "return Optional.ofNullable(value).map(Gender::valueOf).orElse(null);",
          "}",
        ]));
  });

  test("Java input tojson", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
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
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
      inputSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> map = new HashMap<>();',
        'map.put("id", id);',
        'map.put("name", name);',
        'map.put("middleName", middleName);',
        'map.put("dateOfBirth", dateOfBirth);',
        'map.put("gender", gender == null ? null : gender.toJson());',
        'map.put("gender2", gender2.toJson());',
        'map.put("names", names.stream().collect(Collectors.toList()));',
        'map.put("deepGender", deepGender.stream().map(e0 -> e0 == null ? null : e0.stream().map(e1 -> e1 == null ? null : e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList()));',
        'map.put("genders1", genders1.stream().map(e0 -> e0.toJson()).collect(Collectors.toList()));',
        'map.put("genders2", genders2.stream().map(e0 -> e0 == null ? null : e0.toJson()).collect(Collectors.toList()));',
        'map.put("genders3", genders3 == null ? null : genders3.stream().map(e0 -> e0.toJson()).collect(Collectors.toList()));',
        'map.put("city", city == null ? null : city.toJson());',
        'map.put("city2", city2.toJson());',
        'return map;',
        '}'
      ]),
    );
  });

  test("Java input tojson list as array", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male, female}
  input UserInput {
    names: [String!]! ${gqArray}
    genderList: [Gender] ${gqArray}
    genderList2: [[Gender!]] ${gqArray}
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var inputSerial = serializer.generateToJson(userInput.fields, userInput);

    expect(
      inputSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> map = new HashMap<>();',
        'map.put("names", names == null ? null : Stream.of(names).map(e0 -> e0).collect(Collectors.toList()));',
        'map.put("genderList", genderList == null ? null : Stream.of(genderList).map(e0 -> e0 == null ? null : e0.toJson()).collect(Collectors.toList()));',
        'map.put("genderList2", genderList2 == null ? null : Stream.of(genderList2).map(e0 -> e0 == null ? null : Stream.of(e0).map(e1 -> e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList()));',
        'return map;',
        '}'
      ]),
    );
  });

  test("Java input tojson list of lists", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  scalar Long
  enum Gender {male, female}
  
  input UserInput {
    genders: [[Gender]]
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
      inputSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> map = new HashMap<>();',
        'map.put("genders", genders == null ? null : genders.stream().map(e0 -> e0 == null ? null : e0.stream().map(e1 -> e1 == null ? null : e1.toJson()).collect(Collectors.toList())).collect(Collectors.toList()));',
        'return map;',
        '}'
      ]),
    );
  });

  test("Java type tojson", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
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
    expect(parsed is Success, true);
    var useer = g.types["User"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var userSerial = serializer.doSerializeTypeDefinition(useer);

    // same as input, so we only check for the existance of toJson method
    expect(
      userSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        'public Map<String, Object> toJson() {',
        'Map<String, Object> map = new HashMap<>();',
        "}"
      ]),
    );
  });

  test("Java input fromJson nullable string", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input UserInput {
    name: String
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
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
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input UserInput {
    name: String!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
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
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input UserInput {
    name: [String!]!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);

    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<Object>)json.get("name")).stream().map(json0 -> (String)json0).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson number", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input UserInput {
    age: Int!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
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
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input UserInput {
    age: [Int!]!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<Object>)json.get("age")).stream().map(json0 -> ((Number)json0).intValue()).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson enum", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male female}
  input UserInput {
    gender: Gender!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
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
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male female}
  input UserInput {
    gender: [Gender!]!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<Object>)json.get("gender")).stream().map(json0 -> Gender.fromJson((String)json0)).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java input fromJson input", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input AgeInput {
    age: Int!
  }
  input UserInput {
    age: AgeInput!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
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
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  input AgeInput {
    age: Int!
  }
  input UserInput {
    age: [AgeInput!]!
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;

    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var fromJson = serializer.generateFromJson(
        userInput.getSerializableFields(g.mode), "UserInput", userInput);
    expect(
        fromJson.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          'public static UserInput fromJson(Map<String, Object> json) {',
          'return new UserInput(',
          '((List<Object>)json.get("age")).stream().map(json0 -> AgeInput.fromJson((Map<String, Object>)json0)).collect(Collectors.toList())',
          ');',
          "}"
        ]));
  });

  test("Java interface fromJson", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
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
    expect(parsed is Success, true);
    var user = g.interfaces["BasicEntity"]!;
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var userSerial = serializer.serializeInterface(user, getters: true);

    expect(
      userSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'public interface BasicEntity {',
        'String getId();',
        'Map<String, Object> toJson();',
        'static BasicEntity fromJson(Map<String, Object> json) {',
        'String typename = (String)json.get("__typename");',
        'switch(typename) {',
        'case "User": return User.fromJson(json);',
        'case "Animal": return Animal.fromJson(json);',
        'default: throw new RuntimeException(String.format("Invalid type %s. %s does not implement BasicEntity or not defined", typename, typename));',
        '}',
        '}',
        '}'
      ]),
    );
  });
}
