import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

void main() {
  group('markUsedFragments', () {
    const schema = '''
type Query {
  getUser(id: ID!): User!
}
type User {
  id: ID!
  name: String!
  posts: [Post!]!
}
type Post {
  id: ID!
  title: String!
}

query GetUser(\$id: ID!) {
  getUser(id: \$id) {
    ...UserFieldsFragment
  }
}

fragment UserFieldsFragment on User {
  id
  name
}
fragment PostFields on Post {
  id
  title
}
fragment UnusedFrag on User {
  id
}
''';

    test('fragment referenced by operation is marked used', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['UserFieldsFragment']!.used, isTrue);
    });

    test('fragment not referenced by any operation is NOT marked used', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['PostFields']!.used, isFalse);
      expect(g.fragments['UnusedFrag']!.used, isFalse);
    });

    test('all fragments are marked used when referenced by operations', () {
      final g = GLParser();
      g.parse(schema);

      // Verify correct boolean values, not just truthiness
      expect(g.fragments['UserFieldsFragment']!.used, equals(true));
      expect(g.fragments['PostFields']!.used, equals(false));
      expect(g.fragments['UnusedFrag']!.used, equals(false));
    });
  });

  group('markUsedFragments — transitive dependencies', () {
    const schema = '''
type Query {
  getUser(id: ID!): User!
}
type User {
  id: ID!
  name: String!
  address: Address!
}
type Address {
  street: String!
  city: String!
}

query GetUser(\$id: ID!) {
  getUser(id: \$id) {
    ...UserWithAddress
  }
}

fragment UserWithAddress on User {
  id
  name
  address {
    ...AddressFragment
  }
}

fragment AddressFragment on Address {
  street
  city
}

fragment UnusedFragment on User {
  id
}
''';

    test('directly referenced fragment is marked used', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['UserWithAddress']!.used, isTrue);
    });

    test('transitively referenced fragment is marked used', () {
      final g = GLParser();
      g.parse(schema);

      // AddressFragment is spread by UserWithAddress which is referenced
      // by GetUser query, so it should be transitively marked used.
      expect(g.fragments['AddressFragment']!.used, isTrue);
    });

    test('unused fragment still not marked used', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['UnusedFragment']!.used, isFalse);
    });
  });

  group('markUsedFragments — no operations', () {
    const schema = '''
type Query {
  getUser(id: ID!): User!
}
type User {
  id: ID!
  name: String!
}

fragment UserFrag on User {
  id
  name
}
fragment AnotherFrag on User {
  id
}
''';

    test('no fragments marked used when schema has no operations', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['UserFrag']!.used, isFalse);
      expect(g.fragments['AnotherFrag']!.used, isFalse);
    });
  });

  group('markUsedFragments — mutation and subscription', () {
    const schema = '''
type Query {
  getUser(id: ID!): User!
}
type Mutation {
  createUser(name: String!): User!
}
type Subscription {
  userCreated: User!
}
type User {
  id: ID!
  name: String!
}

query GetUser(\$id: ID!) {
  getUser(id: \$id) {
    ...QueryFrag
  }
}
mutation CreateUser(\$name: String!) {
  createUser(name: \$name) {
    ...MutationFrag
  }
}
subscription UserCreated {
  userCreated {
    ...SubscriptionFrag
  }
}

fragment QueryFrag on User {
  id
  name
}
fragment MutationFrag on User {
  id
}
fragment SubscriptionFrag on User {
  name
}
fragment UnusedFrag on User {
  id
}
''';

    test('fragments in queries, mutations, and subscriptions are all marked used', () {
      final g = GLParser();
      g.parse(schema);

      expect(g.fragments['QueryFrag']!.used, isTrue);
      expect(g.fragments['MutationFrag']!.used, isTrue);
      expect(g.fragments['SubscriptionFrag']!.used, isTrue);
      expect(g.fragments['UnusedFrag']!.used, isFalse);
    });
  });
}
