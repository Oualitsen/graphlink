import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_expand_grammar_extension.dart';

// Simple self-reference: Employee points back to itself.
const _selfCycle = '''
type Employee {
  id: ID!
  name: String!
  manager: Employee
}
type Query { getEmployee(id: ID!): Employee! }
''';

// Three-type cycle — graph traversal required to detect it.
// Department → Person (via head)
//            → Project (via project)
//            → Department (via owner)   ← closes the cycle
const _multiHopCycle = '''
type Department {
  id: ID!
  head: Person!
}
type Person {
  id: ID!
  name: String!
  project: Project!
}
type Project {
  id: ID!
  title: String!
  owner: Department!
}
type Query { getDepartment(id: ID!): Department! }
''';

// Acyclic: Author → Book is one-way, no path back.
const _noCycle = '''
type Author {
  id: ID!
  name: String!
}
type Book {
  id: ID!
  title: String!
  author: Author!
}
type Query { getBook(id: ID!): Book! }
''';

// Interface-mediated cycle:
// Person → interface Owned (via pet)
// Dog/Cat implement Owned and have owner: Person!  ← closes the cycle
// The cycle passes through an abstract type and requires expanding implementors.
const _interfaceCycle = '''
interface Owned {
  owner: Person!
}
type Person {
  id: ID!
  name: String!
  pet: Owned!
}
type Dog implements Owned {
  id: ID!
  breed: String!
  owner: Person!
}
type Cat implements Owned {
  id: ID!
  color: String!
  owner: Person!
}
type Query { getPerson(id: ID!): Person! }
''';

// Interface present but no cycle: Node is a pure read interface, nothing points back.
const _interfaceNoCycle = '''
interface Node {
  id: ID!
}
type Post implements Node {
  id: ID!
  title: String!
  author: Author!
}
type Author implements Node {
  id: ID!
  name: String!
}
type Query { getPost(id: ID!): Post! }
''';

GLParser parse(String schema) => GLParser()..parse(schema);

GLParser parseWithGeneration(String schema) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
    )..parse(schema);

void main() {
  group('detectCycles', () {
    test('acyclic schema → empty list', () {
      expect(parse(_noCycle).detectCycles(), isEmpty);
    });

    test('self-cycle → manager/Employee edge detected', () {
      final cycles = parse(_selfCycle).detectCycles();
      expect(cycles, isNotEmpty);
      expect(cycles.map((e) => e.field.name.token), contains('manager'));
      expect(cycles.map((e) => e.declaringType.token), contains('Employee'));
    });

    test('multi-hop cycle → all three closing edges detected', () {
      final cycles = parse(_multiHopCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      final typeNames = cycles.map((e) => e.declaringType.token).toSet();
      expect(fieldNames, containsAll(['head', 'project', 'owner']));
      expect(typeNames, containsAll(['Department', 'Person', 'Project']));
    });

    test('non-cyclic scalar fields are not included', () {
      final cycles = parse(_selfCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      expect(fieldNames, isNot(contains('id')));
      expect(fieldNames, isNot(contains('name')));
    });

    test('each entry pairs the right field with its declaring type', () {
      final cycles = parse(_multiHopCycle).detectCycles();
      // head is declared on Department
      final headEntry = cycles.firstWhere((e) => e.field.name.token == 'head');
      expect(headEntry.declaringType.token, 'Department');
      // owner is declared on Project
      final ownerEntry = cycles.firstWhere((e) => e.field.name.token == 'owner');
      expect(ownerEntry.declaringType.token, 'Project');
    });
  });

  group('detectCycles — union-mediated', () {
    // Union cycle: Person → union Pet (Dog | Cat) via pet
    // Dog.owner: Person! closes the cycle.
    const unionCycle = '''
union Pet = Dog | Cat
type Person {
  id: ID!
  name: String!
  pet: Pet!
}
type Dog {
  id: ID!
  breed: String!
  owner: Person!
}
type Cat {
  id: ID!
  color: String!
}
type Query { getPerson(id: ID!): Person! }
''';

    // Union present but no path back — acyclic.
    const unionNoCycle = '''
union Media = Photo | Video
type Photo {
  id: ID!
  url: String!
}
type Video {
  id: ID!
  url: String!
  duration: Int!
}
type Post {
  id: ID!
  attachment: Media
}
type Query { getPost(id: ID!): Post! }
''';

    test('union cycle → Person.pet and Dog.owner detected', () {
      final cycles = parse(unionCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      final typeNames = cycles.map((e) => e.declaringType.token).toSet();
      expect(fieldNames, containsAll(['pet', 'owner']));
      expect(typeNames, containsAll(['Person', 'Dog']));
    });

    test('union cycle → Cat has no back-edge, not included', () {
      final cycles = parse(unionCycle).detectCycles();
      final typeNames = cycles.map((e) => e.declaringType.token).toSet();
      expect(typeNames, isNot(contains('Cat')));
    });

    test('union cycle → scalar fields not included', () {
      final cycles = parse(unionCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      expect(fieldNames, isNot(contains('breed')));
      expect(fieldNames, isNot(contains('name')));
    });

    test('union without cycle → empty list', () {
      expect(parse(unionNoCycle).detectCycles(), isEmpty);
    });
  });

  group('generated fragment nullability', () {
    // Helper: walks response type → field → projected type.
    GLTypeDefinition projected(GLParser g, String query, String field) {
      final response = g.queries[GLOperationKey(query, GLQueryType.query)]!.getGeneratedTypeDefinition();
      final f = response.fields.firstWhere((f) => f.name.token == field);
      return g.projectedTypes[f.type.inlineType.token]!;
    }

    test('self-cycle: manager is nullable and resolves to a projected Employee type', () {
      final g = parseWithGeneration(_selfCycle);
      final employee = projected(g, 'getEmployee', 'getEmployee');
      final manager = employee.fields.firstWhere((f) => f.name.token == 'manager');
      expect(manager.type.nullable, isTrue);
      final managerProjection = g.projectedTypes[manager.type.inlineType.token];
      expect(managerProjection, isNotNull);
      expect(managerProjection!.fields.map((f) => f.name.token),
          containsAll(['id', 'name']));
    });

    test('self-cycle: scalar fields on Employee are not nullable', () {
      final g = parseWithGeneration(_selfCycle);
      final employee = projected(g, 'getEmployee', 'getEmployee');
      final name = employee.fields.firstWhere((f) => f.name.token == 'name');
      expect(name.type.nullable, isFalse);
    });

    test('multi-hop: head is nullable and resolves to a projected Person type', () {
      final g = parseWithGeneration(_multiHopCycle);
      final department = projected(g, 'getDepartment', 'getDepartment');
      final head = department.fields.firstWhere((f) => f.name.token == 'head');
      expect(head.type.nullable, isTrue);
      final personProjection = g.projectedTypes[head.type.inlineType.token];
      expect(personProjection, isNotNull);
      expect(personProjection!.fields.map((f) => f.name.token),
          containsAll(['id', 'name']));
    });

    test('multi-hop: project is nullable and resolves to a projected Project type', () {
      final g = parseWithGeneration(_multiHopCycle);
      final department = projected(g, 'getDepartment', 'getDepartment');
      final head = department.fields.firstWhere((f) => f.name.token == 'head');
      final person = g.projectedTypes[head.type.inlineType.token]!;
      final project = person.fields.firstWhere((f) => f.name.token == 'project');
      expect(project.type.nullable, isTrue);
      final projectProjection = g.projectedTypes[project.type.inlineType.token];
      expect(projectProjection, isNotNull);
      expect(projectProjection!.fields.map((f) => f.name.token),
          containsAll(['id', 'title']));
    });

    test('multi-hop: owner is nullable and resolves to a projected Department type', () {
      final g = parseWithGeneration(_multiHopCycle);
      final department = projected(g, 'getDepartment', 'getDepartment');
      final head = department.fields.firstWhere((f) => f.name.token == 'head');
      final person = g.projectedTypes[head.type.inlineType.token]!;
      final project = g.projectedTypes[
          person.fields.firstWhere((f) => f.name.token == 'project')
              .type.inlineType.token]!;
      final owner = project.fields.firstWhere((f) => f.name.token == 'owner');
      expect(owner.type.nullable, isTrue);
      final departmentProjection = g.projectedTypes[owner.type.inlineType.token];
      expect(departmentProjection, isNotNull);
      expect(departmentProjection!.fields.map((f) => f.name.token),
          containsAll(['id']));
    });

    test('acyclic: author stays non-null and resolves to a projected Author type', () {
      final g = parseWithGeneration(_noCycle);
      final book = projected(g, 'getBook', 'getBook');
      final author = book.fields.firstWhere((f) => f.name.token == 'author');
      expect(author.type.nullable, isFalse);
      final authorProjection = g.projectedTypes[author.type.inlineType.token];
      expect(authorProjection, isNotNull);
      expect(authorProjection!.fields.map((f) => f.name.token),
          containsAll(['id', 'name']));
    });

    test('interface cycle parses with generation', () {
      expect(() => parseWithGeneration(_interfaceCycle), returnsNormally);
    });

    test('interface no-cycle parses with generation', () {
      expect(() => parseWithGeneration(_interfaceNoCycle), returnsNormally);
    });
  });

  group('detectCycles — interface-mediated', () {
    test('interface cycle → Person.pet and Dog.owner / Cat.owner detected', () {
      final cycles = parse(_interfaceCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      final typeNames = cycles.map((e) => e.declaringType.token).toSet();
      // Person.pet → interface Owned closes back via Dog/Cat.owner → Person
      expect(fieldNames, contains('pet'));
      expect(typeNames, contains('Person'));
      // The reverse edges on the concrete implementors also close the cycle
      expect(fieldNames, containsAll(['owner']));
      expect(typeNames, containsAll(['Dog', 'Cat']));
    });

    test('interface cycle → scalar fields on implementors not included', () {
      final cycles = parse(_interfaceCycle).detectCycles();
      final fieldNames = cycles.map((e) => e.field.name.token).toSet();
      expect(fieldNames, isNot(contains('breed')));
      expect(fieldNames, isNot(contains('color')));
      expect(fieldNames, isNot(contains('name')));
    });

    test('interface without cycle → empty list', () {
      expect(parse(_interfaceNoCycle).detectCycles(), isEmpty);
    });
  });
}
