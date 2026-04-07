import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_serializer.dart';
import 'package:graphlink/src/serializers/java_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
  directive $glUpload on SCALAR
  scalar Upload $glUpload

  type UploadedFile { id: ID! url: String! }

  type Mutation {
    uploadFile(file: Upload!, filename: String!): UploadedFile!
    uploadFiles(files: [Upload!]!, label: String): [UploadedFile!]!
    doThing(name: String!): String
  }

  type Query { noop: String }
''';

const _plainSchema = '''
  type Result { id: String! }
  type Mutation { doThing(name: String!): Result! }
  type Query { noop: String }
''';

JavaClientSerializer _serializer(String schema, {JavaJsonCodec codec = JavaJsonCodec.jackson}) {
  final fullSchema = [
    getClientObjects("Java"),
    javaJsonEncoderDecorder,
    javaClientAdapterNoParamSync,
    javaGraphLinkWebSocketAdapter,
    schema,
  ].join();
  final parser = GLParser(autoGenerateQueries: true, generateAllFieldsFragments: true)
    ..parse(fullSchema);
  final javaSerializer = JavaSerializer(parser, generateJsonMethods: true);
  return JavaClientSerializer(parser, javaSerializer, jsonCodec: codec);
}

void main() {
  // ---------------------------------------------------------------------------
  // GLUpload.java
  // ---------------------------------------------------------------------------
  group('GLUpload file', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateGLUploadFile().toFileContent());

    test('contains class GLUpload', () => expect(out, contains('class GLUpload')));
    test('has InputStream field', () => expect(out, contains('InputStream stream')));
    test('has fromFile factory', () => expect(out, contains('fromFile')));
    test('has fromBytes factory', () => expect(out, contains('fromBytes')));
    test('imports InputStream', () => expect(out, contains('import java.io.InputStream')));
  });

  // ---------------------------------------------------------------------------
  // UploadProgressCallback.java
  // ---------------------------------------------------------------------------
  group('UploadProgressCallback file', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateUploadProgressCallbackFile().toFileContent());

    test('is FunctionalInterface', () => expect(out, contains('@FunctionalInterface')));
    test('has onProgress method', () => expect(out, contains('void onProgress(long sent, long total)')));
  });

  // ---------------------------------------------------------------------------
  // GraphLinkMultipartAdapter.java
  // ---------------------------------------------------------------------------
  group('GraphLinkMultipartAdapter file', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateMultipartAdapterFile('com.example.generated').toFileContent());

    test('declares executeMultipart', () => expect(out, contains('executeMultipart')));
    test('takes Map<String, GLUpload>', () => expect(out, contains('Map<String, GLUpload>')));
    test('takes UploadProgressCallback', () => expect(out, contains('UploadProgressCallback onProgress')));
    test('has default no-progress overload', () => expect(out, contains('executeMultipart(operations, mapJson, files, null)')));
    test('imports java.util.Map', () => expect(out, contains('import java.util.Map')));
    test('imports GLUpload', () => expect(out, contains('import com.example.generated.client.GLUpload')));
    test('imports UploadProgressCallback', () => expect(out, contains('import com.example.generated.client.UploadProgressCallback')));
  });

  // ---------------------------------------------------------------------------
  // Mutations class — upload method generation
  // ---------------------------------------------------------------------------
  group('mutations class — upload methods', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateQueriesClassFile(GLQueryType.mutation, 'com.example.generated')!.toFileContent());

    test('has multipartAdapter field', () => expect(out, contains('GraphLinkMultipartAdapter multipartAdapter')));
    test('single upload arg is GLUpload', () => expect(out, contains('GLUpload file')));
    test('list upload arg is List<GLUpload>', () => expect(out, contains('List<GLUpload> files')));
    test('single upload variable is null', () => expect(out, contains('variables.put("file", null)')));
    test('list upload variable is nCopies null list', () => expect(out, contains('Collections.nCopies')));
    test('single upload uses literal index', () => expect(out, contains('_files.put("0", file)')));
    test('list upload uses runtime loop', () => expect(out, contains('for (int _i = 0; _i < files.size(); _i++)')));
    test('calls executeMultipart', () => expect(out, contains('multipartAdapter.executeMultipart')));
    test('overload without progress delegates with null', () => expect(out, contains('uploadFile(file, filename, null)')));
    test('overload with progress throws IOException', () => expect(out, contains('throws java.io.IOException')));
    test('non-upload mutation uses adapter.execute', () => expect(out, contains('adapter.execute')));
  });

  // ---------------------------------------------------------------------------
  // Mutations class — no uploads in plain schema
  // ---------------------------------------------------------------------------
  group('mutations class — no uploads', () {
    late String out;
    setUpAll(() => out = _serializer(_plainSchema).generateQueriesClassFile(GLQueryType.mutation, '')!.toFileContent());

    test('no multipartAdapter field', () => expect(out, isNot(contains('multipartAdapter'))));
    test('no GLUpload', () => expect(out, isNot(contains('GLUpload'))));
    test('uses adapter.execute', () => expect(out, contains('adapter.execute')));
  });

  // ---------------------------------------------------------------------------
  // GraphLinkClient — upload constructor wiring
  // ---------------------------------------------------------------------------
  group('GraphLinkClient — upload constructors', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateClient('com.example.generated').toFileContent());

    test('full constructor takes multipartAdapter', () => expect(out, contains('GraphLinkMultipartAdapter multipartAdapter')));
    test('mutations instantiation passes multipartAdapter', () => expect(out, contains('new GraphLinkMutations(adapter, multipartAdapter')));
    test('intermediate constructor takes DefaultGraphLinkClientAdapter', () => expect(out, contains('DefaultGraphLinkClientAdapter adapter')));
    test('url+encoder constructor delegates to intermediate', () => expect(out, contains('this(new DefaultGraphLinkClientAdapter(url), encoder, decoder)')));
  });

  // ---------------------------------------------------------------------------
  // GraphLinkClient — no uploads, no multipartAdapter
  // ---------------------------------------------------------------------------
  group('GraphLinkClient — no upload constructors', () {
    late String out;
    setUpAll(() => out = _serializer(_plainSchema).generateClient('').toFileContent());

    test('no multipartAdapter in constructor', () => expect(out, isNot(contains('GraphLinkMultipartAdapter'))));
    test('mutations instantiation has no multipartAdapter', () => expect(out, isNot(contains('new GraphLinkMutations(adapter, multipartAdapter'))));
  });

  // ---------------------------------------------------------------------------
  // DefaultGraphLinkClientAdapter — upload variant
  // ---------------------------------------------------------------------------
  group('DefaultGraphLinkClientAdapter — okhttp with upload', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateDefaultClientAdapterFile('okhttp', '').toFileContent());

    test('implements GraphLinkMultipartAdapter', () => expect(out, contains('implements GraphLinkClientAdapter, GraphLinkMultipartAdapter')));
    test('has executeMultipart', () => expect(out, contains('executeMultipart')));
    test('has ProgressRequestBody inner class', () => expect(out, contains('ProgressRequestBody')));
    test('imports okhttp3.MultipartBody', () => expect(out, contains('import okhttp3.MultipartBody')));
  });

  group('DefaultGraphLinkClientAdapter — java11 with upload', () {
    late String out;
    setUpAll(() => out = _serializer(_schema).generateDefaultClientAdapterFile('java11', '').toFileContent());

    test('implements GraphLinkMultipartAdapter', () => expect(out, contains('implements GraphLinkClientAdapter, GraphLinkMultipartAdapter')));
    test('has executeMultipart', () => expect(out, contains('executeMultipart')));
    test('has CountingBodyPublisher inner class', () => expect(out, contains('CountingBodyPublisher')));
    test('has buildMultipartBody helper', () => expect(out, contains('buildMultipartBody')));
  });

  group('DefaultGraphLinkClientAdapter — no upload', () {
    late String out;
    setUpAll(() => out = _serializer(_plainSchema).generateDefaultClientAdapterFile('okhttp', '').toFileContent());

    test('does not implement GraphLinkMultipartAdapter', () => expect(out, isNot(contains('GraphLinkMultipartAdapter'))));
    test('no executeMultipart', () => expect(out, isNot(contains('executeMultipart'))));
  });

  // ---------------------------------------------------------------------------
  // Codec — convenience constructor uses configured codec
  // ---------------------------------------------------------------------------
  group('convenience constructor codec', () {
    test('jackson codec uses JacksonGraphLinkJsonCodec', () {
      final out = _serializer(_plainSchema, codec: JavaJsonCodec.jackson).generateClient('').toFileContent();
      expect(out, contains('new JacksonGraphLinkJsonCodec()'));
    });

    test('gson codec uses GsonGraphLinkJsonCodec', () {
      final out = _serializer(_plainSchema, codec: JavaJsonCodec.gson).generateClient('').toFileContent();
      expect(out, contains('new GsonGraphLinkJsonCodec()'));
    });

    test('none codec omits url-only constructor', () {
      final out = _serializer(_plainSchema, codec: JavaJsonCodec.none).generateClient('').toFileContent();
      expect(out, isNot(contains('this(url,')));
    });
  });
}
