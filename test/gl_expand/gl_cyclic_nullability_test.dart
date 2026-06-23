import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';

GLParser parseAuto(String schema, {int defaultExpandDepth = 1}) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultExpandDepth: defaultExpandDepth,
    )..parse(schema);

/// Returns the projected type produced for [queryField] inside query [queryName].
GLTypeDefinition projectedFor(GLParser g, String queryName, String queryField) {
  final response = g.queries[GLOperationKey(queryName, GLQueryType.query)]!.getGeneratedTypeDefinition();
  final field = response.fields.firstWhere((f) => f.name.token == queryField);
  return g.projectedTypes[field.type.inlineType.token]!;
}

// ─── concrete type cycles ──────────────────────────────────────────────────

const _authorBook = '''
type Author {
  id: ID!
  name: String!
  book: Book!
}
type Book {
  id: ID!
  title: String!
  author: Author!
}
type Query { getAuthor(id: ID!): Author! }
''';

const _employee = '''
type Employee {
  id: ID!
  name: String!
  manager: Employee!
}
type Query { getEmployee(id: ID!): Employee! }
''';

const _category = '''
type Category {
  id: ID!
  label: String!
  children: [Category!]!
}
type Query { getCategory(id: ID!): Category! }
''';

// ─── interface-mediated cycle ──────────────────────────────────────────────
// Person.pet: Owned! — Owned is an interface; Dog/Cat implement it with
// owner: Person! — this closes the Person ↔ Dog/Cat cycle through the interface.

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

// ─── union-mediated cycle ──────────────────────────────────────────────────
// Person.pet: Pet! — Pet is a union; Dog (a member) has owner: Person! which
// closes the cycle.  Auto-generated queries can't build _all_fields_Pet, so
// we supply an explicit query with inline-fragment selections.

const _unionCycle = '''
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

query getPerson {
  getPerson {
    id
    name
    pet {
      ... on Dog { id breed owner { id name } }
      ... on Cat { id color }
    }
  }
}
''';

// ─── acyclic baseline ─────────────────────────────────────────────────────

const _acyclic = '''
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

void main() {
  group('cyclic field nullability — concrete type cycle', () {
    test('two-type: Author.book nullable (schema declares Book!)', () {
      final g = parseAuto(_authorBook);
      final author = projectedFor(g, 'getAuthor', 'getAuthor');
      final bookField = author.fields.firstWhere((f) => f.name.token == 'book');
      expect(bookField.type.nullable, isTrue,
          reason: 'book closes the Author↔Book cycle');
    });

    test('self-cycle: Employee.manager nullable (schema declares Employee!)', () {
      final g = parseAuto(_employee);
      final employee = projectedFor(g, 'getEmployee', 'getEmployee');
      final managerField =
          employee.fields.firstWhere((f) => f.name.token == 'manager');
      expect(managerField.type.nullable, isTrue);
    });

    test('list edge: outer nullable, inner element stays non-null', () {
      final g = parseAuto(_category);
      final category = projectedFor(g, 'getCategory', 'getCategory');
      final childrenField =
          category.fields.firstWhere((f) => f.name.token == 'children');
      final listType = childrenField.type as GLListType;
      expect(listType.nullable, isTrue,
          reason: 'outer list wrapper must be nullable');
      expect(listType.type.nullable, isFalse,
          reason: 'inner element nullability is unchanged');
    });
  });

  group('cyclic field nullability — interface-mediated cycle', () {
    test('Person.pet is nullable when interface implementors close the cycle', () {
      final g = parseAuto(_interfaceCycle);
      final person = projectedFor(g, 'getPerson', 'getPerson');
      final petField = person.fields.firstWhere((f) => f.name.token == 'pet');
      expect(petField.type.nullable, isTrue,
          reason: 'pet field target Owned has implementors (Dog/Cat) in same SCC as Person');
    });

    test('Dog.owner is nullable in its projected type', () {
      final g = parseAuto(_interfaceCycle);
      // The cyclic edge is relaxed to nullable on the declared type, so Dog's
      // projected type is the declared Dog itself (registered under its bare
      // name).
      final dogProjected = g.projectedTypes['Dog']!;
      final ownerField =
          dogProjected.fields.firstWhere((f) => f.name.token == 'owner');
      expect(ownerField.type.nullable, isTrue,
          reason: 'Dog.owner closes the cycle back to Person');
    });
  });

  group('cyclic field nullability — union-mediated cycle', () {
    test('Person.pet is nullable when a union member closes the cycle', () {
      // Union auto-gen not supported: query is hand-written in the schema.
      final g = GLParser()..parse(_unionCycle);
      final person = projectedFor(g, 'getPerson', 'getPerson');
      final petField = person.fields.firstWhere((f) => f.name.token == 'pet');
      expect(petField.type.nullable, isTrue,
          reason: 'pet field target Pet has member Dog in same SCC as Person');
    });
  });

  group('non-cyclic fields keep declared nullability', () {
    test('acyclic non-null edge stays non-null', () {
      final g = parseAuto(_acyclic);
      final book = projectedFor(g, 'getBook', 'getBook');
      final authorField =
          book.fields.firstWhere((f) => f.name.token == 'author');
      expect(authorField.type.nullable, isFalse,
          reason: 'Author is not in a cycle — nullability must not be changed');
    });

    test('scalar fields on cyclic types are unaffected', () {
      final g = parseAuto(_employee);
      final employee = projectedFor(g, 'getEmployee', 'getEmployee');
      final nameField =
          employee.fields.firstWhere((f) => f.name.token == 'name');
      expect(nameField.type.nullable, isFalse);
    });
  });
}
