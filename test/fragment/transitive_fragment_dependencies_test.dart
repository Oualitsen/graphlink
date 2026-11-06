import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:test/test.dart';

const schema = '''
union Attachment = Photo | Video
type Photo { id: ID! width: Int! }
type Video { id: ID! seconds: Int! }

interface Entity { id: ID! }
type Article implements Entity { id: ID! title: String! cover: Attachment }
type Comment implements Entity { id: ID! text: String! }

type Query {
  feed: [Entity!]!
  article(id: ID!): Article!
  attachment(id: ID!): Attachment
}
''';

void main() {
  late GLParser g;

  setUp(() {
    g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
    g.parse(schema);
  });

  for (final name in ['feed', 'article', 'attachment']) {
    test('$name sends every fragment its fragments spread', () {
      final operation = g.queries[GLOperationKey(name, GLQueryType.query)]!;
      final sent = operation.fragments(g).map((f) => f.token).toSet();
      for (final fragment in operation.fragments(g)) {
        final missing = fragment.block.getDependecies().difference(sent);
        expect(missing, isEmpty, reason: '${fragment.token} spreads $missing, which $name does not send (sent: $sent)');
      }
    });
  }
}
