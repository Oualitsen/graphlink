import 'package:test/test.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  const schema = '''
type Query {
  simple(id: ID!): Item
  heavy(id: ID!): Deep
}

type Item {
  id: ID!
  name: String
}

type Deep {
  id: ID!
  child(a: String, b: String, c: String, d: String): Leaf
}

type Leaf {
  id: ID!
  value: String
}
''';

  // `heavy` auto-generates a query with 4 propagated args (a, b, c, d from
  // Deep.child) — above the cap of 3. `simple` has none — always kept.

  test('query above argument limit is pruned and recorded in skippedAutoQueries', () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      autoQueryArgumentLimit: 3,
    );
    g.parse(schema);

    expect(g.queries.containsKey(GLOperationKey('simple', GLQueryType.query)), isTrue,
        reason: 'simple has no propagated args and must be kept');
    expect(g.queries.containsKey(GLOperationKey('heavy', GLQueryType.query)), isFalse,
        reason: 'heavy has 4 propagated args and must be pruned');
    expect(g.inputs.containsKey('HeavyFieldArgs'), isFalse,
        reason: 'synthesized input for pruned query must also be removed');

    expect(g.skippedAutoQueries, hasLength(1));
    final skipped = g.skippedAutoQueries.first;
    expect(skipped.name, 'heavy');
    expect(skipped.type, GLQueryType.query);
    expect(skipped.count, 4);
    expect(skipped.cap, 3);
  });

  test('null limit disables pruning — all queries are kept', () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      autoQueryArgumentLimit: null,
    );
    g.parse(schema);

    expect(g.queries.containsKey(GLOperationKey('heavy', GLQueryType.query)), isTrue);
    expect(g.skippedAutoQueries, isEmpty);
  });

  test('query exactly at the limit is kept', () {
    final g = GLParser(
      generateAllFieldsFragments: true,
      autoGenerateQueries: true,
      autoQueryArgumentLimit: 4,
    );
    g.parse(schema);

    expect(g.queries.containsKey(GLOperationKey('heavy', GLQueryType.query)), isTrue,
        reason: '4 propagated args with cap 4 must not be pruned');
    expect(g.skippedAutoQueries, isEmpty);
  });
}
