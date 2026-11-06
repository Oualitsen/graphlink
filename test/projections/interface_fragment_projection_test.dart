import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

Set<String> _fieldsProjectedFrom(GLParser g, String typeName) {
  final projected = g.projectedTypes.values
      .where((t) => t.token == typeName || t.derivedFromType?.token == typeName)
      .toList();
  expect(projected, hasLength(1), reason: 'expected one projected type derived from $typeName');
  return projected.single.fields.map((f) => f.name.token).toSet();
}

void main() {
  test('a fragment on an interface reaches the fields of every implementer', () {
    const schema = r'''
interface Entity { id: ID! createdBy: String! }
type Article implements Entity { id: ID! createdBy: String! title: String! }
type Comment implements Entity { id: ID! createdBy: String! text: String! }
type Query { entity(id: ID!): Entity }

query q($id: ID!) {
  entity(id: $id) {
    id
    ... on Entity { createdBy }
    ... on Article { title }
  }
}
''';
    final g = GLParser()..parse(schema);

    expect(_fieldsProjectedFrom(g, 'Article'), {'id', 'createdBy', 'title'});
    expect(_fieldsProjectedFrom(g, 'Comment'), {'id', 'createdBy'});
  });

  test('a fragment on an interface the implementer reaches through another interface applies too', () {
    const schema = r'''
interface Node { id: ID! }
interface Entity implements Node { id: ID! createdBy: String! }
type Article implements Entity & Node { id: ID! createdBy: String! title: String! }
type Comment implements Entity & Node { id: ID! createdBy: String! text: String! }
type Query { node(id: ID!): Node }

query q($id: ID!) {
  node(id: $id) {
    ... on Node { id }
    ... on Entity { createdBy }
    ... on Article { title }
  }
}
''';
    final g = GLParser()..parse(schema);

    expect(_fieldsProjectedFrom(g, 'Article'), {'id', 'createdBy', 'title'});
    expect(_fieldsProjectedFrom(g, 'Comment'), {'id', 'createdBy'});
  });

  test('a fragment on an interface inside a union selection reaches the members that implement it', () {
    const schema = r'''
interface Entity { id: ID! createdBy: String! }
type Article implements Entity { id: ID! createdBy: String! title: String! }
type Photo { id: ID! url: String! }
union Hit = Article | Photo
type Query { hit(id: ID!): Hit }

query q($id: ID!) {
  hit(id: $id) {
    ... on Entity { createdBy }
    ... on Photo { url }
  }
}
''';
    final g = GLParser()..parse(schema);

    expect(_fieldsProjectedFrom(g, 'Article'), {'createdBy'});
    expect(_fieldsProjectedFrom(g, 'Photo'), {'url'});
  });

  const unionSchema = r'''
interface Entity { id: ID! createdBy: String! }
type Article implements Entity { id: ID! createdBy: String! title: String! }
type Photo { id: ID! url: String! }
union Hit = Article | Photo
type Query { hit(id: ID!): Hit }

fragment EntityParts on Entity { id createdBy }

query q($id: ID!) {
  hit(id: $id) {
    ...EntityParts
    ... on Photo { url }
  }
}
''';

  test('a named fragment on an interface can be spread in a union selection', () {
    expect(() => GLParser().parse(unionSchema), returnsNormally);
  });

  test('a named fragment on an interface only reaches the members that implement it', () {
    final g = GLParser()..parse(unionSchema);

    expect(_fieldsProjectedFrom(g, 'Article'), {'id', 'createdBy'});
    expect(_fieldsProjectedFrom(g, 'Photo'), {'url'});
  });
}
