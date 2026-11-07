import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  interface Entity { id: ID! createdBy: String! }
  type Article implements Entity { id: ID! createdBy: String! title: String! }
  type Comment implements Entity { id: ID! createdBy: String! text: String! }
  type Query { feed: [Entity!]! }

  fragment EntityBits on Entity { id createdBy }

  query spreadAndInline { feed { ...EntityBits ... on Article { title } } }
  query inlineOnly { feed { id ... on Article { title } } }
  query plain { feed { id createdBy } }
''';

String _text(String name) {
  final g = GLParser()..parse(_schema);
  final def = g.queries.values.firstWhere((q) => q.token == name);
  return GLGraphqlSerializer(g, false).serializeQueryDefinition(def);
}

void main() {
  test('a fragment spread next to an inline fragment still gets a __typename of its own', () {
    expect(_text('spreadAndInline'), matches(RegExp(r'feed\{[^{}]*__typename[^{}]*\.\.\. on Article')));
  });

  test('a plain field next to an inline fragment too', () {
    expect(_text('inlineOnly'), matches(RegExp(r'feed\{[^{}]*__typename[^{}]*\.\.\. on Article')));
  });

  test('a selection without inline fragments is left alone', () {
    expect(_text('plain'), isNot(contains('__typename')));
  });
}
