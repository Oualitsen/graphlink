import 'package:petitparser/petitparser.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/gl_grammar.dart';

void main() {
  test("extend scalar test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend scalar void @glServiceName(name: "TestService")
    scalar void
  ''');

    expect(result is Success, true);
    var scalar = g.scalars['void']!;
    expect(scalar.getDirectiveByName('@glServiceName'), isNotNull);
  });

  test("extend enum test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend enum Animal  @glServiceName(name: "TestService")  {
      horse
    }
    enum Animal {
      dog cat
    }
  ''');

    expect(result is Success, true);
    var animal = g.enums['Animal']!;
    expect(animal.getDirectiveByName('@glServiceName'), isNotNull);
    expect(animal.values.map((e) => e.value.token), containsAll(['dog', 'cat', 'horse']));
  });

  test("extend input test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend input UserInput @glServiceName(name: "TestService"){
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
    expect(userInput.getDirectiveByName('@glServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend type test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend type User @glServiceName(name: "TestService"){
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
    expect(userInput.getDirectiveByName('@glServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend interface test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
    var result = g.parse('''
    extend interface User @glServiceName(name: "TestService"){
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
    expect(userInput.getDirectiveByName('@glServiceName'), isNotNull);
    expect(userInput.fields.map((e) => e.name.token), containsAll(['password', 'username']));
    var password = userInput.getFieldByName("password")!;
    expect(password.getDirectiveByName("@gqHide"), isNotNull);
  });

  test("extend union test", () {
    final g = GLGrammar(generateAllFieldsFragments: true);
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
    final g = GLGrammar(generateAllFieldsFragments: true);
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
    expect(schema.getByQueryType(GLQueryType.query), "TestQuery");
    expect(schema.getByQueryType(GLQueryType.mutation), "TestMutation");
    expect(schema.getDirectiveByName("@auth"), isNotNull);
  });

  test("throw when when trying to change the type of a field", () {
    final g = GLGrammar(generateAllFieldsFragments: true);

    expect(
      () => g.parse('''
    extend type User {
      password: String
    }
    type User {
      password: Int
    }
    
  '''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("You cannot change field type in an extension line: 5 column: 7"),
        ),
      ),
    );
  });

  test("throw when when trying to change the type of a field nullability", () {
    final g = GLGrammar(generateAllFieldsFragments: true);

    expect(
      () => g.parse('''
    extend type User {
      password: String
    }
    type User {
      password: String!
    }
    
  '''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("You cannot change field type in an extension line: 5 column: 7"),
        ),
      ),
    );
  });

  test("throw when when trying to change field arguments", () {
    final g = GLGrammar(generateAllFieldsFragments: true);

    expect(
      () => g.parse('''
    extend type User {
      password: String
    }
    type User {
      password(id: Int): String
    }
    
  '''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("You cannot add/remove arguments in an extension line: 5 column: 7"),
        ),
      ),
    );
  });

  test("throw when when trying to change field argument types", () {
    final g = GLGrammar(generateAllFieldsFragments: true);

    expect(
      () => g.parse('''
    extend type User {
      password(id: String): String
    }
    type User {
      password(id: Int): String
    }
    
  '''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("You cannot alter argument type in an extension line: 5 column: 16"),
        ),
      ),
    );
  });

  test("throw when when trying to change field argument nullability", () {
    final g = GLGrammar(generateAllFieldsFragments: true);

    expect(
      () => g.parse('''
    extend type User {
      password(id: String): String
    }
    type User {
      password(id: String!): String
    }
    
  '''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("You cannot alter argument type in an extension line: 5 column: 16"),
        ),
      ),
    );
  });
}
