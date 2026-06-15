import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
interface Animal {
    id: ID!
    name: String!
}

type Dog implements Animal {
    id: ID!
    name: String!
    breed: String!
}

type Cat implements Animal {
    id: ID!
    name: String!
    lives: Int!
}
''';

void main() {
  test("TS: GL<Interface>Projection for a user-declared interface", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = TypeScriptSerializer(g, importPrefix: "");

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);

    // Real GraphQL `interface` -> TS union alias of its implementors (unchanged).
    expect(animalOut, contains('export type Animal = Dog | Cat;'));

    // GL<Interface>Projection -> its own all-nullable interface, not a union alias.
    expect(animalProjectionOut, contains('export interface GLAnimalProjection {'));
    expect(animalProjectionOut, contains('readonly id: string | null;'));
    expect(animalProjectionOut, contains('readonly name: string | null;'));
    expect(animalProjectionOut, isNot(contains('export type GLAnimalProjection')));

    // Plain object type -> unchanged.
    expect(dogOut, contains('export interface Dog {'));
    expect(dogOut, contains('readonly id: string;'));
    expect(dogOut, contains('readonly breed: string;'));

    // GL<Type>Projection for an object type -> its own all-nullable interface,
    // not a `type GLDogProjection = Dog` alias.
    expect(dogProjectionOut, contains('export interface GLDogProjection {'));
    expect(dogProjectionOut, contains('readonly id: string | null;'));
    expect(dogProjectionOut, contains('readonly breed: string | null;'));
    expect(dogProjectionOut, isNot(contains('export type GLDogProjection')));
  });

  test("Java: GL<Interface>Projection / GL<Type>Projection for the same schema", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSerializer(g, importPrefix: "");

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);

    expect(animalOut, contains('interface Animal'));
    expect(animalOut, contains('String getId();'));

    expect(animalProjectionOut, contains('interface GLAnimalProjection'));
    expect(animalProjectionOut, contains('String getId();'));
    expect(animalProjectionOut, contains('String getName();'));

    expect(dogOut, contains('implements Animal, GLDogProjection'));
    expect(dogOut, contains('private String id;'));

    expect(dogProjectionOut, contains('interface GLDogProjection'));
    expect(dogProjectionOut, contains('String getId();'));
    expect(dogProjectionOut, contains('String getBreed();'));
  });

  test("Kotlin: GL<Interface>Projection / GL<Type>Projection for the same schema", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = KotlinSerializer(g, importPrefix: "com.example");

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);

    expect(animalOut, contains('interface Animal'));
    expect(animalOut, contains('val id: String'));

    expect(animalProjectionOut, contains('interface GLAnimalProjection'));
    expect(animalProjectionOut, contains('val id: String?'));
    expect(animalProjectionOut, contains('val name: String?'));

    expect(dogOut, contains('Animal'));
    expect(dogOut, contains('GLDogProjection'));

    expect(dogProjectionOut, contains('interface GLDogProjection'));
    expect(dogProjectionOut, contains('val id: String?'));
    expect(dogProjectionOut, contains('val breed: String?'));
  });

  test("Java (generateJsonMethods: true): GL<Interface>Projection / GL<Type>Projection", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = JavaSerializer(g, importPrefix: "", generateJsonMethods: true);

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);
  });

  test("Kotlin (generateJsonMethods: true): GL<Interface>Projection / GL<Type>Projection", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = KotlinSerializer(g, importPrefix: "com.example", generateJsonMethods: true);

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);
  });

  test("Dart: GL<Interface>Projection / GL<Type>Projection for the same schema", () {
    final g = GLParser(identityFields: ["id"], mode: CodeGenerationMode.server);
    g.parse(_schema);

    final serializer = DartSerializer(g, importPrefix: "");

    final animal = g.interfaces["Animal"]!;
    final animalProjection = g.interfaces["GLAnimalProjection"]!;
    final dog = g.types["Dog"]!;
    final dogProjection = g.interfaces["GLDogProjection"]!;

    final animalOut = serializer.serializeTypeDefinition(animal);
    final animalProjectionOut = serializer.serializeTypeDefinition(animalProjection);
    final dogOut = serializer.serializeTypeDefinition(dog);
    final dogProjectionOut = serializer.serializeTypeDefinition(dogProjection);

    print(animalOut);
    print(animalProjectionOut);
    print(dogOut);
    print(dogProjectionOut);

    expect(animalOut, contains('abstract class Animal'));
    expect(animalOut, contains('extends GLAnimalProjection'));
    expect(animalOut, contains('String get id;'));

    expect(animalProjectionOut, contains('abstract class GLAnimalProjection'));
    expect(animalProjectionOut, contains('String? get id;'));
    expect(animalProjectionOut, contains('String? get name;'));

    expect(dogOut, contains('class Dog'));
    expect(dogOut, contains('Animal'));
    expect(dogOut, contains('GLDogProjection'));

    expect(dogProjectionOut, contains('abstract class GLDogProjection'));
    expect(dogProjectionOut, contains('String? get id;'));
    expect(dogProjectionOut, contains('String? get breed;'));
  });
}
