import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';
import 'package:graphlink/src/serializers/dart/dart_serializer.dart';
import 'package:test/test.dart';

const _schema = '''
type Product { id: ID! name: String }
type Query { p: Product @glRest(path: "/p") }
''';

GLClassModel _runtime() {
  final g = GLParser()..parse(_schema);
  return DartClientSerializer(g, DartSerializer(g, importPrefix: '')).generateRestFile();
}

void main() {
  late String content;
  setUp(() => content = _runtime().toFileContent());

  test('declares the adapter function type', () {
    expect(content, contains('typedef GLRestAdapter = Future<RestResponse> Function(RestRequest request);'));
  });

  test('declares request, response, error and body types', () {
    for (final name in [
      'class RestRequest',
      'class RestResponse',
      'class RestError',
      'class RestPart',
      'class RestJsonBody',
      'class RestFormBody',
      'class RestMultipartBody',
      'class RestRawBody',
    ]) {
      expect(content, contains(name));
    }
  });

  test('response buffers through bytes, text and json', () {
    expect(content, contains('Future<Uint8List> bytes()'));
    expect(content, contains('Future<String> text()'));
    expect(content, contains('Future<Object?> json()'));
  });

  test('error carries status, headers and body text', () {
    expect(content, contains('final int status;'));
    expect(content, contains('final String body;'));
  });

  test('imports the uploads file', () {
    expect(content, contains("import 'graph_link_uploads.dart';"));
  });
}
