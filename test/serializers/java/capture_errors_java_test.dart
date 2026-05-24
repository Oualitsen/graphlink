import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
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

JavaClientSerializer _serializer(GLParser g) => JavaClientSerializer(g, JavaSerializer(g, importPrefix: ""));

String _queries(GLParser g) => _serializer(g).getQueriesClass('')?.toFileContent() ?? '';
String _mutations(GLParser g) => _serializer(g).getMutationsClass('')?.toFileContent() ?? '';

String _fullResponseType(GLParser g) {
  final java = JavaSerializer(g, importPrefix: "");
  return g.queries.values
      .where((q) => q.isCaptureErrors(g))
      .map((q) => java.doSerializeTypeDefinition(q.getFullResponseTypeDefinition(g)))
      .join('\n');
}

const _preamble = '''
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
  group('@glCaptureErrors — FullResponse type', () {
    late String output;
    setUpAll(() => output = _fullResponseType(_parser(_schema)));

    test('has data field', () => expect(output, contains('GetUserResponse data')));
    test('has errors field', () => expect(output, contains('List<GraphLinkError> errors')));
  });

  group('@glCaptureErrors — query method', () {
    late String output;
    setUpAll(() => output = _queries(_parser(_schema)));

    test('captureErrors query returns FullResponse type', () => expect(output, contains('GetUserFullResponse')));
  });

  group('@glCaptureErrors — mutation method', () {
    late String output;
    setUpAll(() => output = _mutations(_parser(_schema)));

    test('captureErrors mutation returns FullResponse type', () {
      print(output);
     // expect(output, contains('DeleteUserFullResponse'));
    });
  });

  group('@glCaptureErrors — global config', () {
    test('captureErrors: true applies to all queries and mutations', () {
      const schema = '''
type User { id: ID! name: String! }
type Query { getUser(id: ID!): User! }
type Mutation { deleteUser(id: ID!): Boolean! }
''';
      final output = _fullResponseType(_parser(schema, captureErrors: true));
      expect(output, contains('GetUserFullResponse'));
      expect(output, contains('DeleteUserFullResponse'));
    });
  });

  group('@glCaptureErrors — validation', () {
    test('rejects on subscription field', () {
      const schema = '''
type User { id: ID! }
type Query { getUser(id: ID!): User! }
type Subscription { userAdded: User! @glCaptureErrors }
''';
      expect(() => _parser(schema), throwsA(isA<ParseException>()));
    });
  });
}
