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
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() async {
  test("type depends on type", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  type Person {
    id: String
    car: Car
  }
  type Car {
    make: String
  }
''');

    var person = g.getType("Person".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token), contains("Car"));
  });

  test("type depends on interface", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  type Person {
    id: String
    vehicle: Vehicle
  }
  interface Vehicle {
    make: String
  }
  

''');

    var person = g.getType("Person".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token),
        contains("Vehicle"));
  });

  test("imports list", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  type Person {
    id: String
    vehicle: [Vehicle]
  }
  interface Vehicle {
    make: String
  }
''');

    var person = g.getType("Person".toToken());
    expect(person.getImports(g), contains(importList));
  });

  test("type depends on enum", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  type Person {
    id: String
    gender: Gender
  }
  enum Gender {male, female}
''');

    var person = g.getType("Person".toToken());
    expect(
        person.getImportDependecies(g).map((t) => t.token), contains("Gender"));
  });

  test("interface depends on type, interface and enum", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
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

    var person = g.getType("Animal".toToken());
    expect(person.getImportDependecies(g).map((t) => t.token),
        containsAll(["Owner", "Tail", "Sex"]));
  });

  test("type/interface depend on interfaces (inplementations)", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  interface Animal {
    name: String
  
  }
  type Cat implements Animal {
    name: String
    race: String
  }
''');

    var cat = g.getType("Cat".toToken());
    expect(cat.getImportDependecies(g).map((t) => t.token),
        containsAll(["Animal"]));
  });

  test("input depends on input and enum", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
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

    var person = g.inputs["PersonInput"]!;
    expect(person.getImportDependecies(g).map((t) => t.token),
        containsAll(["AddressInput", "Sex"]));
  });

  test("input depends on directive import", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g),
        containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("input depends on directive import on field", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g),
        containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("type depends on directive import", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var person = g.types["Person"]!;
    expect(person.getImports(g),
        containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("type depends on directive import on field", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var person = g.types["Person"]!;
    expect(person.getImports(g),
        containsAll(["lombok.experimental.FieldNameConstants"]));
  });

  test("handle imports on repository", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImportDependecies(g).map((e) => e.token),
        containsAll(["Person"]));

    expect(
        repo.getImports(g),
        containsAll([
          "org.springframework.data.mongodb.repository.MongoRepository",
          "org.springframework.data.mongodb.repository.Query"
        ]));
  });

  test("handle imports on repository 2", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImports(g), containsAll(["myorg.ExternalPerson"]));
  });

  test("handle imports on glExternal fields", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var repo = g.repositories["PersonRepo"]!;

    expect(repo.getImportDependecies(g).map((e) => e.token),
        containsAll(["Person"]));
    expect(repo.getImportDependecies(g).map((e) => e.token),
        isNot(contains("Pageable")));
    expect(repo.getImports(g), contains("org.myorg.Pagagble"));
  });

  test("controller must depend on service", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
  type Person {
    name: String 
  }
  type Query {
    getPerson: Person 
  }
''');

    var ctrl = g.controllers["PersonServiceController"]!;
    expect(ctrl.getImportDependecies(g).map((e) => e.token),
        contains("PersonService"));
  });

  test(
      "Repository should import org.springframework.stereotype.Repository after serialization",
      () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
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

    var repo = g.repositories["PersonRepo"]!;
    var serializer = SpringServerSerializer(g);
    serializer.serializeRepository(repo, "org.myorg");
    expect(repo.getImports(g),
        contains("org.springframework.stereotype.Repository"));
  });

  test("Should not import skipped objects", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
  
  type Person {
    name: String 
    car: Car
  }

  type Car @glSkipOnServer {
    name: String
  }

  
''');

    var person = g.types["Person"]!;
    expect(person.getImportDependecies(g).map((e) => e.token),
        isNot(contains("Car")));
  });

  test("glImport import", () {
    final GLParser g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
directive @glExternal(glClass: String!, glImport: String!) on  OBJECT|INPUT_OBJECT

  input Pageable @glExternal(glClass: "Pageable", glImport: "org.springframework.data.domain.Pageable") {
    _: Int #dummy
  }

  input PersonInput {
    name: String
    pageable: Pageable
  }

''');

    var person = g.inputs["PersonInput"]!;
    expect(person.getImports(g),
        contains("org.springframework.data.domain.Pageable"));
  });

  test("service should import mapping dependecies", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''

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

    var carMappingService = g.services[g.serviceMappingName("Car")]!;
    expect(carMappingService.getImportDependecies(g).map((e) => e.token),
        contains("Person"));
  });

  test("service should import arguments event when type is skipped", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''

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

    var carService = g.services["MyService"]!;
    expect(carService.getImportDependecies(g).map((e) => e.token),
        contains("PagingInfo"));
  });

  test("interface must import implementations when fromJson is present", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    g.parse('''

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

    var animal = g.projectedInterfaces['Animal']!;
    var serializer = DartSerializer(g, generateJsonMethods: true);
    var animalSerial = serializer.serializeTypeDefinition(animal, "myorg");
    expect(animalSerial,
        stringContainsInOrder(["import 'myorg/types/cat.dart';"]));
  });

  test("Client should import responses", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);
    final text = '''
  ${getClientObjects("dart")}

type Cat  {
  name: String
}

 type Query {
  getAnimal: Cat
  getCat: Cat
  getCount: Int!
 }

''';
    print(text);
    g.parse(text);

    expect(
        clientGen.getImportDependecies(g).map((e) => e.token),
        containsAll(
            ["GetAnimalResponse", "GetCatResponse", "GetCountResponse"]));
  });

  test("Client should import inputs", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    g.parse('''
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

    expect(clientGen.getImportDependecies(g).map((e) => e.token),
        containsAll(["CatInput"]));
  });

  test("Client should import enums", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    g.parse('''
  ${getClientObjects()}
enum Gender {male, female}
type Cat  {
  name: String
}
type Query {
  getCatsByGender(gender: Gender!): [Cat!]!
}

''');

    expect(clientGen.getImportDependecies(g).map((e) => e.token),
        containsAll(["Gender"]));
  });

  test("Client should import subscription classes/eumms", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);
    var serilazer = DartSerializer(g);
    var clientGen = DartClientSerializer(g, serilazer);

    g.parse('''
  ${getClientObjects()}
type Cat  {
  name: String
}
type Subscrtipion {
  cat: Cat
}

''');

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
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.server,
        autoGenerateQueries: true);

    g.parse('''
  ${getClientObjects()}
enum Gender {male, female}
type Person  {
  name: String
  gender: Gender @glSkipOnServer
}
''');
    var person = g.types['Person']!;

    expect(person.getImportDependecies(g).map((e) => e.token),
        isNot(contains("Gender")));
  });

  test("import should be skipped on skip mode on directives", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);

    g.parse('''
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

    expect(person.getImports(g),
        isNot(contains("org.springframework.data.annotation.Id")));
  });

  test("import should be skipped on skip mode on directives", () {
    final GLParser g = GLParser(
        generateAllFieldsFragments: true,
        mode: CodeGenerationMode.client,
        autoGenerateQueries: true);

    g.parse('''
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

    expect(person.getImports(g),
        isNot(contains("lombok.experimental.FieldNameConstants")));
  });

  test("services and repos should not import related class imports", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var person = g.types['Person']!;
    // Person should import lombok.experimental.FieldNameConstants
    expect(person.getImports(g),
        contains('lombok.experimental.FieldNameConstants'));

    var service = g.services['MainService']!;
    var repo = g.repositories['PersonRepository']!;
    // service should NOT import lombok.experimental.FieldNameConstants
    expect(service.getImports(g),
        isNot(contains("lombok.experimental.FieldNameConstants")));
    // repo should NOT import lombok.experimental.FieldNameConstants
    expect(repo.getImports(g),
        isNot(contains("lombok.experimental.FieldNameConstants")));
  });

  test("mapping service should import batch dependecies", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var mappingService = g.services[g.serviceMappingName("PersonCar")]!;
    expect(mappingService.getImportDependecies(g).map((e) => e.token),
        containsAll(["Person", "Car"]));
  });

  test("mapping service should import batch dependecies recursive", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var personCarMappingService =
        g.services[g.serviceMappingName("PersonCar")]!;
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token),
        isNot(contains("Vehicle")));
    expect(personCarMappingService.getImportDependecies(g).map((e) => e.token),
        containsAll(["Person", "Car"]));
  });

  test("mapping should import mapped to dependecies", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var mapping = g.services[g.serviceMappingName('PersonDTO')]!;
    expect(mapping.getImportDependecies(g).map((e) => e.token),
        containsAll(['Person']));
  });

  test("services and controllers should import mapped to dependecies", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var service = g.services["MessageService"]!;
    var ctrl = g.controllers["MessageServiceController"]!;
    expect(service.getImportDependecies(g).map((e) => e.token),
        containsAll(['ConversationView']));
    expect(ctrl.getImportDependecies(g).map((e) => e.token),
        containsAll(['ConversationView']));
  });

  test("service should import DataFetchingEnvironment when serialized", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @glServiceName(name: "PersonService")
  }
  
''');

    var serializer = SpringServerSerializer(g, injectDataFetching: true);

    var service = g.services["PersonService"]!;

    serializer.serializeService(service, "com.myorg");
    expect(service.getImports(g),
        contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test("controller should import DataFetchingEnvironment when serialized", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPerson: Person! @glServiceName(name: "PersonService")
  }
  
''');

    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    var controller = g.controllers["PersonServiceController"]!;
    serializer.serializeController(controller, "com.myorg");
    expect(controller.getImports(g),
        contains(SpringImports.gqlDataFetchingEnvironment));
  });

  test(
      "Java interface should import java.util.map when json methods are serialized",
      () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
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

    var serializer = JavaSerializer(g, generateJsonMethods: true);
    var basicEntity = g.interfaces["BasicEntity"]!;
    var basicEntitySerial =
        serializer.serializeTypeDefinition(basicEntity, 'com.myorg');
    expect(basicEntitySerial, stringContainsInOrder(['import java.util.Map;']));
  });

  test("controller must import @Argument", () {
    final GLParser g = GLParser(mode: CodeGenerationMode.server);

    g.parse('''
  ${getClientObjects()}
  

  type Person  {
    name: String!
    age: Int!
  }

  type Query {
    getPersonById(id: String!): Person! @glServiceName(name: "PersonService")
  }
  
''');

    var serializer = SpringServerSerializer(g, injectDataFetching: true);
    var controller = g.controllers["PersonServiceController"]!;
    var serial = serializer.serializeController(controller, "com.myorg");
    print(serial);
    expect(controller.getImports(g), contains(SpringImports.gqlArgument));
  });
}
