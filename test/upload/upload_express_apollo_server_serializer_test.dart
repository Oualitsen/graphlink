import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/serializers/express_apollo_server_serializer.dart';
import 'package:graphlink/src/serializers/typescript_serializer.dart';
import 'package:test/test.dart';

const _uploadSchema = '''
  directive $glUpload on SCALAR
  scalar Upload $glUpload

  type Mutation {
    uploadOneFile(userId: ID!, file: Upload!): Boolean!
  }

  type Query { ping: Boolean! }
''';

const _plainSchema = '''
  type Mutation { doThing(name: String!): Boolean! }
  type Query { ping: Boolean! }
''';

ExpressApolloServerSerializer _serializer(String schema) {
  final parser = GLParser(mode: CodeGenerationMode.server)..parse(schema);
  return ExpressApolloServerSerializer(
    parser,
    TypeScriptSerializer(parser, importPrefix: ''),
    ExpressApolloServerConfig(),
  );
}

void main() {
  group('entry point — uploads present', () {
    late String out;
    setUpAll(() => out = _serializer(_uploadSchema).serializeEntryPoint());

    test('disables Apollo CSRF prevention', () => expect(out, contains('csrfPrevention: false')));
    test('imports graphqlUploadExpress from the .mjs subpath',
        () => expect(out, contains("import graphqlUploadExpress from 'graphql-upload/graphqlUploadExpress.mjs'")));
  });

  group('entry point — no uploads', () {
    late String out;
    setUpAll(() => out = _serializer(_plainSchema).serializeEntryPoint());

    test('does not touch Apollo CSRF prevention', () => expect(out, isNot(contains('csrfPrevention'))));
    test('has no graphql-upload imports', () => expect(out, isNot(contains('graphql-upload'))));
  });

  group('graphql-upload type declarations', () {
    test('declare the .mjs subpaths', () {
      final out = _serializer(_uploadSchema).serializeGraphqlUploadDeclarations();
      expect(out, contains("declare module 'graphql-upload/GraphQLUpload.mjs'"));
      expect(out, contains("declare module 'graphql-upload/graphqlUploadExpress.mjs'"));
    });
  });
}
