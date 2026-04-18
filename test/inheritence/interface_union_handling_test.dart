import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  test("Interface response generation handling ", () {
    final GLParser g = GLParser(identityFields: ["id"], autoGenerateQueries: true, generateAllFieldsFragments: true);

    const schema = '''

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
    indoor: Boolean!
}

type Query {
    getAnimal: Animal!
}


query getMyAnimal {
    getAnimal {
        ... on Dog {
            breed
            name
        }
       ... on Cat {
            indoor
            name
        }
    }
}
''';

    g.parse(schema);
    var getAnimalResponse = g.projectedTypes['GetAnimalResponse']!;
    var field = getAnimalResponse.getFieldByName('getAnimal')!;
    expect(field.type.token, 'Animal');

    var getMyAnimalResponse = g.projectedTypes['GetMyAnimalResponse']!;
    var myAnimalField = getMyAnimalResponse.getFieldByName('getAnimal')!;
    expect(myAnimalField.type.token, 'Animal_Name');

  });


  test("Union response generation handling ", () {
    final GLParser g = GLParser(identityFields: ["id"], autoGenerateQueries: true, generateAllFieldsFragments: true);

    const schema = '''

union Animal = Dog | Cat

type Dog  {
    id: ID!
    name: String!
    breed: String!
}

type Cat  {
    id: ID!
    name: String!
    indoor: Boolean!
}

type Query {
    getAnimal: Animal!
}


query getMyAnimal {
    getAnimal {
        ... on Dog {
            breed
            name
        }
       ... on Cat {
            indoor
            name
        }
    }
}
''';

    g.parse(schema);
    var getAnimalResponse = g.projectedTypes['GetAnimalResponse']!;
    var field = getAnimalResponse.getFieldByName('getAnimal')!;
    expect(field.type.token, 'Animal');

    var getMyAnimalResponse = g.projectedTypes['GetMyAnimalResponse']!;
    var myAnimalField = getMyAnimalResponse.getFieldByName('getAnimal')!;
    expect(myAnimalField.type.token, 'Animal_Name');

  });
}
