import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
schema {
  query: Query
  mutation: Mutation
}

enum Role {
  ADMIN
  USER
  GUEST
}

enum Status {
  ACTIVE
  INACTIVE
}

input CreateUserInput {
  name: String!
  role: Role = USER
  age: Int = 18
  isActive: Boolean = true
  score: Float = 4.5
  nickname: String = "anonymous"
  tags: [String] = ["dart", "graphql"]
}

input SearchInput {
  query: String!
  limit: Int = 10
  offset: Int = 0
  status: Status = ACTIVE
}

type User {
  id: ID!
  name: String!
  role: Role!
}

type Query {
  getUser(id: ID!): User
  searchUsers(input: SearchInput!): [User]
  listUsers(limit: Int = 20, status: Status = ACTIVE): [User]
}

type Mutation {
  createUser(input: CreateUserInput!): User
}
''';

void main() {
  late GLParser parser;

  setUp(() {
    parser = GLParser(identityFields: ['id'], mode: CodeGenerationMode.server);
    parser.parse(_schema);
  });

  test('input field defaults appear in generated server schema', () {
    final out = GLGraphqlSerializer(parser).generateSchema();
    print('=== GENERATED SERVER SCHEMA ===\n$out');

    expect(out, contains('role: Role = USER'));
    expect(out, contains('age: Int = 18'));
    expect(out, contains('isActive: Boolean = true'));
    expect(out, contains('score: Float = 4.5'));
    expect(out, contains('nickname: String = "anonymous"'));
  });

  test('field argument defaults appear in generated server schema', () {
    final out = GLGraphqlSerializer(parser).generateSchema();
    expect(out, contains('listUsers(limit: Int = 20, status: Status = ACTIVE)'));
  });

  test('raw parsed initialValues on input fields', () {
    final input = parser.inputs['CreateUserInput']!;
    final role = input.fields.firstWhere((f) => f.name.token == 'role');
    final age = input.fields.firstWhere((f) => f.name.token == 'age');
    final isActive = input.fields.firstWhere((f) => f.name.token == 'isActive');
    final score = input.fields.firstWhere((f) => f.name.token == 'score');
    final nickname = input.fields.firstWhere((f) => f.name.token == 'nickname');
    final tags = input.fields.firstWhere((f) => f.name.token == 'tags');

    expect(role.initialValue, equals('USER'));
    expect(age.initialValue, equals(18));
    expect(isActive.initialValue, equals(true));
    expect(score.initialValue, equals(4.5));
    expect(nickname.initialValue, equals('"anonymous"'));
    expect(tags.initialValue, equals(['"dart"', '"graphql"']));
  });

  test('raw parsed initialValues on field arguments', () {
    final listUsers = parser.types['Query']!.fields
        .firstWhere((f) => f.name.token == 'listUsers');
    expect(listUsers.getArgumentByName('limit')!.defaultValue?.value, equals(20));
    expect(listUsers.getArgumentByName('status')!.defaultValue?.value, equals('ACTIVE'));
  });
}
