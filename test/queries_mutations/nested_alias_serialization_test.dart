import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Photo { id: ID! size: Int! }
type Video { id: ID! size: String! }
union Media = Photo | Video
type Gallery { cover: Media  title: String }
type Query { media: Media  gallery: Gallery }
''';

String _queryText(String operation) {
  final g = GLParser()..parse('$_schema\n$operation');
  final query = g.queries[const GLOperationKey('q', GLQueryType.query)]!;
  return GLGraphqlSerializer(g).serializeQueryDefinition(query);
}

void main() {
  test('an aliased field keeps its field name', () {
    expect(_queryText('query q { gallery { t: title } }'), contains('t:title'));
  });

  test('an aliased field inside an inline fragment keeps its field name', () {
    final text = _queryText('query q { media { ... on Video { id videoSize: size } } }');
    expect(text, contains('videoSize:size'));
    expect(text, isNot(contains('videoSize:__typename')));
  });

  test('an aliased field nested in a field of an inline fragment keeps its field name', () {
    final text = _queryText('query q { gallery { cover { ... on Photo { p: size } } } }');
    expect(text, contains('p:size'));
  });
}
