import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';

void main() {
  test("extend scalar test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend scalar void @gqServiceName(name: "TestService")
    scalar void
  ''');

    expect(result is Success, true);
    var scalar = g.scalars['void']!;
    expect(scalar.getDirectiveByName('@gqServiceName'), isNotNull);
  });

  test("extend enum test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend enum Animal  @gqServiceName(name: "TestService")  {
      horse
    }
    enum Animal {
      dog cat
    }
  ''');

    expect(result is Success, true);
    var animal = g.enums['Animal']!;
    expect(animal.getDirectiveByName('@gqServiceName'), isNotNull);
    expect(animal.values.map((e) => e.value.token), containsAll(['dog', 'cat', 'horse']));
  });

  test("extend input test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend input UserInput @gqServiceName(name: "TestService"){
      password: String
    }

    input UserInput {
      username: String
    }

    extend input UserInput {
      password: String @gqHide
    }
    
  ''');

    expect(result is Success, true);
    var userInput = g.inputs['UserInput']!;
    expect(userInput.getDirectiveByName('@gqServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend type test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend type User @gqServiceName(name: "TestService"){
      password: String
    }

    type User {
      username: String
    }

    extend type User {
      password: String @gqHide
    }
    
  ''');

    expect(result is Success, true);
    var userInput = g.types['User']!;
    expect(userInput.getDirectiveByName('@gqServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend interface test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend interface User @gqServiceName(name: "TestService"){
      password: String
    }

    interface User {
      username: String
    }

    extend interface User {
      password: String @gqHide
    }
    
  ''');

    expect(result is Success, true);
    var userInput = g.interfaces['User']!;
    expect(userInput.getDirectiveByName('@gqServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend union test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    type type1 {
      name: String
    }

    type type2 {
      name: String
    }

    type type3 {
      name: String
    }

    extend union MyUnion = type3

    union MyUnion = type1 | type2
    extend union MyUnion @deprecated(reason: "Use other")
    
  ''');

    expect(result is Success, true);
    var myUnion = g.unions['MyUnion']!;
    expect(myUnion.typeNames.map((e) => e.token), containsAll(['type1', 'type2', 'type3']));
    expect(myUnion.getDirectiveByName("@deprecated"), isNotNull);
  });

  test("extend schema test", () {
    final g = GQGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    schema {
      query: TestQuery
    }
   

    extend schema {
      mutation: TestMutation
    }

    extend schema {
      subscription: TestSubscription
    }
    extend schema @auth(role: "ADMIN")

    
  ''');

    expect(result is Success, true);
    var schema = g.schema;
    expect(schema.getByQueryType(GQQueryType.query), "TestQuery");
    expect(schema.getByQueryType(GQQueryType.mutation), "TestMutation");
    expect(schema.getDirectiveByName("@auth"), isNotNull);
  });
}
