import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/serializers/spring_server_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:petitparser/petitparser.dart';

void main() async {
  test("type depends on type", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true

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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true

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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true

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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true

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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
    glOnServer: Boolean = true
) on INTERFACE

directive @gqQuery(
    value: String
    count: Boolean
    exists: Boolean
    delete: Boolean
    fields: String
    sort: String
    glClass: String = "@Query"
    glImport: String = "org.springframework.data.mongodb.repository.Query"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
    glAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Person {
    name: String 
  }

  interface PersonRepo @glRepository(glIdType: "String", glType: "Person") {
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
) on INTERFACE


  type Person @glExternal(glClass: "ExternalPerson", glImport: "myorg.ExternalPerson") {
    name: String 
  }

  interface PersonRepo @glRepository(glIdType: "String", glType: "Person") {
    _: Int 
  }
  
''');
    expect(parsed is Success, true);
    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImports(g), containsAll(["myorg.ExternalPerson"]));
  });

  test("handle imports on glExternal fields", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
) on INTERFACE

directive @gqQuery(
    value: String
    count: Boolean
    exists: Boolean
    delete: Boolean
    fields: String
    sort: String
    glClass: String = "@Query"
    glImport: String = "org.springframework.data.mongodb.repository.Query"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
    glAnnotation: Boolean = true
) on FIELD_DEFINITION

  type Person {
    name: String 
  }

  input Pageable @glExternal(glClass: "Pageaable", glImport: "org.myorg.Pagagble") {
    _: Int
  }

  interface PersonRepo @glRepository(glIdType: "String", glType: "Person") {
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  directive @glRepository(
    glType: String!
    glIdType: String!
    glImport: String = "org.springframework.data.mongodb.repository.MongoRepository"
    glClass: String = "MongoRepository"
) on INTERFACE

  type Person {
    name: String 
  }

  interface PersonRepo @glRepository(glIdType: "String", glType: "Person") {
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''
  
  type Person {
    name: String 
    car: Car
  }

  type Car @glSkipOnServer {
    name: String
  }

  
''');
    expect(parsed is Success, true);
    var person = g.types["Person"]!;
    expect(person.getImportDependecies(g).map((e) => e.token), isNot(contains("Car")));
  });

  test("glImport import", () {
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
directive @glExternal(glClass: String!, glImport: String!) on  OBJECT|INPUT_OBJECT

  input Pageable @glExternal(glClass: "Pageable", glImport: "org.springframework.data.domain.Pageable") {
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''

 type Car {
  name: String
  owner: Person @glSkipOnServer
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
    final GLGrammar g = GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var parsed = g.parse('''

 type Car @glSkipOnServer {
  name: String
 }

 input PagingInfo {
    page: Int!
    size: Int!
}

 type Query {
  getCars(page: PagingInfo!): [Car!]! @glServiceName(name: "MyService")
 }

''');
    expect(parsed is Success, true);
    var carService = g.services["MyService"]!;
    expect(carService.getImportDependecies(g).map((e) => e.token), contains("PagingInfo"));
  });

  test("interface must import implementations when fromJson is present", () {
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
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
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
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
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
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
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
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
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);
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
          "GraphLinkSubscriptionPayload",
          "GraphLinkSubscriptionErrorMessageBase",
          "GraphLinkSubscriptionErrorMessage",
          "GraphLinkSubscriptionMessage"
        ]));
  });

  test("import should be skipped on skip mode", () {
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server, autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}
enum Gender {male, female}
type Person  {
  name: String
  gender: Gender @glSkipOnServer
}
''');
    var person = g.types['Person']!;
    expect(parsed is Success, true);
    expect(person.getImportDependecies(g).map((e) => e.token), isNot(contains("Gender")));
  });

  test("import should be skipped on skip mode on directives", () {
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @Id(
    glClass: String = "Id",
    glImport: String = "org.springframework.data.annotation.Id",
    glOnClient: Boolean = false,
    glOnServer: Boolean = true,
    glAnnotation: Boolean = true
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
    final GLGrammar g =
        GLGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.client, autoGenerateQueries: true);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true

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
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  directive @FieldNameConstants(
    glAnnotation: Boolean = true
    glClass: String = "@FieldNameConstants"
    glImport: String = "lombok.experimental.FieldNameConstants"
    glOnClient: Boolean = false
    glOnServer: Boolean = true
) on OBJECT | INPUT_OBJECT | INTERFACE

type Person @FieldNameConstants  {
  id: String 
}

interface PersonRepository @glRepository(glIdType: "String", glType: "Person") {
  _: Int
}

type Query {
  findPerson: Person @glServiceName(name: "MainService")
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
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  type PersonCar @glSkipOnServer(mapTo: "Person") {
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
    findPerson: [PersonCar!]! @glServiceName(name: "MainService")  ### it should be a batch with a skipped Type response
  }
''');
    expect(parsed is Success, true);
    var mappingService = g.services[g.serviceMappingName("PersonCar")]!;
    expect(mappingService.getImportDependecies(g).map((e) => e.token), containsAll(["Person", "Car"]));
  });

  test("mapping service should import batch dependecies recursive", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}

  type PersonCar @glSkipOnServer(mapTo: "Person") {
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

  type Vehicle @glSkipOnServer(mapTo: "Car") {
    car: Car!
    owner: Owner
  }

  type Query {
    findPerson: [PersonCar!]! @glServiceName(name: "MainService") 
  }
''');
    expect(parsed is Success, true);
    var personCarMappingService = g.services[g.serviceMappingName("PersonCar")]!;
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token), isNot(contains("Vehicle")));
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token), containsAll(["Person", "Car"]));
  });

  test("mapping should import mapped to dependecies", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  type Person {
    firstName: String
    lastName: String
  }

  type PersonDTO ${glSkipOnServer}(mapTo: "Person") {
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
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  type ConversationUnread @glSkipOnServer(mapTo: "ConversationView") {
    view: ConversationView!
    unread: Int!
  }

  type ConversationView  {
    conversationId: ID! 
    customName: String
  }

  type Query {
    getConversationById(id: ID!): ConversationUnread! @glServiceName(name: "MessageService")
  }
  
''');
    expect(parsed is Success, true);

    var service = g.services["MessageService"]!;
    var ctrl = g.controllers["MessageServiceController"]!;
    expect(service.getImportDependecies(g).map((e) => e.token), containsAll(['ConversationView']));
    expect(ctrl.getImportDependecies(g).map((e) => e.token), containsAll(['ConversationView']));
  });

  test("service should import DataFetchingEnvironment when serialized", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @glServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);

    var service = g.services["PersonService"]!;

    serializer.serializeService(service, "com.myorg");
    expect(service.getImports(g), contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test("controller should import DataFetchingEnvironment when serialized", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @glServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    var controller = g.controllers["PersonServiceController"]!;
    serializer.serializeController(controller, "com.myorg");
    expect(controller.getImports(g), contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test("Java interface should import java.util.map when json methods are serialized", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

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
    getPerson: Person! @glServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var basicEntity = g.interfaces["BasicEntity"]!;
    var basicEntitySerial = serializer.serializeTypeDefinition(basicEntity, 'com.myorg');
    expect(basicEntitySerial, stringContainsInOrder(['import java.util.Map;']));
  });

  test("controller must import @Argument", () {
    final GLGrammar g = GLGrammar(mode: CodeGenerationMode.server);

    var parsed = g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPersonById(id: String!): Person! @glServiceName(name: "PersonService")
  }
  
''');
    expect(parsed is Success, true);
    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    var controller = g.controllers["PersonServiceController"]!;
    var serial = serializer.serializeController(controller, "com.myorg");
    print(serial);
    expect(controller.getImports(g), contains(SpringImports.gqlArgument));
  });
}
