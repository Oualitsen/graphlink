import 'package:retrofit_graphql/src/constants.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/model/gq_token_with_fields.dart';
import 'package:retrofit_graphql/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/java_serializer.dart';
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
    expect(
        person.getImportDependecies(g).map((t) => t.token), containsAll(["Owner", "Tail", "Sex"]));
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
    expect(
        person.getImportDependecies(g).map((t) => t.token), containsAll(["AddressInput", "Sex"]));
  });

  test("input depends on directive import", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @gqRepository(
    gqType: String!
    gqIdType: String!
    gqImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    gqClass: String = "MongoRepository"
    gqOnServer: Boolean = true
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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

  test("Repository should import org.springframework.stereotype.Repository after serialization",
      () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    var carMappingService = g.services[g.serviceMappingName("Car")]!;
    expect(carMappingService.getImportDependecies(g).map((e) => e.token), contains("Person"));
  });

  test("service should import arguments event when type is skipped", () {
    final GQGrammar g =
        GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
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
    var animal = g.projectedInterfaces['Animal']!;
    var serializer = DartSerializer(g, generateJsonMethods: true);
    var animalSerial = serializer.serializeTypeDefinition(animal, "myorg");
    expect(animalSerial, stringContainsInOrder(["import 'myorg/types/cat.dart';"]));
  });

  test("Client should import responses", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${getClientObjects("dart")}

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
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${getClientObjects()}

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
    expect(clientGen.getImportDependecies(g).map((e) => e.token), containsAll(["CatInput"]));
  });

  test("Client should import enums", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${getClientObjects()}
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

  test("Client should import subscription classes/eumms", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    var parsed = g.parse('''
  ${getClientObjects()}
type Cat  {
  name: String
}
type Subscrtipion {
  cat: Cat
}

''');
    expect(parsed is Success, true);
    expect(
        clientGen.getImportDependecies(g).map((e) => e.token),
        containsAll([
          "GQSubscriptionPayload",
          "GQAckStatus",
          "GQSubscriptionErrorMessageBase",
          "GQSubscriptionErrorMessage",
          "GQSubscriptionMessage"
        ]));
  });

  test("import should be skipped on skip mode", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.server,
        autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}
enum Gender {male, female}
type Person  {
  name: String
  gender: Gender @gqSkipOnServer
}
''');
    var person = g.types['Person']!;
    expect(parsed is Success, true);
    expect(person.getImportDependecies(g).map((e) => e.token), isNot(contains("Gender")));
  });

  test("import should be skipped on skip mode on directives", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @Id(
    gqClass: String = "Id",
    gqImport: String = "org.springframework.data.annotation.Id",
    gqOnClient: Boolean = false,
    gqOnServer: Boolean = true,
    gqAnnotation: Boolean = true
)
 on FIELD_DEFINITION | FIELD

enum Gender {male, female}
type Person  {
  id: String @Id
}
''');
    var person = g.types['Person']!;
    expect(parsed is Success, true);
    expect(person.getImports(g), isNot(contains("org.springframework.data.annotation.Id")));
  });

  test("import should be skipped on skip mode on directives", () {
    final GQGrammar g = GQGrammar(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true

) on OBJECT | INPUT_OBJECT | INTERFACE

type Person @FieldNameConstants  {
  id: String 
}
''');
    var person = g.types['Person']!;
    expect(parsed is Success, true);
    expect(person.getImports(g), isNot(contains("lombok.experimental.FieldNameConstants")));
  });

  test("services and repos should not import related class imports", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @FieldNameConstants(
    gqAnnotation: Boolean = true
    gqClass: String = "@FieldNameConstants"
    gqImport: String = "lombok.experimental.FieldNameConstants"
    gqOnClient: Boolean = false
    gqOnServer: Boolean = true
) on OBJECT | INPUT_OBJECT | INTERFACE

type Person @FieldNameConstants  {
  id: String 
}

interface PersonRepository @gqRepository(gqIdType: "String", gqType: "Person") {
  _: Int
}

type Query {
  findPerson: Person @gqServiceName(name: "MainService")
}
''');
    expect(parsed is Success, true);

    var person = g.types['Person']!;
    // Person should import lombok.experimental.FieldNameConstants
    expect(person.getImports(g), contains('lombok.experimental.FieldNameConstants'));

    var service = g.services['MainService']!;
    var repo = g.repositories['PersonRepository']!;
    // service should NOT import lombok.experimental.FieldNameConstants
    expect(service.getImports(g), isNot(contains("lombok.experimental.FieldNameConstants")));
    // repo should NOT import lombok.experimental.FieldNameConstants
    expect(repo.getImports(g), isNot(contains("lombok.experimental.FieldNameConstants")));
  });

  test("mapping service should import batch dependecies", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  type PersonCar @gqSkipOnServer(mapTo: "Person") {
    person: Person!
    car: Car
  }
  type Person  {
    name: String
  }
  type Car {
    make: String
  }
  type Query {
    findPerson: [PersonCar!]! @gqServiceName(name: "MainService")  ### it should be a batch with a skipped Type response
  }
''');
    expect(parsed is Success, true);
    var mappingService = g.services[g.serviceMappingName("PersonCar")]!;
    expect(
        mappingService.getImportDependecies(g).map((e) => e.token), containsAll(["Person", "Car"]));
  });

  test("mapping service should import batch dependecies recursive", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  type PersonCar @gqSkipOnServer(mapTo: "Person") {
    person: Person!
    car: Car
    vehicle: Vehicle
  }
  type Person  {
    name: String
  }
  type Car {
    make: String
  }
  type Owner {
    name: String
  }

  type Vehicle @gqSkipOnServer(mapTo: "Car") {
    car: Car!
    owner: Owner
  }

  type Query {
    findPerson: [PersonCar!]! @gqServiceName(name: "MainService") 
  }
''');
    expect(parsed is Success, true);
    var personCarMappingService = g.services[g.serviceMappingName("PersonCar")]!;
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token),
        isNot(contains("Vehicle")));
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token),
        containsAll(["Person", "Car"]));
  });

  test("mapping should import mapped to dependecies", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  type Person {
    firstName: String
    lastName: String
  }

  type PersonDTO ${gqSkipOnServer}(mapTo: "Person") {
    age: Int!
  }

  type Query {
    getDTO: [PersonDTO!]!
  }
  
''');
    expect(parsed is Success, true);

    var mapping = g.services[g.serviceMappingName('PersonDTO')]!;
    expect(mapping.getImportDependecies(g).map((e) => e.token), containsAll(['Person']));
  });

  test("services and controllers should import mapped to dependecies", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  type ConversationUnread @gqSkipOnServer(mapTo: "ConversationView") {
    view: ConversationView!
    unread: Int!
  }

  type ConversationView  {
    conversationId: ID! 
    customName: String
  }

  type Query {
    getConversationById(id: ID!): ConversationUnread! @gqServiceName(name: "MessageService")
  }
  
''');
    expect(parsed is Success, true);

    var service = g.services["MessageService"]!;
    var ctrl = g.controllers["MessageServiceController"]!;
    expect(service.getImportDependecies(g).map((e) => e.token), containsAll(['ConversationView']));
    expect(ctrl.getImportDependecies(g).map((e) => e.token), containsAll(['ConversationView']));
  });

  test("service should import DataFetchingEnvironment when serialized", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @gqServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);

    var service = g.services["PersonService"]!;

    serializer.serializeService(service, "com.myorg");
    expect(service.getImports(g), contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test("controller should import DataFetchingEnvironment when serialized", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @gqServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    var controller = g.controllers["PersonServiceController"]!;
    serializer.serializeController(controller, "com.myorg");
    expect(controller.getImports(g), contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test("Java interface should import java.util.map when json methods are serialized", () {
    final GQGrammar g = GQGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  
  interface BasicEntity {
    id: ID!
  }

  type Person implements BasicEntity  {
    id: ID!
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @gqServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var basicEntity = g.interfaces["BasicEntity"]!;
    var basicEntitySerial = serializer.serializeTypeDefinition(basicEntity, 'com.myorg');
    expect(basicEntitySerial, stringContainsInOrder(['import java.util.Map;']));
  });
}
