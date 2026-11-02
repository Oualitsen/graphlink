import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('download', () {
    test('metadata comes from the response headers and bytes are exact', () async {
      final d = await client.queries.blob(size: 100000);
      expect(d.filename, 'blob-100000.bin');
      expect(d.contentType, startsWith('application/octet-stream'));
      expect(d.length, 100000);
      expect(await d.bytes(), pattern(100000));
    });

    test('the body is streamed and a multi-megabyte download arrives intact', () async {
      final d = await client.queries.blob(size: 8 * 1024 * 1024);
      var received = 0;
      var chunks = 0;
      final all = <int>[];
      await for (final chunk in d.stream) {
        received += chunk.length;
        chunks++;
        all.addAll(chunk);
      }
      expect(received, 8 * 1024 * 1024);
      expect(chunks, greaterThan(1));
      expect(sha256Of(all), sha256Of(pattern(8 * 1024 * 1024)));
    });

    test('progress ends at the total', () async {
      final reports = <List<int>>[];
      final d = await client.queries.blob(size: 500000, onReceiveProgress: (r, t) => reports.add([r, t]));
      await d.bytes();
      expect(reports.last, [500000, 500000]);
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
      }
    });

    test('an empty download', () async {
      final d = await client.queries.blob(size: 0);
      expect(await d.bytes(), isEmpty);
    });

    test('a missing resource is a RestError, not a download', () async {
      await expectLater(client.queries.avatar(id: 'p1'), throwsA(isA<RestError>().having((e) => e.status, 'status', 404)));
    });

    test('an upload and the matching download round-trip, with the stored mime type', () async {
      final bytes = pattern(70000);
      await client.mutations.uploadAvatar(id: 'p1', file: uploadOf(bytes, mimeType: 'image/png'));
      final d = await client.queries.avatar(id: 'p1');
      expect(d.contentType, startsWith('image/png'));
      expect(d.filename, 'p1.png');
      expect(await d.bytes(), bytes);
    });

    test('a nullable download is null on 204 and present afterwards', () async {
      expect(await client.queries.avatarOrEmpty(id: 'p1'), isNull);
      await client.mutations.uploadAvatar(id: 'p1', file: uploadOf(pattern(10)));
      expect(await (await client.queries.avatarOrEmpty(id: 'p1'))!.bytes(), pattern(10));
    });

    test('several downloads can be open at once', () async {
      final downloads = await Future.wait([for (var i = 1; i <= 5; i++) client.queries.blob(size: i * 1000)]);
      final bytes = await Future.wait(downloads.map((d) => d.bytes()));
      expect([for (final b in bytes) b.length], [1000, 2000, 3000, 4000, 5000]);
    });
  });
}
