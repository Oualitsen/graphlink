
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';

final GQGrammar g = GQGrammar();

void main() {
  

  test("serializeSchemaDefinition - all root types", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
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
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
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
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    type Mutation {
      updateValue: Int
    }

    type Subscription {
      watchValue: Int
    }
  ''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
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
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    type Query {
      getValue: Int
    }

    type Subscription {
      watchValue: Int
    }
  ''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.contains("mutation"), isFalse);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(
          ["schema {", "query: Query", "subscription: Subscription", "}"]),
    );
  });

  test("serializeSchemaDefinition - no Subscription", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    type Query {
      getValue: Int
    }

    type Mutation {
      updateValue: Int
    }
  ''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.contains("subscription"), isFalse);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder(
          ["schema {", "query: Query", "mutation: Mutation", "}"]),
    );
  });

  test("serializeSchemaDefinition - no root types defined", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    type Something {
      name: String
    }
  ''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeSchemaDefinition(g.schema);
    expect(serial.trim().isEmpty, true);
  });

  test("serializeScalarDefinition test", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result =  g.parse('''
  scalar Long
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeScalarDefinition(g.scalars["Long"]!);
    expect(serial, "scalar Long");
  });

  test("serializeDirectiveDefinition test", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result =  g.parse('''
    directive @myDirective(arg1: String) on FIELD_DEFINITION|OBJECT
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer
        .serializeDirectiveDefinition(g.directiveDefinitions["@myDirective"]!);
    expect(serial.trim(),
        "directive @myDirective(arg1: String) on FIELD_DEFINITION | OBJECT");
  });

  test("serializeInputDefinition test", () async {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    input UserInput {
      id: String
      name: String
      lastName: String
      age: Int
    }
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeInputDefinition(g.inputs["UserInput"]!);
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
    final g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var result =  g.parse('''
    type User @gqSkipOnServer {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @gqSkipOnServer
    }
    type Car {
      id: ID!
    }
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeTypeDefinition(g.getType("User"));
    // should seriaze skip on server types
    // but should skip fields with @gqSkipOnServer directive
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "type User {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "}"
      ]),
    );

    expect(serial.contains("car"), isFalse);
  });


  test("serializeInterfaceDefinition test", () async {
    final g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var result =  g.parse('''
    interface User  {
      id: String
      name: String
      lastName: String
      age: Int
      car: Car @gqSkipOnServer
    }
    type Car {
      id: ID!
    }
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeInterfaceDefinition(g.interfaces["User"]!);

    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "interface User {",
        "id: String",
        "name: String",
        "lastName: String",
        "age: Int",
        "}"
      ]),
    );

    expect(serial.contains("car"), isFalse);
  });



  test("serializeEnumDefinition test", () async {
    final g = GQGrammar(generateAllFieldsFragments: true, mode: CodeGenerationMode.server);
    var result =  g.parse('''
    enum Gender {male, female}
''');
    expect(result is Success, true);
    final serializer = GraphqSerializer(g);
    var serial = serializer.serializeEnumDefinition(g.enums["Gender"]!);
    expect(
      serial.split("\n").map((str) => str.trim()),
      containsAllInOrder([
        "enum Gender {",
        "male female",
        "}"
      ]),
    );

  });
}
