import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
$javaJsonEncoderDecorder
$javaClientAdapterNoParamSync
$javaGraphLinkWebSocketAdapter
directive $glUpload on SCALAR
scalar Upload $glUpload
type UploadedFile { id: ID! url: String! }
type Mutation { uploadFile(file: Upload!, filename: String!): UploadedFile! }
type Query { noop: String }
''';

void main() {
  test('the WebClient adapter imports MultipartBodyBuilder from the package Spring ships it in', () {
    final parser = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)..parse(_schema);
    final adapter = JavaClientSerializer(parser, JavaSerializer(parser, importPrefix: ''), flavor: JavaReactiveFlavor.reactor)
        .generateWebClientDefaultClientAdapterFile()
        .toFileContent();

    expect(adapter, contains('org.springframework.http.client.MultipartBodyBuilder'));
    expect(adapter, isNot(contains('org.springframework.util.MultipartBodyBuilder')));
  });
}
