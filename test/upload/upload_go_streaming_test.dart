import 'package:graphlink/src/serializers/client_serializers/go/go_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_rest_constants.dart';
import 'package:test/test.dart';

void main() {
  group('Go uploads', () {
    test('multipart parts stream through an io.MultiReader and never carry a nameless file', () {
      expect(goUploads, contains('io.MultiReader(readers...)'));
      expect(goUploads, contains('filename = part.Name'));
    });

    test('progress is reported only when the total size is known', () {
      expect(goRestHttpAdapter, contains('onProgress == nil || total <= 0'));
    });
  });
}
