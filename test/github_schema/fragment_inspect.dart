import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';

const schema = '''
type Query {
  getUser: User
}

type User {
  id: ID!
  name: String!
  address: Address!
  project: Project!
}

type Address {
  street: String!
  user: User
  district: District!
}

type District {
  name: String!
  region: Region!
}

type Region {
  code: String!
  country: Country!
}

type Country {
  name: String!
  isoCode: String!
}

type Project {
  id: ID!
  title: String!
  owner: User
  metadata: Metadata!
}

type Metadata {
  key: String!
  value: String!
}
''';

void main() {
  final parser = GLParser(generateAllFieldsFragments: true);
  parser.parse(schema);

  final serializer = GLGraphqlSerializer(parser, false);

  print('=== Generated fragments (${parser.fragments.length} total) ===\n');
  for (final frag in parser.fragments.values) {
    print(serializer.serializeFragmentDefinitionBase(frag));
    print('');
  }
}
