import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:http/http.dart' as http;

const _defaultPort = 9999;
const _uploadPort = 9998;

String _httpUrl(int port) => 'http://localhost:$port/graphql';
String _wsUrl(int port) => 'ws://localhost:$port/graphql';

Future<String> Function(String) httpAdapterForPort(int port) =>
    (String payload) async {
      final response = await http.post(
        Uri.parse(_httpUrl(port)),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      return response.body;
    };

Future<String> realHttpAdapter(String payload) =>
    httpAdapterForPort(_defaultPort)(payload);

/// Multipart adapter for the upload server on port 9998.
/// Parts map: 'operations' and 'map' are Strings; numbered keys are GLUpload.
Future<String> realMultipartAdapter(
    Map<String, Object> parts, UploadProgressCallback? onProgress) async {
  final request =
      http.MultipartRequest('POST', Uri.parse(_httpUrl(_uploadPort)));

  for (final entry in parts.entries) {
    final value = entry.value;
    if (value is String) {
      request.fields[entry.key] = value;
    } else if (value is GLUpload) {
      final bytes = await value.stream.fold<List<int>>(
        [],
        (acc, chunk) => acc..addAll(chunk),
      );
      request.files.add(http.MultipartFile.fromBytes(
        entry.key,
        bytes,
        filename: value.filename ?? 'upload',
      ));
    }
  }

  final streamed = await request.send();
  return await streamed.stream.transform(utf8.decoder).join();
}

GraphLinkClient newClient({int port = _defaultPort}) => GraphLinkClient(
      adapter: httpAdapterForPort(port),
      wsAdapter: DefaultGraphLinkWebSocketAdapter(url: _wsUrl(port)),
    );

GraphLinkClient newUploadClient() => GraphLinkClient(
      adapter: realHttpAdapter,
      uploadAdapter: realMultipartAdapter,
      wsAdapter: DefaultGraphLinkWebSocketAdapter(url: _wsUrl(_defaultPort)),
    );

DefaultGraphLinkWebSocketAdapter newWsAdapter({int port = _defaultPort}) =>
    DefaultGraphLinkWebSocketAdapter(url: _wsUrl(port), reconnect: true);

/// Adapter with maxReconnectAttempts=null (retry forever) and a reduced
/// maxReconnectDelay so integration tests run fast.
DefaultGraphLinkWebSocketAdapter newWsAdapterNeverStop(
        {int port = _defaultPort}) =>
    DefaultGraphLinkWebSocketAdapter(
      url: _wsUrl(port),
      reconnect: true,
      maxReconnectAttempts: null,
      maxReconnectDelay: const Duration(seconds: 2),
    );

// ---------------------------------------------------------------------------
// Server lifecycle utilities
// ---------------------------------------------------------------------------

String _jarPath() =>
    '${Directory.current.path}/../spring_server/build/libs/graphlink-test-server-0.0.1.jar';

/// Kills any process listening on [port].
Future<void> killPort(int port) async {
  await Process.run('bash', [
    '-c',
    'lsof -ti :$port -sTCP:LISTEN | xargs kill -9 2>/dev/null || true'
  ]);
  await Future.delayed(const Duration(milliseconds: 500));
}

/// Kills any process on [port], starts the test-server JAR on that port,
/// and waits until the port accepts TCP connections.
Future<void> startServer(int port) async {
  print("Killing process with port $port");
  await killPort(port);
  print("starting spring server with port ${port}");
  final process = await Process.start('java', [
    '-jar',
    _jarPath(),
    '--server.port=$port',
    '--management.server.port=-1',
  ]);
  unawaited(process.stdout.drain());
  unawaited(process.stderr.drain());
  print("waiting for port ${port}");
  await _waitForPort(port);
}

Future<void> _waitForPort(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect('localhost', port,
          timeout: const Duration(seconds: 1));
      await socket.close();
      return;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
  throw TimeoutException('Server on port $port did not start within 20 s');
}
