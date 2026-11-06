import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const schema = r'''
union Attachment = Photo | Video
type Photo { id: ID! width: Int! }
type Video { id: ID! seconds: Int! }

interface Entity { id: ID! }
type Article implements Entity { id: ID! title: String! cover: Attachment attachments: [Attachment!]! }
type Comment implements Entity { id: ID! text: String! }

type Query { feed: [Entity!]! }

fragment AttachmentParts on Attachment {
  ... on Photo { id width }
  ... on Video { id seconds }
}

fragment ArticleParts on Article { title }
''';

Set<String> _sent(String query, String name) {
  final g = GLParser();
  g.parse('$schema\n$query');
  return g.queries[GLOperationKey(name, GLQueryType.query)]!.fragments(g).map((f) => f.token).toSet();
}

void main() {
  test('a spread inside a field of an inline fragment is sent with the operation', () {
    final sent = _sent('''
      query feedWithAttachments {
        feed { id ... on Article { attachments { ...AttachmentParts } } ... on Comment { text } }
      }
    ''', 'feedWithAttachments');
    expect(sent, contains('AttachmentParts'));
  });

  test('a spread directly inside an inline fragment is sent with the operation', () {
    final sent = _sent('''
      query feedWithArticleParts {
        feed { id ... on Article { ...ArticleParts } }
      }
    ''', 'feedWithArticleParts');
    expect(sent, contains('ArticleParts'));
  });

  test('a spread nested in an inline fragment inside another inline fragment is sent', () {
    final sent = _sent('''
      query nested {
        feed { id ... on Article { cover { ... on Photo { id } } attachments { ... on Photo { ...AttachmentParts } } } }
      }
    ''', 'nested');
    expect(sent, contains('AttachmentParts'));
  });

  test('the fragment names of the operation include a spread inside an inline fragment', () {
    final g = GLParser();
    g.parse('$schema\nquery q { feed { id ... on Article { attachments { ...AttachmentParts } } } }');
    expect(g.queries[const GLOperationKey('q', GLQueryType.query)]!.fragmentNames, {'AttachmentParts'});
  });
}
