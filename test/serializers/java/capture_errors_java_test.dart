import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:test/test.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

GLParser _parser(String schema, {bool captureErrors = false}) {
  final g = GLParser(
    autoGenerateQueries: true,
    generateAllFieldsFragments: true,
    captureErrors: captureErrors,
  );
  g.parse(_preamble + schema);
  return g;
}

JavaClientSerializer _serializer(GLParser g) {
  final java = JavaSerializer(g);
  return JavaClientSerializer(g, java);
}

String _queries(GLParser g) => _serializer(g).getQueriesClass('')?.toFileContent() ?? '';
String _mutations(GLParser g) => _serializer(g).getMutationsClass('')?.toFileContent() ?? '';

String _types(GLParser g) {
  final java = JavaSerializer(g);
  return g.queries.values
      .map((q) => q.getGeneratedTypeDefinition())
      .map((t) => java.doSerializeTypeDefinition(t))
      .join('\n');
}

// Required built-in types for Java parsing
final _preamble = '''
${getClientObjects("Object", "Map<String, Object>")}
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
''';

const _schema = '''
type User {
  id: ID!
  name: String!
}

type Query {
  getUser(id: ID!): User! @glCaptureErrors
  listUsers: [User!]!
}

type Mutation {
  deleteUser(id: ID!): Boolean! @glCaptureErrors
}
''';

void main() {
  group('@glCaptureErrors — Java response class', () {
    late String types;

    setUpAll(() {
      types = _types(_parser(_schema));
    });

    test('has errors field', () {
      expect(types, contains('List<GraphLinkError> errors'));
    });

    test('has hasErrors() method', () {
      expect(types, contains('hasErrors()'));
    });

    test('has getErrors() method', () {
      expect(types, contains('getErrors()'));
    });

    test('fromJson navigates json.get("data")', () {
      expect(types, contains('json.get("data")'));
    });

    test('fromJson reads json.get("errors")', () {
      expect(types, contains('json.get("errors")'));
    });

    test('non-captureErrors response (ListUsersResponse) has no errors field', () {
      final listSection = types.substring(types.indexOf('ListUsersResponse'));
      expect(listSection.substring(0, listSection.indexOf('}')), isNot(contains('GraphLinkError')));
    });
  });

  group('@glCaptureErrors — Java query method', () {
    late String queries;

    setUpAll(() {
      queries = _queries(_parser(_schema));
    });

    test('cache hit wraps with singletonMap("data", ...)', () {
      expect(queries, contains('singletonMap("data"'));
    });

    test('network path does not throw on errors', () {
      expect(queries, contains('getUser'));
      final idx = queries.indexOf('getUser');
      final section = queries.substring(idx);
      final nextMethodIdx = section.indexOf('public ', 10);
      final methodBody = nextMethodIdx > 0 ? section.substring(0, nextMethodIdx) : section;
      expect(methodBody, isNot(contains('throw GraphLinkException')));
    });

    test('listUsers (no @glCaptureErrors) uses parseToObjectAndCache (which throws on errors)', () {
      expect(queries, contains('parseToObjectAndCache('));
    });
  });

  group('@glCaptureErrors — Java mutation method', () {
    late String mutations;

    setUpAll(() {
      mutations = _mutations(_parser(_schema));
    });

    test('does not throw on errors', () {
      expect(mutations, isNot(contains('throw GraphLinkException')));
    });

    test('returns fromJson of full response', () {
      expect(mutations, contains('DeleteUserResponse.fromJson('));
    });
  });

  group('@glCaptureErrors — Java global config', () {
    test('captureErrors: true adds errors field to all response types', () {
      const schema = '''
type User { id: ID! name: String! }
type Query { getUser(id: ID!): User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final types = _types(_parser(schema, captureErrors: true));
      expect(types, contains('List<GraphLinkError> errors'));
      expect(types, contains('hasErrors()'));
    });
  });

  group('@glCaptureErrors — Java validation', () {
    test('rejects on subscription', () {
      const schema = '''
type User { id: ID! }
type Query { getUser(id: ID!): User! }
type Subscription { userAdded: User! @glCaptureErrors }
''';
      expect(() => _parser(schema), throwsA(isA<ParseException>()));
    });

    test('rejects on list return type', () {
      const schema = '''
type User { id: ID! }
type Query { getUsers(id: ID!): [User!]! @glCaptureErrors }
''';
      expect(() => _parser(schema), throwsA(isA<ParseException>()));
    });
  });
}
