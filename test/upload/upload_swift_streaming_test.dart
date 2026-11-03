import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_rest_constants.dart';
import 'package:test/test.dart';

void main() {
  group('Swift uploads', () {
    test('GLUpload pulls its bytes lazily and no longer holds a Data', () {
      expect(swiftGLUpload, contains('public init(fileURL: URL'));
      expect(swiftGLUpload, contains('public func readAll() async throws -> Data'));
      expect(swiftGLUpload, isNot(contains('public let data: Data')));
    });

    test('bodies are streamed through a bound stream and reported only for a known length', () {
      expect(swiftGLUpload, contains('uploadTask(withStreamedRequest: request)'));
      expect(swiftGLUpload, contains('Stream.getBoundStreams'));
      expect(swiftGLUpload, contains('let length, length > 0'));
    });

    test('the GraphQL adapter streams a GLMultipartBody', () {
      expect(swiftDefaultGraphLinkURLSessionMultipartAdapter, contains('GLStreamedUpload.send('));
      expect(swiftDefaultGraphLinkURLSessionMultipartAdapter, isNot(contains('session.upload(for: request, from: body)')));
    });

    test('the REST adapter no longer assembles uploads into a Data', () {
      expect(swiftRestUrlSessionAdapter, contains('GLStreamedUpload.send('));
      expect(swiftRestUrlSessionAdapter, isNot(contains('upload.data')));
      expect(swiftRestFile, isNot(contains('func restMultipart')));
    });
  });
}
