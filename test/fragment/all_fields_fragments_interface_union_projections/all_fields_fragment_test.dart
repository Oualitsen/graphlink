import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  test("All field fragments on interface/union as a projection", () {
    final text = File(
            "test/fragment/all_fields_fragments_interface_union_projections/all_fields_fragment_test.graphql")
        .readAsStringSync();
    var g = GLParser(generateAllFieldsFragments: true);

    g.parse(text);

    expect(g.fragments.keys,
        containsAll(["_all_fields_Animal", "_all_fields_Animal2"]));
    var allFieldAnimal = g.fragments["_all_fields_Animal"]!;
    expect(allFieldAnimal.dependecies.map((d) => d.token).toList(),
        containsAll(["_all_fields_Cat", "_all_fields_Dog"]));

    var allFieldAnimal2 = g.fragments["_all_fields_Animal2"]!;
    expect(allFieldAnimal2.dependecies.map((d) => d.token).toList(),
        containsAll(["_all_fields_Cat", "_all_fields_Dog"]));
  });

  group('fragments sent with an operation', () {
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
}
''';

    late GLParser g;

    Set<String> sentWith(String operation) =>
        g.queries[GLOperationKey(operation, GLQueryType.query)]!.fragments(g).map((f) => f.token).toSet();

    setUp(() {
      g = GLParser(generateAllFieldsFragments: true, autoGenerateQueries: true);
      g.parse(schema);
    });

    test('an interface fragment brings the union fragments of its implementers', () {
      expect(sentWith('feed'), {
        '_all_fields_Entity',
        '_all_fields_Article',
        '_all_fields_Comment',
        '_all_fields_Attachment',
        '_all_fields_Photo',
        '_all_fields_Video',
      });
    });

    test('a type fragment brings the members of the union it spreads', () {
      expect(sentWith('article'), {
        '_all_fields_Article',
        '_all_fields_Attachment',
        '_all_fields_Photo',
        '_all_fields_Video',
      });
    });

    test('dependecies stays direct while transitiveDependecies follows every hop', () {
      final entity = g.fragments['_all_fields_Entity']!;
      expect(entity.dependecies.map((d) => d.token), {'_all_fields_Article', '_all_fields_Comment'});
      expect(entity.transitiveDependecies.map((d) => d.token), {
        '_all_fields_Article',
        '_all_fields_Comment',
        '_all_fields_Attachment',
        '_all_fields_Photo',
        '_all_fields_Video',
      });
    });
  });
}
