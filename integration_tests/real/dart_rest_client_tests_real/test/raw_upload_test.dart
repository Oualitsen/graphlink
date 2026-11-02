
import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('raw body', () {
    test('is exactly the file bytes with the upload mime type and a known length', () async {
      final bytes = pattern(120000);
      final e = await client.mutations.eRaw(file: uploadOf(bytes, mimeType: 'image/png'));
      expect(e.method, 'PUT');
      expect(e.contentType, startsWith('image/png'));
      expect(e.bodySize, bytes.length);
      expect(e.bodySha256, sha256Of(bytes));
      expect(e.contentLength, bytes.length);
      expect(e.chunked, isFalse);
    });

    test('an upload of unknown length is streamed chunked', () async {
      final bytes = pattern(250000);
      final e = await client.mutations.eRaw(file: uploadOf(bytes, knownLength: false));
      expect(e.chunked, isTrue);
      expect(e.contentLength, isNull);
      expect(e.bodySha256, sha256Of(bytes));
    });

    test('the default mime type is application/octet-stream', () async {
      final e = await client.mutations.eRaw(file: uploadOf(pattern(5)));
      expect(e.contentType, startsWith('application/octet-stream'));
    });

    test('contentType on the operation replaces the upload mime type', () async {
      final e = await client.mutations.eRawType(file: uploadOf(pattern(5), mimeType: 'image/png'));
      expect(e.contentType, startsWith('application/x-custom'));
    });

    test('an empty file is an empty body', () async {
      final e = await client.mutations.eRaw(file: uploadOf(const []));
      expect(e.bodySize, 0);
    });

    test('a null optional file means no body and no Content-Type', () async {
      final e = await client.mutations.eRawOptional();
      expect(e.bodySize, 0);
      expect(e.contentType, isNull);
    });

    test('the filename is not sent', () async {
      final e = await client.mutations.eRaw(file: uploadOf(pattern(5), filename: 'secret-name.bin'));
      expect(e.headers.map((h) => h.value).join('|'), isNot(contains('secret-name')));
      expect(e.path, isNot(contains('secret-name')));
    });

    test('a multi-megabyte upload arrives intact and progress ends at the total', () async {
      final bytes = pattern(6 * 1024 * 1024);
      final reports = <List<int>>[];
      final e = await client.mutations.eRaw(
        file: uploadOf(bytes),
        onProgress: (sent, total) => reports.add([sent, total]),
      );
      expect(e.bodySha256, sha256Of(bytes));
      expect(reports.last, [bytes.length, bytes.length]);
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
      }
    });

    test('progress with an unknown length reports -1 for the total', () async {
      final reports = <List<int>>[];
      await client.mutations.eRaw(file: uploadOf(pattern(40000), knownLength: false), onProgress: (s, t) => reports.add([s, t]));
      expect(reports, isNotEmpty);
      expect(reports.every((r) => r[1] == -1 || r[1] == 40000), isTrue);
      expect(reports.last[0], 40000);
    });

    test('a stream that fails mid-way fails the call and does not hang', () async {
      final failing = GLUpload(
        stream: () async* {
          yield pattern(1000);
          throw StateError('source failed');
        }(),
        length: null,
      );
      await expectLater(client.mutations.eRaw(file: failing).timeout(const Duration(seconds: 10)), throwsA(anything));
      expect((await client.queries.eAccept()).method, 'GET');
    });
  });
}
