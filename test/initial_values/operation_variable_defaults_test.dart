import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_serializer.dart';
import 'package:test/test.dart';

// role is non-null with default to verify no nullable widening.
// status is nullable with default.
// name is non-null without default → required.
const _schema = '''
schema { query: Query mutation: Mutation }

enum Role { ADMIN USER GUEST }
enum Status { ACTIVE INACTIVE }

type User { id: ID! name: String! role: Role! }

type Query {
  listUsers(name: String!, role: Role! = USER, status: Status = ACTIVE, limit: Int = 10): [User]
}

type Mutation {
  createUser(name: String!, role: Role! = USER): User
}
''';

GLParser _dartParser() {
  final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client, autoGenerateQueries: true, generateAllFieldsFragments: true);
  g.parse(_schema);
  return g;
}

GLParser _kotlinParser() {
  final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client, autoGenerateQueries: true, generateAllFieldsFragments: true);
  g.parse(_schema);
  g.parse(kotlinJsonEncoderDecoder, validate: false);
  g.parse(kotlinClientAdapterGql, validate: false);
  return g;
}

GLParser _tsParser() {
  final g = GLParser(identityFields: ['id'], mode: CodeGenerationMode.client, autoGenerateQueries: true, generateAllFieldsFragments: true);
  g.parse(_schema);
  return g;
}

void main() {
  group('Dart — operation variable defaults', () {
    test('generated method has correct required/optional/default params', () {
      final g = _dartParser();
      final s = DartSerializer(g, importPrefix: '');
      final out = DartClientSerializer(g, s).getQueriesClass()?.toFileContent() ?? '';
      print('=== Dart client ===\n$out');

      // non-null, no default → required
      expect(out, contains('required String name'));
      // non-null, has default → not required, no ?
      expect(out, contains('Role role = Role.USER'));
      expect(out, isNot(contains('required Role role')));
      expect(out, isNot(contains('Role? role')));
      // nullable, has default → no required, with literal
      expect(out, contains('Status? status = Status.ACTIVE'));
      // nullable Int with default
      expect(out, contains('int? limit = 10'));
    });
  });

  group('Kotlin — operation variable defaults', () {
    test('generated method has correct param defaults', () {
      final g = _kotlinParser();
      final s = KotlinSerializer(g, importPrefix: 'com.example');
      final out = KotlinClientSerializer(g, s).getQueriesClass()?.toFileContent() ?? '';
      print('=== Kotlin queries ===\n$out');

      // non-null, no default → no default suffix
      expect(out, contains('name: String'));
      expect(out, isNot(contains('name: String = null')));
      // non-null, has default → literal, no ?
      expect(out, contains('role: Role = Role.USER'));
      expect(out, isNot(contains('Role?')));
      // nullable, has default → literal
      expect(out, contains('status: Status? = Status.ACTIVE'));
      expect(out, contains('limit: Int? = 10'));
    });
  });

  group('TypeScript — operation variable defaults', () {
    test('generated method marks defaulted args optional and applies ?? in variables', () {
      final g = _tsParser();
      final s = TypeScriptSerializer(g, importPrefix: '');
      final out = TypeScriptClientSerializer(g, s).getQueriesClass()?.toFileContent() ?? '';
      print('=== TypeScript queries ===\n$out');

      // non-null, no default → not optional
      expect(out, contains('name: string'));
      expect(out, isNot(contains('name?: string')));
      // non-null, has default → optional in args type
      expect(out, contains('role?: Role'));
      // nullable, has default → optional

      expect(out, contains('status?: Status'));
      expect(out, contains('limit?: number'));
      // variables map uses ?? fallback

      expect(out, contains("'role': (args.role != null ? Role.toJson(args.role) : args.role) ?? Role.USER"));
      expect(out, contains("'status': (args.status != null ? Status.toJson(args.status) : args.status) ?? Status.ACTIVE"));
      expect(out, contains("'limit': (args.limit) ?? 10"));
    });
  });
}
