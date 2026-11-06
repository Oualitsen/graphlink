import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

String _fieldType(GLParser g, String typeToken, String field) => g
    .projectedTypes[typeToken]!.fields
    .firstWhere((f) => f.name.token == field)
    .type
    .inlineType
    .token;

Iterable<String> _projectedFrom(GLParser g, String typeName) => g.projectedTypes.values
    .where((t) => t.token == typeName || t.derivedFromType?.token == typeName)
    .map((t) => t.token);

void main() {
  const objects = r'''
type Query { post(id: ID!): Post }
type Photo { id: ID! url: String! width: Int! }
type Post { id: ID! title: String! cover: Photo }
''';

  test('a parent whose nested selection is partial does not take the schema type name', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$objects
query partial { post(id: "1") { id title cover { id } } }
''');

    expect(g.projectedTypes.containsKey('Post'), isFalse);
    final parent = _projectedFrom(g, 'Post').single;
    expect(_fieldType(g, parent, 'cover'), isNot('Photo'));
  });

  test('a partial and a full selection of the same parent stay two distinct types', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$objects
query partial { post(id: "1") { id title cover { id } } }
query full { post(id: "1") { id title cover { id url width } } }
''');

    expect(_fieldType(g, 'Post', 'cover'), 'Photo');
    final others = _projectedFrom(g, 'Post').where((t) => t != 'Post');
    expect(others, hasLength(1));
    expect(_fieldType(g, others.single, 'cover'), isNot('Photo'));
  });

  test('a parent whose union field selects only some members does not take the schema type name', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse(r'''
type Query { poly(id: ID!): Holder }
type Photo { id: ID! url: String! width: Int! }
type Clip { id: ID! secs: Int! }
union Media = Photo | Clip
type Holder { id: ID! media: Media }
query partial { poly(id: "1") { id media { ... on Photo { id } } } }
''');

    expect(g.projectedTypes.containsKey('Holder'), isFalse);
    final parent = _projectedFrom(g, 'Holder').single;
    expect(_fieldType(g, parent, 'media'), isNot('Media'));
  });

  test('a parent whose nested selection is complete keeps the schema type name', () {
    final g = GLParser(generateAllFieldsFragments: true)
      ..parse('''
$objects
query full { post(id: "1") { id title cover { id url width } } }
''');

    expect(_fieldType(g, 'Post', 'cover'), 'Photo');
  });
}
