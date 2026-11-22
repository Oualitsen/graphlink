import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/reserved_words.dart';
import 'package:graphlink/src/naming_convention.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/python/fastapi_ariadne_server_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/serializers/typescript/nest_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
directive @auth(role: String, glClass: String = "Auth", glImport: String = "IMPORT_LINE",
  glOnClient: Boolean = false, glOnServer: Boolean = true, glAnnotation: Boolean = true) on FIELD_DEFINITION

type Book { id: ID! }
type Query { book(id: ID!): Book @auth(role: "admin") }
''';

List<String> _lines(String s) => s.split('\n').map((l) => l.trim()).toList();

void main() {
  test('NestJS puts a user annotation on the resolver method, after the framework decorator', () {
    final g = GLParser(mode: CodeGenerationMode.server)..parse(_schema.replaceAll('IMPORT_LINE', "import { Auth } from './auth'"));
    final serializer = NestApolloServerSerializer(g, TypeScriptSerializer(g, importPrefix: ''), NestApolloServerConfig());
    final resolver = serializer.serializeResolverFiles().values.first;
    expect(_lines(resolver), containsAllInOrder(['@Query("book")', '@Auth({ role: "admin" })', startsWith('async book(')]));
    expect(resolver, contains("import { Auth } from './auth'"));
  });

  test('Ariadne puts a user annotation on the resolver function, after the framework decorator', () {
    final g = GLParser(
      mode: CodeGenerationMode.server,
      naming: NamingConvention.python,
      reservedWords: pythonReservedWords,
      reservedTypeNames: pythonReservedTypeNames,
    )..parse(_schema.replaceAll('IMPORT_LINE', 'from auth import Auth'));
    final serializer = FastapiAriadneServerSerializer(g, PythonSerializer(g, runtimeDir: 'runtime'), FastapiAriadneServerConfig());
    final resolvers = serializer.serializeResolvers().single;
    expect(_lines(resolvers), containsAllInOrder(['@query.field("book")', '@Auth(role="admin")', startsWith('async def query_book(')]));
    expect(resolvers, contains('from auth import Auth'));
  });
}
