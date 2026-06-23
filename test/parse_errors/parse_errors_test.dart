import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  

  test("Parse error type implements interface but does not declare a field",
      () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    interface IBase {
      id: String
    }
    type User implements IBase{
      name: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Type User implements IBase but does not declare field id"),
        ),
      ),
    );
  });

  test("Exception when scalar has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    scalar Long
    scalar Long
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Scalar Long has already been declared"),
        ),
      ),
    );
  });

  test("Exception when directive has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    directive @Getter on OBJECT
    directive @Getter on INTERFACE
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Directive @Getter has already been declared"),
        ),
      ),
    );
  });

  test("Exception when enum has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    enum Gender {male, female}
    enum Gender {unspecified}
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Enum Gender has already been declared"),
        ),
      ),
    );
  });

  test("Exception when interface has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    interface Interface1 {
      id: String
    }
    interface Interface1 {
      name: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Interface Interface1 has already been declared"),
        ),
      ),
    );
  });

  test("Exception when type has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type User {
      id: String
    }
    type User {
      name: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Type User has already been declared"),
        ),
      ),
    );
  });

  test("Exception when input has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    input UserInput {
      id: String
    }
    input UserInput {
      name: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Input UserInput has already been declared"),
        ),
      ),
    );
  });

  test("Exception when union has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type Type1 {
      id: String
    }
    type Type2 {
      name: String
    }
    union MyUnion = Type1 | Type2
    type Type3 {
      id: String
    }
    type Type4 {
      name: String
    }
    union MyUnion = Typ3 | Type3

'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Union MyUnion has already been declared"),
        ),
      ),
    );
  });

  test("Exception when fragment has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type User {
      id: String
    }
    fragment Frag1 on User {id}
    type City {
      name: String
    }
    fragment Frag1 on City {name}

'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Fragment Frag1 has already been declared"),
        ),
      ),
    );
  });

  test("Exception when query has already been defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type Query {
      findUser: User
    }
    type User {
      name: String
    }
    type City {
      zipcode: String
    }
    query GetUser {
      findUser {
        name
      }
    }

    query GetUser {
      City {
        zipcode
      }
    }

'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "query GetUser has already been declared"),
        ),
      ),
    );
  });

  test("Exception when input is not defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    input UserInput {
      name: String
      city: CityInput
    }

'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "CityInput is not a scalar, input or enum"),
        ),
      ),
    );
  });

  test("Exception when type is not defined", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type UserInput {
      name: String
      city: City
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "City is not a scalar, enum, type, interface or union"),
        ),
      ),
    );
  });

  test("Exception when query argument not found", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type User {
      name: String
    }
    type Query {
      getUser(name: String): User
    }
    query getUser(\$name: String) {
        getUser(name: \$invalid) {
          name
        }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Argument \$invalid was not declared"),
        ),
      ),
    );
  });

  test("Exception when schema is already defined", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    schema  {
      query: Query
    }
    type Query {
      getId: Int!
    }

    type Query2 {
      getId2: Int!
    }
    schema  {
      query: Query2
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("A schema has already been defined"),
        ),
      ),
    );
  });

  test("Exception when projection is required but not found", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }

    query GetUser {
      getUser {
        id city
      }
    }
    
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Field 'city' of type 'User' must have a selection of subfield "),
        ),
      ),
    );
  });

  test("Exception when projection is not required but found", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }

    query GetUser {
      getUser {
        id {
          name
        }
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Field 'id' of type 'User' should not have a selection of subfields "),
        ),
      ),
    );
  });

  test(
      "Exception when inline projection on a given type does not implement the target type",
      () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    interface Animal {
      sound: String
    }

    type Dog implements Animal {
      sound: String
      name: String
    }

    type Cat implements Animal {
      sound: String
      name: String
    }

    type Human { #does not implement animal
      firstName: String!
      lastName: String
    }
    
    type Query {
      getAnimal: Animal
    }

    query GetUser {
      getAnimal {
        ... on Dog {
          sound
        }
        ... on Cat {
          name
        }
        ... on Human {
          firstName lastName
        }
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Type 'Human' does not implement 'Animal'"),
        ),
      ),
    );
  });

  test(
      "Exception when inline projection on a given type does not implement the target type 2",
      () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type Dog  {
      sound: String
      name: String
    }

    type Cat  {
      sound: String
      name: String
    }
    
    
    type Query {
      getCat: Cat
    }

    query GetUser {
      getCat {
        ... on Dog {
          sound
        }
        
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Type 'Dog' does not implement 'Cat'"),
        ),
      ),
    );
  });

  test("Exception when fragment is applied to the wrong type", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }

    fragment CityFragment on City {
      zipcode
    }

    query GetUser {
      getUser {
        ... CityFragment
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Fragment CityFragment cannot be applied to type User"),
        ),
      ),
    );
  });

  test("Exception when projection is not required but found", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }

    fragment UserFrag on User {
      id name name2
    }

    query GetUser {
      getUser {
        ... UserFrag
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Could not find field 'name2' on type 'User'"),
        ),
      ),
    );
  });

  test("Exception when fragment projection conatins an undeclared field", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }
    fragment CityFrag on City {
      zipcode zip2
     }

    fragment UserFrag on User {
      id name city {
        ... CityFrag
      }
    }

    query GetUser {
      getUser {
        ... UserFrag
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Could not find field 'zip2' on type 'City'"),
        ),
      ),
    );
  });

  test("Exception on duplicate field defition on query", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
    }

    fragment UserFrag on User {
      id name 
    }

    query GetUser {
      getUser {
        ... UserFrag
      }

      getUser {
        id
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "Duplicate field defition on type GetUserResponse, field: getUser"),
        ),
      ),
    );
  });

  test("Exception on duplicate query definition", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
      getCity: City
    }

    fragment UserFrag on User {
      id name 
    }

    query GetUser2 {
      getUser {
        id
      }
    }
    query GetUser2 {
      getCity {
        zipcode
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "query GetUser2 has already been declared"),
        ),
      ),
    );
  });

  test("Exception on different objects with same name", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    type User {
      id: String
      name: String
      city: City
    }
    type City {
      zipcode: String
    }
    type Query {
      getUser: User
      getCity: City
    }

    fragment UserFrag on User {
      id name 
    }

    query GetUser {
      getUser @glTypeName(name: "Data") {
        id
      }
    }
    query GetUser2 {
      getCity @glTypeName(name: "Data") {
        zipcode
      }
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "You have names two object the same name 'Data' but have diffrent fields. Data_1.fields are: [[id: String]], Data_2.fields are: [[zipcode: String]]. Please consider renaming one of them"),
        ),
      ),
    );
  });

  test("Exception on interface implement undefined interface", () {
    final GLParser g = GLParser();
    expect(
      () => g.parse('''
    interface BasicEntity implements IBase {
      id: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains("Interface IBase is not found"),
        ),
      ),
    );
  });

  test("Exception on interface implement more than once", () {
    final GLParser g = GLParser();

    expect(
      () => g.parse('''
    interface BasicEntity implements IBase & IBase {
      id: String
      name: String
    }

    interface IBase {
      name: String
    }
'''),
      throwsA(
        isA<ParseException>().having(
          (e) => e.errorMessage,
          'errorMessage',
          contains(
              "interface IBase has been implemented more than once"),
        ),
      ),
    );
  });
}
