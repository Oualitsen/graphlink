import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  directive $glUpload on SCALAR
  scalar Upload $glUpload

  type UploadResult { url: String! }

  type Mutation {
    uploadAvatar(file: Upload!, userId: String!): UploadResult!
    uploadDocuments(files: [Upload!]!, label: String): [UploadResult!]!
  }

  type Query { noop: String }
''';

const _plainSchema = '''
  type Result { id: String! }
  type Mutation { doThing(name: String!): Result! }
  type Query { noop: String }
''';

DartClientSerializer _serializer(String schema,
    {DartHttpAdapter adapter = DartHttpAdapter.dio}) {
  final parser = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)
    ..parse(schema);
  return DartClientSerializer(parser, DartSerializer(parser, generateJsonMethods: true),
      generateAdapters: true, httpAdapter: adapter);
}

void main() {
  group('uploads file', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateUploadsFile());

    test('contains GLUpload', () => expect(out, contains('class GLUpload')));
    test('contains UploadProgressCallback', () => expect(out, contains('typedef UploadProgressCallback')));
    test('contains GLUploadConverter', () => expect(out, contains('typedef GLUploadConverter')));
    test('contains GLMultipartAdapter', () => expect(out, contains('typedef GLMultipartAdapter')));
  });

  group('client file — upload mutations', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateClient(''));

    test('imports graph_link_uploads.dart', () => expect(out, contains("import 'graph_link_uploads.dart'")));
    test('has _defaultUploadConverter', () => expect(out, contains('_defaultUploadConverter')));
    test('upload arg is GLUpload', () => expect(out, contains('required GLUpload file')));
    test('list upload arg is List<GLUpload>', () => expect(out, contains('required List<GLUpload> files')));
    test('has onProgress param', () => expect(out, contains('UploadProgressCallback? onProgress')));
    test('upload variable is null', () => expect(out, contains("'file': null")));
    test('builds multipart parts map', () => expect(out, contains('_uploadAdapter!(parts, onProgress)')));
    test('list upload uses indexed loop', () => expect(out, contains('variables.files.')));
    test('mutations class has upload fields', () {
      expect(out, contains('GLUploadConverter _uploadConverter'));
      expect(out, contains('GLMultipartAdapter? _uploadAdapter'));
    });
    test('withHttp is a factory when uploads present', () {
      expect(out, contains('factory GraphLinkClient.withHttp'));
      expect(out, contains('uploadAdapter: _a.multipartCall'));
    });
  });

  group('adapter files — upload support', () {
    test('dio adapter imports graph_link_uploads.dart', () {
      final out = _serializer(_schema).generateDioAdapterFile();
      expect(out, contains("import 'graph_link_uploads.dart'"));
      expect(out, contains('multipartCall'));
      expect(out, contains('FormData.fromMap'));
    });

    test('http adapter imports graph_link_uploads.dart', () {
      final out = _serializer(_schema, adapter: DartHttpAdapter.http).generateHttpAdapterFile();
      expect(out, contains("import 'graph_link_uploads.dart'"));
      expect(out, contains('multipartCall'));
      expect(out, contains('MultipartRequest'));
    });
  });

  group('no uploads — nothing emitted', () {
    test('client has no upload imports', () {
      final out = _serializer(_plainSchema).generateClient('');
      expect(out, isNot(contains('graph_link_uploads')));
      expect(out, isNot(contains('GLUploadConverter')));
    });

    test('dio adapter has no multipartCall', () {
      final out = _serializer(_plainSchema).generateDioAdapterFile();
      expect(out, isNot(contains('multipartCall')));
    });
  });
}
