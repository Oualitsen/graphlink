import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const _schema = '''
  type Item { id: ID!  name: String! }

  type Query {
    getItem(id: ID!): Item! @glCache(ttl: 60, tags: ["items"])
    listItems: [Item!]!     @glNoCache
  }

  type Mutation {
    deleteItem(id: ID!): Item! @glCacheInvalidate(tags: ["items"])
  }
''';

void main() {
  group('disableCache', () {
    late GLParser g;

    setUp(() {
      g = GLParser(
        disableCache: true,
        generateAllFieldsFragments: true,
        autoGenerateQueries: true,
      )..parse(_schema);
    });

    test('getItem query has no @glCache directive', () {
      final q = g.queries.values.firstWhere((q) => q.token == 'getItem');
      expect(q.hasDirective(glCache), isFalse);
    });

    test('listItems query has no @glNoCache directive', () {
      final q = g.queries.values.firstWhere((q) => q.token == 'listItems');
      expect(q.hasDirective(glNoCache), isFalse);
    });

    test('deleteItem mutation has no @glCacheInvalidate directive', () {
      final q = g.queries.values
          .firstWhere((q) => q.type == GLQueryType.mutation && q.token == 'deleteItem');
      expect(q.hasDirective(glCacheInvalidate), isFalse);
    });

    test('parser directiveValues contains no cache directives', () {
      final cacheNames = {glCache, glCacheInvalidate, glNoCache};
      final found = g.directiveValues.where((d) => cacheNames.contains(d.token));
      expect(found, isEmpty);
    });
  });
}
