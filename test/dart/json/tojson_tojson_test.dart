import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() {
  test("enum to json", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male, female}
''');
    expect(parsed is Success, true);
    var gender = g.enums["Gender"]!;
    var serializer = DartSerializer(g);
    var genderSerial = serializer.serializeEnumDefinition(gender);
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "String toJson() {",
          'switch(this) {',
          'case male: return "male";',
          'case female: return "female";',
          '}',
        ]));
  });

  test("enum from json", () {
    final GQGrammar g = GQGrammar();

    var parsed = g.parse('''
  enum Gender {male, female}
''');
    expect(parsed is Success, true);
    var gender = g.enums["Gender"]!;
    var serializer = DartSerializer(g);
    var genderSerial = serializer.serializeEnumDefinition(gender);
    expect(
        genderSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "static Gender fromJson(String value) {",
          'switch(value) {',
          'case "male": return male;',
          'case "female": return female;',
          'default: throw ArgumentError("Invalid Gender: \$value");',
          '}',
          '}',
        ]));
  });

  test("input tojson", () {
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
    names: [String!]!
    middleName: String
    dateOfBirth: Long
    gender: Gender
    gender2: Gender!
    genders1: [Gender]
    genders2: [Gender!]!
    genders3: [Gender]!
    city: CityInput
    cities: [CityInput]
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;
    var serializer = DartSerializer(g);
    var inputSerial = serializer.doSerializeInputDefinition(userInput);
    expect(
      inputSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        "Map<String, dynamic> toJson() {",
        "return {",
        "'id': id,",
        "'name': name,",
        "'middleName': middleName,",
        "'dateOfBirth': dateOfBirth,",
        "'gender': gender?.toJson(),",
        "'gender2': gender2.toJson(),",
        "'genders1': genders1?.map((e0) => e0?.toJson()).toList(),",
        "'genders2': genders2.map((e0) => e0.toJson()).toList(),",
        "'genders3': genders3.map((e0) => e0?.toJson()).toList(),",
        "'city': city?.toJson(),",
        "'cities': cities?.map((e0) => e0?.toJson()).toList()",
        "};",
        "}"
      ]),
    );
  });

  test("input tojson list of lists", () {
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
    var serializer = DartSerializer(g);
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
        inputSerial.split("\n").map((e) => e.trim()),
        containsAllInOrder([
          "Map<String, dynamic> toJson() {",
          'return {',
          "'genders': genders?.map((e0) => e0?.map((e1) => e1?.toJson()).toList()).toList()",
          '};',
        ]));
  });

  test("type tojson", () {
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
    var serializer = DartSerializer(g);
    var userSerial = serializer.doSerializeTypeDefinition(useer);

    expect(
      userSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        "'middleName': middleName,",
        "'dateOfBirth': dateOfBirth,",
        "'gender': gender?.toJson(),",
        "'gender2': gender2.toJson(),",
        "'genders1': genders1?.map((e0) => e0?.toJson()).toList(),",
        "'genders2': genders2.map((e0) => e0.toJson()).toList(),",
        "'genders3': genders3.map((e0) => e0?.toJson()).toList(),",
        "'city': city?.toJson(),",
        "'cities': cities?.map((e0) => e0?.toJson()).toList()",
        "};",
        "}"
      ]),
    );
  });

  test("input fromJson", () {
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
    price: Float
    gender: Gender
    gender2: Gender!
    genders1: [Gender]
    genders2: [Gender!]!
    genders3: [Gender]!
    city: CityInput
    cities: [CityInput]
    doubleCities: [[CityInput]]
  }
''');
    expect(parsed is Success, true);
    var userInput = g.inputs["UserInput"]!;
    var serializer = DartSerializer(g);
    var inputSerial = serializer.doSerializeInputDefinition(userInput);

    expect(
      inputSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        "static UserInput fromJson(Map<String, dynamic> json) {",
        "return UserInput(",
        "id: json['id'] as String?,",
        "name: json['name'] as String,",
        "middleName: json['middleName'] as String?,",
        "dateOfBirth: json['dateOfBirth'] as int?,",
        "price: (json['price'] as num?)?.toDouble(),",
        "gender: json['gender'] == null ? null : Gender.fromJson(json['gender'] as String),",
        "gender2: Gender.fromJson(json['gender2'] as String),",
        "genders1: (json['genders1'] as List<dynamic>?)?.map((e0) => e0 == null ? null : Gender.fromJson(e0 as String)).toList(),",
        "genders2: (json['genders2'] as List<dynamic>).map((e0) => Gender.fromJson(e0 as String)).toList(),",
        "genders3: (json['genders3'] as List<dynamic>).map((e0) => e0 == null ? null : Gender.fromJson(e0 as String)).toList(),",
        "city: json['city'] == null ? null : CityInput.fromJson(json['city'] as Map<String, dynamic>),",
        "cities: (json['cities'] as List<dynamic>?)?.map((e0) => e0 == null ? null : CityInput.fromJson(e0 as Map<String, dynamic>)).toList(),",
        "doubleCities: (json['doubleCities'] as List<dynamic>?)?.map((e0) => (e0 as List<dynamic>?)?.map((e1) => e1 == null ? null : CityInput.fromJson(e1 as Map<String, dynamic>)).toList()).toList()",
        ");",
        "}"
      ]),
    );
  });

  test("type fromJson", () {
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
    price: Float
    gender: Gender
    gender2: Gender!
    genders1: [Gender]
    genders2: [Gender!]!
    genders3: [Gender]!
    city: City
    cities: [City]
    doubleCities: [[City]]
  }
''');
    expect(parsed is Success, true);
    var user = g.types["User"]!;
    var serializer = DartSerializer(g);
    var userSerial = serializer.doSerializeTypeDefinition(user);
    expect(
      userSerial.split("\n").map((e) => e.trim()),
      containsAllInOrder([
        "static User fromJson(Map<String, dynamic> json) {",
        "return User(",
        "id: json['id'] as String?,",
        "name: json['name'] as String,",
        "middleName: json['middleName'] as String?,",
        "dateOfBirth: json['dateOfBirth'] as int?,",
        "price: (json['price'] as num?)?.toDouble(),",
        "gender: json['gender'] == null ? null : Gender.fromJson(json['gender'] as String),",
        "gender2: Gender.fromJson(json['gender2'] as String),",
        "genders1: (json['genders1'] as List<dynamic>?)?.map((e0) => e0 == null ? null : Gender.fromJson(e0 as String)).toList(),",
        "genders2: (json['genders2'] as List<dynamic>).map((e0) => Gender.fromJson(e0 as String)).toList(),",
        "genders3: (json['genders3'] as List<dynamic>).map((e0) => e0 == null ? null : Gender.fromJson(e0 as String)).toList(),",
        "city: json['city'] == null ? null : City.fromJson(json['city'] as Map<String, dynamic>),",
        "cities: (json['cities'] as List<dynamic>?)?.map((e0) => e0 == null ? null : City.fromJson(e0 as Map<String, dynamic>)).toList(),",
        "doubleCities: (json['doubleCities'] as List<dynamic>?)?.map((e0) => (e0 as List<dynamic>?)?.map((e1) => e1 == null ? null : City.fromJson(e1 as Map<String, dynamic>)).toList()).toList()",
        ");",
        "}"
      ]),
    );
  });

  test("interface fromJson", () {
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
    var serializer = DartSerializer(g);
    var userSerial = serializer.serializeInterface(user);

    expect(
      userSerial.split('\n').map((e) => e.trim()),
      containsAllInOrder([
        'abstract class BasicEntity {',
        'String get id;',
        'Map<String, dynamic> toJson();',
        'static BasicEntity fromJson(Map<String, dynamic> json) {',
        "var typename = json['__typename'] as String;",
        'switch(typename) {',
        "case 'User': return User.fromJson(json);",
        "case 'Animal': return Animal.fromJson(json);",
        'default: throw ArgumentError("Invalid type \$typename. \$typename does not implement BasicEntity or not defined");',
        '}',
        '}',
        '}'
      ]),
    );
  });
}
