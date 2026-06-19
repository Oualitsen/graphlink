import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

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

void main() {
  test('union: both members register their argument variables in the auto-generated query',
      () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(_unionSchema);

    final query = g.queries['getContainer']!;
    final argsByName = {for (var a in query.arguments) a.token: a.type.token};

    expect(argsByName[r'$itemsPage'], equals('Int'),
        reason: 'TypeA.items(page: Int) should produce \$itemsPage: Int');
    expect(argsByName[r'$fetchSize'], equals('Int'),
        reason: 'TypeB.fetch(size: Int) should produce \$fetchSize: Int');
  });

  test('non-scalar: different fields with same arg name do not collide', () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(_nonScalarSchema);

    final query = g.queries['getNode']!;
    final argsByName = {for (var a in query.arguments) a.token: a.type.token};

    expect(argsByName[r'$searchOrder'], equals('OrderInput'),
        reason: 'TypeA.search(order: OrderInput!) → \$searchOrder');
    expect(argsByName[r'$findOrder'], equals('OrderInput'),
        reason: 'TypeB.find(order: OrderInput) → \$findOrder');
  });

  test('scalar: different fields with same arg name do not collide', () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(_scalarSchema);

    final query = g.queries['getNode']!;
    final argsByName = {for (var a in query.arguments) a.token: a.type.token};

    expect(argsByName[r'$itemsPage'], equals('Int'),
        reason: 'TypeA.items(page: Int!) → \$itemsPage');
    expect(argsByName[r'$fetchPage'], equals('Int'),
        reason: 'TypeB.fetch(page: Int) → \$fetchPage');
  });

  test('nullability merge: same field across interface members upgrades to non-nullable',
      () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(_nullabilityMergeSchema);

    final query = g.queries['getNode']!;
    final args = {for (var a in query.arguments) a.token: a};

    // only one variable — merged from Int and Int!
    expect(args.length, equals(1),
        reason: 'same field+arg across members should produce one variable');
    expect(args[r'$fetchPage'], isNotNull,
        reason: 'variable should be named \$fetchPage');
    expect(args[r'$fetchPage']!.type.nullable, isFalse,
        reason: 'Int! wins over Int — most restrictive');
  });

  test('list args: variable names use field+arg name regardless of list depth', () {
    final g = GLParser(
        generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(_listNamingSchema);

    final query = g.queries['getContainer']!;
    final argsByName = {for (var a in query.arguments) a.token: a.type.token};

    expect(argsByName[r'$aIds'], equals('String'), reason: '[String] → \$aIds');
    expect(argsByName[r'$bIds'], equals('String'), reason: '[String]! → \$bIds');
    expect(argsByName[r'$cIds'], equals('String'), reason: '[String!] → \$cIds');
    expect(argsByName[r'$dIds'], equals('String'), reason: '[String!]! → \$dIds');
    expect(argsByName[r'$eIds'], equals('String'), reason: '[[String]] → \$eIds');
    expect(argsByName[r'$fIds'], equals('String'), reason: '[[String]!] → \$fIds');
    expect(argsByName[r'$gIds'], equals('String'), reason: '[[String!]!]! → \$gIds');
    expect(argsByName[r'$hIds'], equals('String'), reason: '[[[String]]] → \$hIds');
  });
}
