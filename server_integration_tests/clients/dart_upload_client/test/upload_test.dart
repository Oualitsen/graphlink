import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_upload_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('ping', () {
    test('returns true', () async {
      final res = await client.queries.ping();
      expect(res.ping, isTrue);
    });
  });

  group('uploadOneFile', () {
    test('returns true for a non-empty file', () async {
      final file = GLUpload.fromBytes(
        utf8.encode('hello world'),
        filename: 'hello.txt',
        mimeType: 'text/plain',
      );

      final res = await client.mutations.uploadOneFile(
        userId: 'user-1',
        file: file,
      );

      expect(res.uploadOneFile, isTrue);
    });

    test('returns false for an empty file', () async {
      final file = GLUpload.fromBytes(
        Uint8List(0),
        filename: 'empty.txt',
        mimeType: 'text/plain',
      );

      final res = await client.mutations.uploadOneFile(
        userId: 'user-1',
        file: file,
      );

      expect(res.uploadOneFile, isFalse);
    });
  });

  group('uploadFileList', () {
    test('returns true for a non-empty list of non-empty files', () async {
      final files = [
        GLUpload.fromBytes(utf8.encode('file one'), filename: 'one.txt', mimeType: 'text/plain'),
        GLUpload.fromBytes(utf8.encode('file two'), filename: 'two.txt', mimeType: 'text/plain'),
      ];

      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: files,
      );

      expect(res.uploadFileList, isTrue);
    });

    test('returns false for an empty list', () async {
      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: const [],
      );

      expect(res.uploadFileList, isFalse);
    });

    test('returns false if any file is empty', () async {
      final files = [
        GLUpload.fromBytes(utf8.encode('file one'), filename: 'one.txt', mimeType: 'text/plain'),
        GLUpload.fromBytes(Uint8List(0), filename: 'empty.txt', mimeType: 'text/plain'),
      ];

      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: files,
      );

      expect(res.uploadFileList, isFalse);
    });
  });
}
