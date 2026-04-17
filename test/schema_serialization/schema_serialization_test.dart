import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final GLParser g = GLParser();

void main() {
  test("serialize directive definition with different argument types@@", () {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''

    type User {
      id: String
      name: String
      pet: Pet @glSkipOnServer
      petId: String @glSkipOnClient
    }
    type Pet {
      name: String
    }
  ''');

    final serializer = GLGraphqSerializer(g);

    var schema = serializer.generateSchema();
    // user should declare a pet: Pet but should not declare a petId
    expect(schema, contains("pet: Pet"));
    expect(schema, isNot(contains("petId: String")));
  });

  test("serialize directive definition with different argument types", () {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    directive @myDirective(value: User!) on OBJECT
    directive @myDirective2(value: [String!]!) on OBJECT
    directive @myDirective3(value: [User!]!) on OBJECT

    type User {
      id: String @myDirective(value: {name: "ramdane", age: 12, id: "test"})
      name: String @myDirective2(value: ["azul", "fellawen"])
      lastName: String @myDirective3(value: [{name: "ramdane", age: 12, id: "test"}])
      age: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var myDirective = serializer
        .serializeDirectiveDefinition(g.directiveDefinitions["@myDirective"]!);
    expect(myDirective, "directive @myDirective(value: User!) on OBJECT");

    var myDirective2 = serializer
        .serializeDirectiveDefinition(g.directiveDefinitions["@myDirective2"]!);
    expect(
        myDirective2, "directive @myDirective2(value: [String!]!) on OBJECT");

    var myDirective3 = serializer
        .serializeDirectiveDefinition(g.directiveDefinitions["@myDirective3"]!);
    expect(myDirective3, "directive @myDirective3(value: [User!]!) on OBJECT");
  });

  test("serialize directive values with different argument types", () {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    directive @myDirective(value: User!) on OBJECT
    directive @myDirective2(value: [String!]!) on OBJECT
    directive @myDirective3(value: [User!]!) on OBJECT

    type User {
      id: String @myDirective(value: {name: "ramdane", age: 12, id: "test"})
      name: String @myDirective2(value: ["azul", "fellawen"])
      lastName: String @myDirective3(value: [{name: "ramdane", age: 12, id: "test"}])
      age: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var user = g.getTypeByName("User")!;
    var myDirective =
        user.getFieldByName("id")!.getDirectiveByName("@myDirective")!;
    var myDirectiveSerial = serializer.serializeDirectiveValue(myDirective);
    expect(myDirectiveSerial,
        '@myDirective(value: {name: "ramdane", age: 12, id: "test"})');

    var myDirective2 =
        user.getFieldByName("name")!.getDirectiveByName("@myDirective2")!;
    var myDirectiveSerial2 = serializer.serializeDirectiveValue(myDirective2);
    expect(myDirectiveSerial2, '@myDirective2(value: ["azul", "fellawen"])');

    var myDirective3 =
        user.getFieldByName("lastName")!.getDirectiveByName("@myDirective3")!;
    var myDirectiveSerial3 = serializer.serializeDirectiveValue(myDirective3);
    expect(myDirectiveSerial3,
        '@myDirective3(value: [{name: "ramdane", age: 12, id: "test"}])');
  });

  test("serializeSchemaDefinition - all root types", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    type Query {
      getValue: Int
    }

    type Mutation {
      updateValue: Int
    }

    type Subscription {
      watchValue: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "schema {",
        "query: Query",
        "mutation: Mutation",
        "subscription: Subscription",
        "}"
      ]),
    );
  });

  test("serializeSchemaDefinition - no Query", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    type Mutation {
      updateValue: Int
    }

    type Subscription {
      watchValue: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.contains("query"), isFalse);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "schema {",
        "mutation: Mutation",
        "subscription: Subscription",
        "}"
      ]),
    );
  });

  test("serializeSchemaDefinition - no Mutation", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    type Query {
      getValue: Int
    }

    type Subscription {
      watchValue: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.contains("mutation"), isFalse);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(
          ["schema {", "query: Query", "subscription: Subscription", "}"]),
    );
  });

  test("serializeSchemaDefinition - no Subscription", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    type Query {
      getValue: Int
    }

    type Mutation {
      updateValue: Int
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.contains("subscription"), isFalse);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(
          ["schema {", "query: Query", "mutation: Mutation", "}"]),
    );
  });

  test("serializeSchemaDefinition - no root types defined", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    type Something {
      name: String
    }
  ''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.trim().isEmpty, true);
  });

  test("serializeScalarDefinition test", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
  scalar Long
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeScalarDefinition(g.scalars["Long"]!);
    expect(serial, "scalar Long");
  });

  test("serializeDirectiveDefinition test", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    directive @myDirective(arg1: String) on FIELD_DEFINITION|OBJECT
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer
        .serializeDirectiveDefinition(g.directiveDefinitions["@myDirective"]!);
    expect(serial.trim(),
        "directive @myDirective(arg1: String) on FIELD_DEFINITION | OBJECT");
  });

  test("serializeInputDefinition test", () async {
    final g = GLParser(generateAllFieldsFragments: true);
    g.parse('''
    input UserInput {
      id: String
      name: String
      lastName: String
      age: Int
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeInputDefinition(
        g.inputs["UserInput"]!, CodeGenerationMode.client);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "input UserInput {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "}"
      ]),
    );
  });

  test("serializeTypeDefinition test", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    type User {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();
    // should seriaze skip on client types
    // but should skip fields with @glSkipOnServer directive
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "type User {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeTypeDefinition implements one interface", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface IBase {
      id: String
    }
    type User implements IBase {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();
    // should seriaze skip on client types
    // but should skip fields with @glSkipOnServer directive
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "type User implements IBase {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeTypeDefinition implements multiple interfaces", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface IBase {
      id: String
    }

    interface IBase2 {
      name: String
    }
    type User implements IBase&IBase2 {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();
    // should seriaze skip on client types
    // but should skip fields with @glSkipOnServer directive
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "type User implements IBase & IBase2 {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeInterfaceDefinition test", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    interface User  {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();

    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "interface User {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeInterfaceDefinition imlements one interface", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
interface IBase {
      id: String
    }
    interface User implements IBase {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();

    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "interface User implements IBase {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeInterfaceDefinition imlements multiple interfaces", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
interface IBase {
      id: String
    }

    interface IBase2 {
      id: String
    }
    interface User implements IBase&IBase2 {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @glSkipOnServer
      carId: ID! @glSkipOnClient
    }
    type Car {
      id: ID!
    }
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.generateSchema();

    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "interface User implements IBase & IBase2 {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "car: Car",
        "}"
      ]),
    );

    expect(serial.contains("carId"), isFalse);
  });

  test("serializeEnumDefinition test", () async {
    final g = GLParser(
        generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    g.parse('''
    enum Gender {male, female}
''');

    final serializer = GLGraphqSerializer(g);
    var serial = serializer.serializeEnumDefinition(g.enums["Gender"]!);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(["enum Gender {", "male female", "}"]),
    );
  });
}
