import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_expand_grammar_extension.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';

GLParser parseAuto(String schema, {int defaultExpandDepth = 1}) => GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      defaultExpandDepth: defaultExpandDepth,
    )..parse(schema);

// Self-cycle.
const _employee = '''
type Employee {
  id: ID!
  name: String!
  manager: Employee!
}
type Query { getEmployee(id: ID!): Employee! }
''';

// Two-type cycle.
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

// Three-type cycle.
const _multiHop = '''
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

// Interface-mediated cycle.
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

/// Internal/runtime scaffolding types we don't care about here: anything the
/// generator injects (GraphLink*) or the per-operation response wrappers.
bool _isNoise(String name) =>
    name.startsWith('GraphLink') || name.toLowerCase().endsWith('response');

/// Prints every projected type / interface (minus runtime scaffolding), tagging
/// the ones whose origin type sits in a cycle, and returns the printed cyclic
/// names for assertions.
List<String> dumpProjected(String label, GLParser g) {
  final cyclic = g.cyclicTypeNames;
  print('\n=== $label ===');
  print('cyclic source types: ${cyclic.toList()..sort()}');

  final cyclicNames = <String>[];

  // A cyclic projected type is now the declared type itself (its cyclic edges
  // relaxed to nullable), registered under its bare schema name — so flag by
  // membership in cyclicTypeNames rather than derivedFromType origin.
  print('-- projectedTypes --');
  for (final entry in g.projectedTypes.entries) {
    if (_isNoise(entry.key)) continue;
    final origin = entry.value.derivedFromType?.token ?? entry.value.token;
    final isCyclic = cyclic.contains(origin);
    if (isCyclic) cyclicNames.add(entry.key);
    print('  ${entry.key}'
        '  (from: ${entry.value.derivedFromType?.token})'
        '${isCyclic ? '  <-- cyclic' : ''}');
  }

  print('-- projectedInterfaces --');
  for (final entry in g.projectedInterfaces.entries) {
    if (_isNoise(entry.key)) continue;
    final origin = entry.value.derivedFromType?.token ?? entry.value.token;
    final isCyclic = cyclic.contains(origin);
    if (isCyclic) cyclicNames.add(entry.key);
    print('  ${entry.key}'
        '  (from: ${entry.value.derivedFromType?.token})'
        '${isCyclic ? '  <-- cyclic' : ''}');
  }

  return cyclicNames;
}

/// Serializes the cyclic projected types to Dart and prints the classes so we
/// can eyeball the generated fields/nullability for the cycle edges.
void dumpDart(String label, GLParser g) {
  final serializer = DartSerializer(g, importPrefix: 'package:app/models');
  final cyclic = g.cyclicTypeNames;
  print('\n=== $label — Dart ===');
  for (final entry in g.projectedTypes.entries) {
    if (_isNoise(entry.key)) continue;
    final origin = entry.value.derivedFromType?.token ?? entry.value.token;
    if (!cyclic.contains(origin)) continue;
    print(serializer.doSerializeTypeDefinition(entry.value).trim());
    print('');
  }
}

void main() {
  group('cyclic projected type / interface names', () {
    test('self-cycle (Employee)', () {
      final names = dumpProjected('self-cycle', parseAuto(_employee));
      expect(names, isNotEmpty);
    });

    test('two-type cycle (Author / Book)', () {
      final g = parseAuto(_authorBook);
      final names = dumpProjected('two-type', g);
      dumpDart('two-type', g);
      expect(names, isNotEmpty);
    });

    test('three-type cycle (Department / Person / Project)', () {
      final names = dumpProjected('multi-hop', parseAuto(_multiHop));
      expect(names, isNotEmpty);
    });

    test('interface-mediated cycle (Person / Owned / Dog / Cat)', () {
      final names = dumpProjected('interface-cycle', parseAuto(_interfaceCycle));
      expect(names, isNotEmpty);
    });
  });
}
