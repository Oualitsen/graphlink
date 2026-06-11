import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_uploads.dart';
import 'real_server_adapter.dart';

GLUpload _makeFile(List<int> bytes, {String name = 'test.png'}) =>
    GLUpload.fromBytes(
      Uint8List.fromList(bytes),
      filename: name,
      mimeType: 'image/png',
    );

void main() {
  late GraphLinkClient client;
  setUp(() => client = newUploadClient());

  // ── uploadOneFile ──────────────────────────────────────────────────────────

  group('uploadOneFile', () {
    test('returns true when file is provided', () async {
      final res = await client.mutations.uploadOneFile(
        userId: 'user-1',
        file: _makeFile([1, 2, 3]),
      );
      expect(res.uploadOneFile, isTrue);
    });

    test('returns true for a different userId', () async {
      final res = await client.mutations.uploadOneFile(
        userId: 'user-42',
        file: _makeFile([10, 20, 30]),
      );
      expect(res.uploadOneFile, isTrue);
    });

    test('returns true for a larger file', () async {
      final res = await client.mutations.uploadOneFile(
        userId: 'user-1',
        file: _makeFile(List.generate(1024, (i) => i % 256), name: 'big.bin'),
      );
      expect(res.uploadOneFile, isTrue);
    });
  });

  // ── uploadFileList ─────────────────────────────────────────────────────────

  group('uploadFileList', () {
    test('returns true for a single file in the list', () async {
      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [
          _makeFile([1, 2, 3])
        ],
      );
      expect(res.uploadFileList, isTrue);
    });

    test('returns true for two files', () async {
      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [
          _makeFile([1, 2, 3]),
          _makeFile([4, 5, 6], name: 'second.png'),
        ],
      );
      expect(res.uploadFileList, isTrue);
    });

    test('returns true for three files', () async {
      final res = await client.mutations.uploadFileList(
        userId: 'user-2',
        files: [
          _makeFile([1]),
          _makeFile([2]),
          _makeFile([3]),
        ],
      );
      expect(res.uploadFileList, isTrue);
    });
  });
}
