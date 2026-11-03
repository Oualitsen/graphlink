import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_rest_constants.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScript uploads', () {
    test('the uploads file streams multipart bodies and counts progress only for a known total', () {
      expect(tsUploadsFile, contains('export function glMultipartBody('));
      expect(tsUploadsFile, contains("total === undefined || total === 0"));
    });

    test('the GraphQL fetch adapter no longer puts uploads into FormData itself', () {
      expect(tsMultipartFetchAdapter, contains('glFetchMultipart(list, onProgress)'));
      expect(tsMultipartFetchAdapter, isNot(contains('new FormData()')));
    });

    test('REST never reads an upload or a multipart body into memory', () {
      expect(tsRestFetchAdapter, contains('glFetchMultipart(body.parts, request.onSendProgress)'));
      expect(tsRestFetchAdapter, isNot(contains('restMultipart')));
      expect(tsRestAxiosAdapter, isNot(contains('restReadAll(body.upload.stream)')));
      expect(tsRestAxiosAdapter, isNot(contains('restMultipart')));
    });
  });

  group('Python uploads', () {
    test('the uploads file owns the shared multipart stream and counts progress only for a known total', () {
      expect(pythonUploads, contains('def gl_multipart_stream('));
      expect(pythonUploads, contains('if on_progress is not None and total:'));
    });

    test('the REST adapter uses the shared helpers', () {
      expect(pythonRestHttpxAdapter, contains('gl_multipart_stream(body.parts, request.on_send_progress)'));
      expect(pythonRestFile, isNot(contains('def rest_multipart_stream')));
    });
  });
}
