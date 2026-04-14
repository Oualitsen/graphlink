import 'package:dart_http_upload_app/generated/client/graph_link_uploads.dart';

import 'generated/client/graph_link_client.dart';
import 'dart:io';
const _endpoint = 'http://localhost:8080/graphql';
const _ws = 'ws://localhost:8080/graphql';

void main() async {
  final client = GraphLinkClient.withHttp(url: _endpoint, wsUrl: _ws);

  // ── Single file upload ─────────────────────────────────────────────────────
  final file = File('pubspec.yaml');
  final bytes = await file.readAsBytes();

  print('Uploading ${file.path} (${bytes.length} bytes)...');

  final upload = GLUpload.fromBytes(
    bytes,
    filename: file.uri.pathSegments.last,
    mimeType: 'text/yaml',
  );

  final result = await client.mutations.uploadFile(
    file: upload,
    filename: 'pubspec.yaml',
    onProgress: (sent, total) => print('  progress: $sent / $total'),
  
  );

  print('Uploaded: ${result.uploadFile.url}');

  // ── Multiple files upload ──────────────────────────────────────────────────
  print('\nUploading multiple files...');

  final files = [
    GLUpload.fromBytes(bytes, filename: 'copy1.yaml', mimeType: 'text/yaml'),
    GLUpload.fromBytes(bytes, filename: 'copy2.yaml', mimeType: 'text/yaml'),
  ];

  final batch = await client.mutations.uploadFiles(
    files: files,
    label: 'batch-test',
    onProgress: (sent, total) => print('  batch progress: $sent / $total'),
  );

  print('Uploaded ${batch.uploadFiles.length} files:');
  for (final f in batch.uploadFiles) {
    print('  - ${f.url}');
  }
}

