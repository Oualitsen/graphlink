import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_uploads.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late MockMultipartAdapter multipart;
  late GraphLinkClient client;

  GLUpload makeFile(List<int> bytes, {String? filename}) => GLUpload.fromBytes(
        Uint8List.fromList(bytes),
        filename: filename,
        mimeType: 'image/png',
      );

  setUp(() {
    adapter = MockAdapter();
    multipart = MockMultipartAdapter();
    client = GraphLinkClient(
      adapter: adapter.call,
      uploadAdapter: multipart.call,
      wsAdapter: MockWebSocketAdapter(),
    );
  });

  // ── uploadOneFile ─────────────────────────────────────────────────────────

  group('uploadOneFile — single file', () {
    setUp(() {
      multipart.registerData('uploadOneFile', {'uploadOneFile': kUserAliceJson});
    });

    test('response deserialized: id correct', () async {
      final res = await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      expect(res.uploadOneFile.id, equals('user-1'));
    });

    test('response deserialized: name correct', () async {
      final res = await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      expect(res.uploadOneFile.name, equals('Alice Smith'));
    });

    test('multipart adapter is called once', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      expect(multipart.callCount, equals(1));
    });

    test('operations contains correct userId variable', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-42', file: makeFile([1, 2, 3]));
      final ops = jsonDecode(multipart.lastCall!['operations'] as String)
          as Map<String, dynamic>;
      expect(ops['variables']['userId'], equals('user-42'));
    });

    test('file variable is null in operations (multipart spec)', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      final ops = jsonDecode(multipart.lastCall!['operations'] as String)
          as Map<String, dynamic>;
      expect(ops['variables']['file'], isNull);
    });

    test('map slot 0 points to variables.file', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      final map = jsonDecode(multipart.lastCall!['map'] as String)
          as Map<String, dynamic>;
      expect(map['0'], equals(['variables.file']));
    });

    test('file part is present under slot key "0"', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      expect(multipart.lastCall!.containsKey('0'), isTrue);
    });

    test('regular JSON adapter is not called', () async {
      await client.mutations
          .uploadOneFile(userId: 'user-1', file: makeFile([1, 2, 3]));
      expect(adapter.callCount, equals(0));
    });
  });

  // ── uploadFileList ────────────────────────────────────────────────────────

  group('uploadFileList — list of files', () {
    setUp(() {
      multipart.registerData(
          'uploadFileList', {'uploadFileList': kUserAliceJson});
    });

    test('response deserialized: id correct', () async {
      final res = await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
      );
      expect(res.uploadFileList.id, equals('user-1'));
    });

    test('files variables are all null in operations (multipart spec)', () async {
      await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
      );
      final ops = jsonDecode(multipart.lastCall!['operations'] as String)
          as Map<String, dynamic>;
      expect(ops['variables']['files'], equals([null, null]));
    });

    test('map slot 0 points to variables.files.0', () async {
      await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
      );
      final map = jsonDecode(multipart.lastCall!['map'] as String)
          as Map<String, dynamic>;
      expect(map['0'], equals(['variables.files.0']));
    });

    test('map slot 1 points to variables.files.1', () async {
      await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
      );
      final map = jsonDecode(multipart.lastCall!['map'] as String)
          as Map<String, dynamic>;
      expect(map['1'], equals(['variables.files.1']));
    });

    test('both file parts present in parts map', () async {
      await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3]), makeFile([4, 5, 6])],
      );
      expect(multipart.lastCall!.containsKey('0'), isTrue);
      expect(multipart.lastCall!.containsKey('1'), isTrue);
    });

    test('single-file list produces one slot', () async {
      await client.mutations.uploadFileList(
        userId: 'user-1',
        files: [makeFile([1, 2, 3])],
      );
      final map = jsonDecode(multipart.lastCall!['map'] as String)
          as Map<String, dynamic>;
      expect(map.length, equals(1));
    });
  });
}
