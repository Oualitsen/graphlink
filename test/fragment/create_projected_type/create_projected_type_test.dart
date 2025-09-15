import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:petitparser/petitparser.dart';

final GQGrammar g = GQGrammar();

void main() async {
  test("createProjectedType 1", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    name: String
  }

  type Query {
    getPerson: Person!
  }
  query getPerson {
    getPerson {
      name
    }
  }

''');
    expect(parsed is Success, true);
    var block = g.queries['getPerson']!.elements.first.block!;
    var type = g.getType("Person".toToken());
    var newType = g.createProjectedType(type: type, projectionMap: block.projections, directives: type.getDirectives());
  });

  test("createProjectedType 2", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    name: String
    animal: Animal
  }

  interface Animal {
    name: String
  }

  type Dog implements Animal {
    name: String
    race: String
    age: Int
  }

  type Cat implements Animal {
    name: String
    color: String
    furr: String
  }

  type Query {
    getPerson: Person!
  }
  query getPerson {
    getPerson {
      name
      animal {
        name
      }
    }
  }

''');
    expect(parsed is Success, true);

    var serializer = DartSerializer(g);
    g.projectedTypes.values.forEach((pt) {
      print("############## ${pt.token} ###########");
      print(serializer.serializeTypeDefinition(pt, ""));
    });
  });

  test("createProjectedType 3", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    name: String
    animal: Animal
  }

  interface Animal {
    name: String
  }

  type Dog implements Animal {
    name: String
    race: String
    age: Int
  }

  type Cat implements Animal {
    name: String
    color: String
    furr: String
  }

  type Query {
    getPerson: Person!
#    getAnimal: Animal!
  }
  query getPerson {

    
    getPerson {
      name
      animal {
        name ... on Cat {
          color furr
        }
        ... on Dog {
          race age
        }
      }
    }

    
  }

''');
    expect(parsed is Success, true);

    var serializer = DartSerializer(g);
    g.projectedTypes.values.forEach((pt) {
      print("############## ${pt.token} ###########2");
      print(serializer.serializeTypeDefinition(pt, ""));
    });
  });

  test("createProjectedType 4", () {
    final GQGrammar g = GQGrammar(generateAllFieldsFragments: true);
    var parsed = g.parse('''
  type Person {
    id: String
    name: String
    lastName: String
  }

  type Query {
    getPerson: Person!
  }
  query getPerson {
    getPerson {
      name ... on Person {
        id
      }
    }
  }

''');
    expect(parsed is Success, true);
    var serializer = DartSerializer(g);
    g.projectedTypes.values.forEach((pt) {
      print("############## ${pt.token} ###########");
      print(serializer.serializeTypeDefinition(pt, ""));
    });
  });
}
