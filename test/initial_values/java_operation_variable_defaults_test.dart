import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

const _preamble = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
''';

// role is non-null with default — Java method signature is unchanged (no overloading),
// but the method body should contain: if (role == null) role = Role.USER;
const _schema = '''
$_preamble

schema { query: Query mutation: Mutation }

enum Role { ADMIN USER GUEST }

type User { id: ID! name: String! role: Role! }

type Query {
  listUsers(name: String!, role: Role! = USER, limit: Int = 10): [User]
}

type Mutation {
  createUser(name: String!, role: Role! = USER): User
}
''';

GLParser _parser() {
  final g = GLParser(
    identityFields: ['id'],
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
  );
  g.parse(_schema);
  return g;
}

JavaClientSerializer _serializer(GLParser g) =>
    JavaClientSerializer(g, JavaSerializer(g, importPrefix: ''));

void main() {
  group('Java — operation variable defaults', () {
    test('query method body contains null-coalesce for defaulted variables', () {
      final g = _parser();
      final out = _serializer(g).getQueriesClass()?.toFileContent() ?? '';
      print('=== Java queries ===\n$out');

      // method signature is unchanged — all args are still explicit params
      expect(out, contains('Role role'));
      expect(out, contains('Integer limit'));
      // null-coalesce applied before variables map is built
      expect(out, contains('if (role == null)'));
      expect(out, contains('role = Role.USER;'));
      expect(out, contains('if (limit == null)'));
      expect(out, contains('limit = 10;'));
      // required arg has no null-coalesce
      expect(out, isNot(contains('if (name == null)')));
    });

    test('mutation method body contains null-coalesce for defaulted variables', () {
      final g = _parser();
      final out = _serializer(g).getMutationsClass()?.toFileContent() ?? '';
      print('=== Java mutations ===\n$out');

      expect(out, contains('if (role == null)'));
      expect(out, contains('role = Role.USER;'));
      expect(out, isNot(contains('if (name == null)')));
    });
  });
}
