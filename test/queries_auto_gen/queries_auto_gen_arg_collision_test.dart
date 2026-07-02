import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

// Propagated field arguments are no longer flat operation parameters — they are
// grouped into a synthesized `<Op>FieldArgs` input object. These tests therefore
// assert on that input's fields (keyed by the bare field name, no `$`) instead
// of on `query.arguments`. The variable-naming / collision-disambiguation logic
// being exercised is unchanged.

const _nonScalarSchema = '''
input OrderInput {
  direction: String
}

interface Node {
  id: String
}

type TypeA implements Node {
  id: String
  search(order: OrderInput!): String
}

type TypeB implements Node {
  id: String
  find(order: OrderInput): String
}

type Query {
  getNode: Node
}
''';

const _scalarSchema = '''
interface Node {
  id: String
}

type TypeA implements Node {
  id: String
  items(page: Int!): String
}

type TypeB implements Node {
  id: String
  fetch(page: Int): String
}

type Query {
  getNode: Node
}
''';

const _unionSchema = '''
union NodeResult = TypeA | TypeB

type Container {
  id: String
  result: NodeResult
}

type TypeA {
  id: String
  items(page: Int): String
}

type TypeB {
  id: String
  fetch(size: Int): String
}

type Query {
  getContainer: Container
}
''';

const _nullabilityMergeSchema = '''
interface Node {
  id: String
}

type TypeA implements Node {
  id: String
  fetch(page: Int): String
}

type TypeB implements Node {
  id: String
  fetch(page: Int!): String
}

type Query {
  getNode: Node
}
''';

const _listNamingSchema = '''
type Container {
  a(ids: [String]): String
  b(ids: [String]!): String
  c(ids: [String!]): String
  d(ids: [String!]!): String
  e(ids: [[String]]): String
  f(ids: [[String]!]): String
  g(ids: [[String!]!]!): String
  h(ids: [[[String]]]): String
}

type Query {
  getContainer: Container
}
''';

GLParser _parse(String schema) {
  final g =
      GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
  g.parse(schema);
  return g;
}

/// The synthesized `<Op>FieldArgs` fields, keyed by bare field name → type token.
Map<String, String> _fieldArgTypes(GLParser g, String inputName) =>
    {for (final f in g.inputs[inputName]!.fields) f.name.token: f.type.token};

void main() {
  test('union: both members register their argument variables in the auto-generated query',
      () {
    final g = _parse(_unionSchema);
    final byName = _fieldArgTypes(g, 'GetContainerFieldArgs');

    expect(byName['itemsPage'], equals('Int'),
        reason: 'TypeA.items(page: Int) should produce itemsPage: Int');
    expect(byName['fetchSize'], equals('Int'),
        reason: 'TypeB.fetch(size: Int) should produce fetchSize: Int');
  });

  test('non-scalar: different fields with same arg name do not collide', () {
    final g = _parse(_nonScalarSchema);
    final byName = _fieldArgTypes(g, 'GetNodeFieldArgs');

    expect(byName['searchOrder'], equals('OrderInput'),
        reason: 'TypeA.search(order: OrderInput!) → searchOrder');
    expect(byName['findOrder'], equals('OrderInput'),
        reason: 'TypeB.find(order: OrderInput) → findOrder');
  });

  test('scalar: different fields with same arg name do not collide', () {
    final g = _parse(_scalarSchema);
    final byName = _fieldArgTypes(g, 'GetNodeFieldArgs');

    expect(byName['itemsPage'], equals('Int'),
        reason: 'TypeA.items(page: Int!) → itemsPage');
    expect(byName['fetchPage'], equals('Int'),
        reason: 'TypeB.fetch(page: Int) → fetchPage');
  });

  test('nullability merge: same field across interface members upgrades to non-nullable',
      () {
    final g = _parse(_nullabilityMergeSchema);
    final input = g.inputs['GetNodeFieldArgs']!;
    final byName = {for (final f in input.fields) f.name.token: f};

    // only one field — merged from Int and Int!
    expect(input.fields.length, equals(1),
        reason: 'same field+arg across members should produce one variable');
    expect(byName['fetchPage'], isNotNull,
        reason: 'field should be named fetchPage');
    expect(byName['fetchPage']!.type.nullable, isFalse,
        reason: 'Int! wins over Int — most restrictive');
  });

  test('list args: variable names use field+arg name regardless of list depth', () {
    final g = _parse(_listNamingSchema);
    final byName = _fieldArgTypes(g, 'GetContainerFieldArgs');

    expect(byName['aIds'], equals('String'), reason: '[String] → aIds');
    expect(byName['bIds'], equals('String'), reason: '[String]! → bIds');
    expect(byName['cIds'], equals('String'), reason: '[String!] → cIds');
    expect(byName['dIds'], equals('String'), reason: '[String!]! → dIds');
    expect(byName['eIds'], equals('String'), reason: '[[String]] → eIds');
    expect(byName['fIds'], equals('String'), reason: '[[String]!] → fIds');
    expect(byName['gIds'], equals('String'), reason: '[[String!]!]! → gIds');
    expect(byName['hIds'], equals('String'), reason: '[[[String]]] → hIds');
  });
}
