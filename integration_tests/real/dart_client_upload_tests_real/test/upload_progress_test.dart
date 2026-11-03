import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:graphlink_dart_upload_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'recording_server.dart';

Uint8List pattern(int size) => Uint8List.fromList(List.generate(size, (i) => (i * 31 + 7) % 251));

String shaOf(List<int> bytes) => sha256.convert(bytes).toString();

GLUpload fileOf(Uint8List bytes, {String name = 'big.bin', bool knownLength = true, int chunk = 64 * 1024}) => GLUpload(
      stream: Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += chunk) Uint8List.sublistView(bytes, i, (i + chunk).clamp(0, bytes.length)),
      ]),
      length: knownLength ? bytes.length : null,
      filename: name,
      mimeType: 'application/octet-stream',
    );

void main() {
  late RecordingServer server;
  late GraphLinkClient client;

  setUp(() async {
    server = await RecordingServer.start();
    client = GraphLinkClient.withHttp(url: server.url);
  });
  tearDown(() => server.close());

  group('uploadOneFile without progress', () {
    test('a 6 MB file arrives intact', () async {
      final bytes = pattern(6 * 1024 * 1024);
      final res = await client.mutations.uploadOneFile(userId: 'u1', file: fileOf(bytes));
      expect(res.uploadOneFile, isTrue);
      final sent = server.requests.single;
      expect(sent.part('0').sha256Hex, shaOf(bytes));
      expect(sent.part('0').filename, 'big.bin');
      expect(sent.part('operations').text, contains('"userId":"u1"'));
    });

    test('a file of unknown length arrives intact, sent chunked', () async {
      final bytes = pattern(300000);
      await client.mutations.uploadOneFile(userId: 'u1', file: fileOf(bytes, knownLength: false));
      final sent = server.requests.single;
      expect(sent.part('0').sha256Hex, shaOf(bytes));
      expect(sent.chunked, isTrue);
    });

    test('a file of known length is sent with a content-length', () async {
      final bytes = pattern(300000);
      await client.mutations.uploadOneFile(userId: 'u1', file: fileOf(bytes));
      final sent = server.requests.single;
      expect(sent.chunked, isFalse);
      expect(sent.contentLength, greaterThan(bytes.length));
    });
  });

  group('uploadOneFile with progress', () {
    test('a 6 MB file arrives intact', () async {
      final bytes = pattern(6 * 1024 * 1024);
      await client.mutations.uploadOneFile(userId: 'u1', file: fileOf(bytes), onProgress: (_, __) {});
      expect(server.requests.single.part('0').sha256Hex, shaOf(bytes));
    });

    test('reports increasing byte counts that end at the total', () async {
      final bytes = pattern(6 * 1024 * 1024);
      final reports = <List<int>>[];
      await client.mutations.uploadOneFile(
        userId: 'u1',
        file: fileOf(bytes),
        onProgress: (sent, total) => reports.add([sent, total]),
      );
      expect(reports.length, greaterThan(10));
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
      }
      expect(reports.last[0], reports.last[1]);
      expect(reports.last[1], greaterThan(bytes.length));
      expect(reports.last[1], server.requests.single.contentLength);
    });

    test('the file is not read in full before the first progress report', () async {
      final bytes = pattern(6 * 1024 * 1024);
      const chunk = 256 * 1024;
      var pulled = 0;
      var pulledAtFirstReport = -1;
      Stream<List<int>> slowSource() async* {
        for (var i = 0; i < bytes.length; i += chunk) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          final part = Uint8List.sublistView(bytes, i, (i + chunk).clamp(0, bytes.length));
          pulled += part.length;
          yield part;
        }
      }

      final source = slowSource();
      await client.mutations.uploadOneFile(
        userId: 'u1',
        file: GLUpload(stream: source, length: bytes.length, filename: 'big.bin'),
        onProgress: (_, __) {
          if (pulledAtFirstReport < 0) pulledAtFirstReport = pulled;
        },
      );
      expect(pulledAtFirstReport, lessThan(bytes.length), reason: 'progress path buffered the whole file first');
    });

    test('a file of unknown length arrives intact and fires no progress', () async {
      final bytes = pattern(300000);
      var calls = 0;
      await client.mutations.uploadOneFile(
        userId: 'u1',
        file: fileOf(bytes, knownLength: false),
        onProgress: (_, __) => calls++,
      );
      final sent = server.requests.single;
      expect(sent.part('0').sha256Hex, shaOf(bytes));
      expect(sent.chunked, isTrue);
      expect(calls, 0);
    });
  });

  group('uploadFileList', () {
    test('two files arrive intact in slot order, with progress', () async {
      final a = pattern(1200000);
      final b = Uint8List.fromList(pattern(900000).reversed.toList());
      final reports = <List<int>>[];
      final res = await client.mutations.uploadFileList(
        userId: 'u1',
        files: [fileOf(a, name: 'a.bin'), fileOf(b, name: 'b.bin')],
        onProgress: (sent, total) => reports.add([sent, total]),
      );
      expect(res.uploadFileList, isTrue);
      final sent = server.requests.single;
      expect(sent.part('0').sha256Hex, shaOf(a));
      expect(sent.part('0').filename, 'a.bin');
      expect(sent.part('1').sha256Hex, shaOf(b));
      expect(sent.part('1').filename, 'b.bin');
      expect(reports.last[0], reports.last[1]);
    });
  });
}
