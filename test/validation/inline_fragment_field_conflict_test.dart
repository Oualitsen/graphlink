import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const _types = '''
type Photo { id: ID! size: Int! maybe: Int tags: [String!]! owner: User }
type Video { id: ID! size: String! maybe: Int! tags: String owner: Admin }
type Doc { id: ID! size: Int! }
type User { name: String }
type Admin { name: String }
union Media = Photo | Video | Doc
type Query { media: Media }
''';

void expectError(String selection, List<String> mentions) {
  expect(
      () => GLParser().parse('$_types\nquery q { media { $selection } }'),
      throwsA(isA<ParseException>().having((e) => e.toString(), 'message',
          allOf(mentions.map(contains).toList()))));
}

void expectValid(String selection) {
  expect(() => GLParser().parse('$_types\nquery q { media { $selection } }'), returnsNormally);
}

void main() {
  test('the same response name with different scalar types is rejected', () {
    expectError('... on Photo { size } ... on Video { size }', ['size', 'Photo', 'Video', 'alias']);
  });

  test('an alias on one side makes it valid', () {
    expectValid('... on Photo { size } ... on Video { videoSize: size }');
  });

  test('the same type on both members is valid', () {
    expectValid('... on Photo { size } ... on Doc { size }');
  });

  test('different nullability is a conflict', () {
    expectError('... on Photo { maybe } ... on Video { maybe }', ['maybe']);
  });

  test('a list against a non-list is a conflict', () {
    expectError('... on Photo { tags } ... on Video { tags }', ['tags']);
  });

  test('two object types with the same wrapper are valid', () {
    expectValid('... on Photo { owner { name } } ... on Video { owner { name } }');
  });

  test('different fields never conflict', () {
    expectValid('... on Photo { size } ... on Video { id }');
  });

  test('a conflict is also found inside a named fragment', () {
    expect(
        () => GLParser().parse('''
$_types
fragment M on Media { ... on Photo { size } ... on Video { size } }
query q { media { ...M } }
'''),
        throwsA(isA<ParseException>()));
  });

  test('the generated all-fields fragments never conflict-check', () {
    expect(
        () => GLParser(generateAllFieldsFragments: true).parse('$_types\ntype Other { m: Media }'),
        returnsNormally);
  });
}
