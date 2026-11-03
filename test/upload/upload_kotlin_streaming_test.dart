import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_rest_constants.dart';
import 'package:test/test.dart';

void main() {
  group('Kotlin GraphQL upload adapter', () {
    final out = kotlinDefaultGraphLinkClientAdapterWithUpload(false);

    test('counts progress over the whole body, and only when its size is known', () {
      expect(out, contains('body.contentLength() > 0'));
      expect(out, contains('ProgressRequestBody(body, onProgress)'));
      expect(out, isNot(contains('ProgressRequestBody(fileBody')));
    });

    test('streams each file and never reads it into memory', () {
      expect(out, contains('upload.stream.source().use { sink.writeAll(it) }'));
      expect(out, isNot(contains('readBytes')));
    });
  });

  group('Kotlin REST adapter', () {
    test('streams multipart file parts instead of reading them into memory', () {
      expect(kotlinRestOkHttpAdapter, isNot(contains('readBytes')));
      expect(kotlinRestOkHttpAdapter, contains('rawBody(file, file.mimeType.toMediaTypeOrNull())'));
    });

    test('reports no progress when the total size is unknown', () {
      expect(kotlinRestOkHttpAdapter, contains('callback == null || delegate.contentLength() <= 0'));
    });
  });
}
