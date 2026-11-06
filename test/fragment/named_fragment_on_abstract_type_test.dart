import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

void main() {
  test('a named fragment on a union selects fields of its members through inline fragments', () {
    const schema = '''
union Attachment = Photo | Video
type Photo { id: ID! width: Int! }
type Video { id: ID! seconds: Int! }
type Query { attachment(id: ID!): Attachment }

query fetchAttachment(\$id: ID!) {
  attachment(id: \$id) { ...AttachmentParts }
}

fragment AttachmentParts on Attachment {
  ... on Photo { id width }
  ... on Video { id seconds }
}
''';
    final g = GLParser();
    g.parse(schema);

    final sent = g.queries[const GLOperationKey('fetchAttachment', GLQueryType.query)]!.fragments(g).map((f) => f.token);
    expect(sent, contains('AttachmentParts'));
  });

  test('a named fragment on an interface selects fields only some implementers have', () {
    const schema = '''
interface Entity { id: ID! }
type Article implements Entity { id: ID! title: String! }
type Comment implements Entity { id: ID! text: String! }
type Query { entity(id: ID!): Entity }

query fetchEntity(\$id: ID!) {
  entity(id: \$id) { ...EntityParts }
}

fragment EntityParts on Entity {
  id
  ... on Article { title }
  ... on Comment { text }
}
''';
    final g = GLParser();
    g.parse(schema);

    final sent = g.queries[const GLOperationKey('fetchEntity', GLQueryType.query)]!.fragments(g).map((f) => f.token);
    expect(sent, contains('EntityParts'));
  });
}
