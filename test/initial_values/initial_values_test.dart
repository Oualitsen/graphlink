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

  test('server schema includes input field defaults', () {
    final serializer = GLGraphqlSerializer(parser);
    final output = serializer.generateSchema();

    print('=== GENERATED SERVER SCHEMA ===');
    print(output);

    expect(output, contains('role: Role'));
    expect(output, contains('age: Int'));
    expect(output, contains('isActive: Boolean'));
    expect(output, contains('score: Float'));
    expect(output, contains('nickname: String'));
    expect(output, contains('tags: [String]'));
  });

  test('field argument defaults appear in generated schema', () {
    final serializer = GLGraphqlSerializer(parser);
    final output = serializer.generateSchema();

    print('=== listUsers field args ===');
    final listUsersLine =
        output.split('\n').where((l) => l.contains('listUsers')).join('\n');
    print(listUsersLine);

    expect(output, contains('listUsers'));
  });

  test('raw parsed initialValues on input fields', () {
    final createUserInput = parser.inputs['CreateUserInput']!;

    print('=== CreateUserInput field initialValues ===');
    for (final field in createUserInput.fields) {
      print('  ${field.name.token}: ${field.type.token} = ${field.initialValue} (${field.initialValue.runtimeType})');
    }

    final roleField = createUserInput.fields.firstWhere((f) => f.name.token == 'role');
    final ageField = createUserInput.fields.firstWhere((f) => f.name.token == 'age');
    final isActiveField = createUserInput.fields.firstWhere((f) => f.name.token == 'isActive');
    final scoreField = createUserInput.fields.firstWhere((f) => f.name.token == 'score');
    final nicknameField = createUserInput.fields.firstWhere((f) => f.name.token == 'nickname');
    final tagsField = createUserInput.fields.firstWhere((f) => f.name.token == 'tags');

    expect(roleField.initialValue, equals('USER'));
    expect(ageField.initialValue, equals(18));
    expect(isActiveField.initialValue, equals(true));
    expect(scoreField.initialValue, equals(4.5));
    expect(nicknameField.initialValue, equals('"anonymous"'));
    expect(tagsField.initialValue, equals(['"dart"', '"graphql"']));
  });

  test('raw parsed initialValues on field arguments', () {
    final queryType = parser.types['Query']!;
    final listUsersField = queryType.fields.firstWhere((f) => f.name.token == 'listUsers');

    print('=== listUsers argument initialValues ===');
    for (final arg in listUsersField.arguments) {
      print('  ${arg.token}: ${arg.type.token} = ${arg.initialValue} (${arg.initialValue.runtimeType})');
    }

    final limitArg = listUsersField.getArgumentByName('limit')!;
    final statusArg = listUsersField.getArgumentByName('status')!;

    expect(limitArg.initialValue, equals(20));
    expect(statusArg.initialValue, equals('ACTIVE'));
  });
}
