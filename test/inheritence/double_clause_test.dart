import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';



void main() async {
  test("multiple conflicts: Animal and User both appear as concrete and as inline fragments", () {
    final GLParser g = GLParser(generateAllFieldsFragments: false, autoGenerateQueries: false);

    const text = '''
interface BasicEntity {
  id: ID!
  creationDate: Int!
  lastUpdate: Int!
}

type User implements BasicEntity {
  id: ID!
  creationDate: Int!
  lastUpdate: Int!

  firstName: String
  lastName: String
}

type Animal implements BasicEntity {

  id: ID!
  creationDate: Int!
  lastUpdate: Int!

  name: String
  age: Int
}

type Query {
  getEntity: BasicEntity!
  getAnimal: Animal
  getUser: User
}

query getData {
  getAnimal { id }
  getUser { id }
  getEntity {
    id ... on Animal {name} ... on User {firstName}
  }
}

''';
    g.parse(text);
    var dartSerializer = DartSerializer(g);
    g.projectedInterfaces.forEach((k, v) {
      print(dartSerializer.serializeTypeDefinition(v, 'org'));
    });

    g.projectedTypes.forEach((k, v) {
      if(!k.endsWith('Response')){
        print(dartSerializer.serializeTypeDefinition(v, 'org'));
      }
    });

    // Animal and User each appear twice → 2 extra interfaces created, 3 total
    expect(g.projectedInterfaces.length, 3);

    // no interface may have two implementations from the same original schema type
    for (var iface in g.projectedInterfaces.values) {
      final seen = <String>{};
      for (var impl in iface.implementations) {
        final origin = impl.derivedFromType?.token ?? impl.token;
        expect(seen.contains(origin), isFalse,
            reason: '${iface.token} has two implementations both derived from "$origin"');
        seen.add(origin);
      }
    }
  });

  test("same switch claude for multiple interface implementations", () {
    final GLParser g = GLParser(generateAllFieldsFragments: false, autoGenerateQueries: false);

    const text = '''
interface BasicEntity {
  id: ID!
  creationDate: Int! 
  lastUpdate: Int! 
}

type User implements BasicEntity {
  id: ID!
  creationDate: Int! 
  lastUpdate: Int! 

  firstName: String
  lastName: String
}

type Animal implements BasicEntity {

  id: ID!
  creationDate: Int! 
  lastUpdate: Int! 

  name: String
  age: Int
}

type Query {
  getEntity: BasicEntity!
  getAnimal: Animal
  getUser: User
}

query getData {
  getAnimal { id   }
  getEntity {
    id ... on Animal {name} ... on User {firstName}
  }
}


''';
    g.parse(text);
    var dartSerializer = DartSerializer(g);
    g.projectedInterfaces.forEach((k, v) {
      print(dartSerializer.serializeTypeDefinition(v, 'org'));
    });

    g.projectedTypes.forEach((k, v) {
      if(!k.endsWith('Response')){
        print(dartSerializer.serializeTypeDefinition(v, 'org'));
      }
    });

    // Animal appears twice (getAnimal + getEntity) → 1 extra interface, 2 total
    expect(g.projectedInterfaces.length, 2);

    // no interface may have two implementations from the same original schema type
    for (var iface in g.projectedInterfaces.values) {
      final seen = <String>{};
      for (var impl in iface.implementations) {
        final origin = impl.derivedFromType?.token ?? impl.token;
        expect(seen.contains(origin), isFalse,
            reason: '${iface.token} has two implementations both derived from "$origin"');
        seen.add(origin);
      }
    }
  });
}