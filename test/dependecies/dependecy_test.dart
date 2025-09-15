import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("type depends on type", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    car: Car
  }
  type Car {
    make: String
  }
''');
    expect(parsed is Success, true);
    var person = g.getType("Person".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token), contains("Car"));
  });

  test("type depends on interface", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    vehicle: Vehicle
  }
  interface Vehicle {
    make: String
  }
  

''');
    expect(parsed is Success, true);
    var person = g.getType("Person".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token), contains("Vehicle"));
  });

  test("imports list", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    vehicle: [Vehicle]
  }
  interface Vehicle {
    make: String
  }
''');
    expect(parsed is Success, true);
    var person = g.getType("Person".toToken());
    expect(person.getImports(g), contains(importList));
  });

  test("type depends on enum", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    gender: Gender
  }
  enum Gender {male, female}
''');
    expect(parsed is Success, true);
    var person = g.getType("Person".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token), contains("Gender"));
  });

  test("interface depends on type, interface and enum", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  interface Animal {
    name: String
    race: String
    sex: Sex
    owner: Owner
    tail: Tail
  }
  interface Owner {
    name: String
  }
  type Tail {
    id: String
  }
  enum Sex {male, female}
''');
    expect(parsed is Success, true);
    var person = g.getType("Animal".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token), containsAll(["Owner", "Tail", "Sex"]));
  });

  test("type/interface depend on interfaces (inplementations)", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  interface Animal {
    name: String
  
  }
  type Cat implements Animal {
    name: String
    race: String
  }
''');
    expect(parsed is Success, true);
    var cat = g.getType("Cat".toToken());
    expect(cat.getImportDependecies(g).map((t) => t.token), containsAll(["Animal"]));
  });

  test("input depends on input and enum", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  input PersonInput {
    name: String
    address: AddressInput
    sex: Sex
  }
  input AddressInput {
    street: String!
  }
  enum Sex {male, female}
''');
    expect(parsed is Success, true);
    var person = g.inputs["PersonInput"]!;
    expect(person.getImportDependecies(g).map((t) => t.token), containsAll(["AddressInput", "Sex"]));
  });

  test("input depends on directive import", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true

) on OBJECT | INPUT_OBJECT | INTERFACE

  input PersonInput @FieldNameConstants {
    name: String
  }
  
''');
    expect(parsed is Success, true);
    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g), containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("input depends on directive import on field", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true

) on OBJECT | INPUT_OBJECT | INTERFACE

  input PersonInput  {
    name: String @FieldNameConstants
  }
  
''');
    expect(parsed is Success, true);
    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g), containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("type depends on directive import", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true

) on OBJECT | INPUT_OBJECT | INTERFACE

  type Person @FieldNameConstants {
    name: String
  }
  
''');
    expect(parsed is Success, true);
    var person = g.types["Person"]!;
    expect(person.getImports(g), containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("type depends on directive import on field", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true

) on OBJECT | INPUT_OBJECT | INTERFACE

  type Person  {
    name: String @FieldNameConstants
  }
  
''');
    expect(parsed is Success, true);
    var person = g.types["Person"]!;
    expect(person.getImports(g), containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("handle imports on repository", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @gqRepository(
    gqType: String!
    gqIdType: String!
    gqImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    gqClass: String = "MongoRepository"
) on INTERFACE

directive @gqQuery(
    value: String
    count: Boolean
    exists: Boolean
    delete: Boolean
    fields: String
    sort: String
    gqClass: String = "@Query"
    gqImport: String = "org.springframework.data.mongodb.repository.Query"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true
    gqAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Person {
    name: String 
  }

  interface PersonRepo @gqRepository(gqIdType: "String", gqType: "Person") {
    countById(id: String): Int @gqQuery(value: "{'_id': ?0}")
  }
  
''');
    expect(parsed is Success, true);
    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImportDependecies(g).map((e) => e.token), containsAll(["Person"]));

    expect(
        repo.getImports(g),
        containsAll([
          "org.springframework.data.mongodb.repository.MongoRepository",
          "org.springframework.data.mongodb.repository.Query"
        ]));
  });

  test("handle imports on repository 2", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @gqRepository(
    gqType: String!
    gqIdType: String!
    gqImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    gqClass: String = "MongoRepository"
) on INTERFACE


  type Person @gqExternal(gqClass: "ExternalPerson", gqImport: "myorg.ExternalPerson") {
    name: String 
  }

  interface PersonRepo @gqRepository(gqIdType: "String", gqType: "Person") {
    _: Int 
  }
  
''');
    expect(parsed is Success, true);
    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImports(g), containsAll(["myorg.ExternalPerson"]));
  });

  test("handle imports on gqExternal fields", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @gqRepository(
    gqType: String!
    gqIdType: String!
    gqImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    gqClass: String = "MongoRepository"
) on INTERFACE

directive @gqQuery(
    value: String
    count: Boolean
    exists: Boolean
    delete: Boolean
    fields: String
    sort: String
    gqClass: String = "@Query"
    gqImport: String = "org.springframework.data.mongodb.repository.Query"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true
    gqAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Person {
    name: String 
  }

  input Pageable @gqExternal(gqClass: "Pageaable", gqImport: "org.myorg.Pagagble") {
    _: Int
  }

  interface PersonRepo @gqRepository(gqIdType: "String", gqType: "Person") {
    findById(id: String): Person @gqQuery(value: "{'_id': ?0}")
    findByName(id: String, pageable: Pageable): [Person!]!
  }
  
''');
    expect(parsed is Success, true);
    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImportDependecies(g).map((e) => e.token), containsAll(["Person"]));
    expect(repo.getImportDependecies(g).map((e) => e.token), isNot(contains("Pageable")));
    expect(repo.getImports(g), contains("org.myorg.Pagagble"));
  });

  test("controller must depend on service", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  type Person {
    name: String 
  }
  type Query {
    getPerson: Person 
  }
''');
    expect(parsed is Success, true);
    var ctrl = g.controllers["PersonServiceController"]!;
    expect(ctrl.getImportDependecies(g).map((e) => e.token), contains("PersonService"));
  });

  test("Repository should import org.springframework.stereotype.Repository after serialization", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @gqRepository(
    gqType: String!
    gqIdType: String!
    gqImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    gqClass: String = "MongoRepository"
) on INTERFACE

  type Person {
    name: String 
  }

  interface PersonRepo @gqRepository(gqIdType: "String", gqType: "Person") {
    findById(id: String): Person
  }
  
''');
    expect(parsed is Success, true);
    var repo = g.repositories["PersonRepo"]!;
    var serializer = SpringServerSerializer(g);
    serializer.serializeRepository(repo, "org.myorg");
    expect(repo.getImports(g), contains("org.springframework.stereotype.Repository"));
  });

  test("Should not import skipped objects", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  
  type Person {
    name: String 
    car: Car
  }

  type Car @gqSkipOnServer {
    name: String
  }

  
''');
    expect(parsed is Success, true);
    var person = g.types["Person"]!;
    expect(person.getImportDependecies(g).map((e) => e.token), isNot(contains("Car")));
  });

  test("gqImport import", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
directive @gqExternal(gqClass: String!, gqImport: String!) on  OBJECT|INPUT_OBJECT

  input Pageable @gqExternal(gqClass: "Pageable", gqImport: "org.springframework.data.domain.Pageable") {
    _: Int #dummy
  }

  input PersonInput {
    name: String
    pageable: Pageable
  }

''');
    expect(parsed is Success, true);
    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g), contains("org.springframework.data.domain.Pageable"));
  });

  test("service should import mapping dependecies", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''

 type Car {
  name: String
  owner: Person @gqSkipOnServer
 }
 type Person {
  name: String
 }

 type Query {
  getCar: Car
 }

''');
    expect(parsed is Success, true);
    var carService = g.services["CarService"]!;
    expect(carService.getImportDependecies(g).map((e) => e.token), contains("Person"));
  });

  test("service should import arguments event when type is skipped", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''

 type Car @gqSkipOnServer {
  name: String
 }

 input PagingInfo {
    page: Int!
    size: Int!
}

 type Query {
  getCars(page: PagingInfo!): [Car!]! @gqServiceName(name: "MyService")
 }

''');
    expect(parsed is Success, true);
    var carService = g.services["MyService"]!;
    expect(carService.getImportDependecies(g).map((e) => e.token), contains("PagingInfo"));
  });

  test("interface must import implementations when fromJson is present", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
    var parsed = g.parse('''

interface Animal {
  name: String
}

type Cat implements Animal {
  name: String
}


 type Query {
  getAnimal: Animal
 }

''');
    expect(parsed is Success, true);
    var animal = g.projectedTypes['Animal']!;
    expect(animal.getImportDependecies(g).map((e) => e.token), containsAll(["Cat"]));
  });

  test("Client should import responses", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${clientObjects}

type Cat  {
  name: String
}

 type Query {
  getAnimal: Cat
  getCat: Cat
  getCount: Int!
 }

''');
    expect(parsed is Success, true);
    expect(clientGen.getImportDependecies(g).map((e) => e.token),
        containsAll(["GetAnimalResponse", "GetCatResponse", "GetCountResponse"]));
  });

  test("Client should import inputs", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${clientObjects}

type Cat  {
  name: String
}
 input CatInput {
  name: String!
 }


 type Mutation {
  createCat(input: CatInput!): Cat!
 }

''');
    expect(parsed is Success, true);
    print(clientGen.generateClient("mypackage"));
    expect(clientGen.getImportDependecies(g).map((e) => e.token), containsAll(["CatInput"]));
  });

  test("Client should import enums", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${clientObjects}
enum Gender {male, female}
type Cat  {
  name: String
}
type Query {
  getCatsByGender(gender: Gender!): [Cat!]!
}

''');
    expect(parsed is Success, true);
    expect(clientGen.getImportDependecies(g).map((e) => e.token), containsAll(["Gender"]));
  });
}
