import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_uploads.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_websocket_adapter.dart';

const _httpUrl = 'http://localhost:9999/graphql';
const _wsUrl = 'ws://localhost:9999/graphql';
const _uploadUrl = 'http://localhost:9998/graphql';

Future<String> realHttpAdapter(String payload) async {
  final response = await http.post(
    Uri.parse(_httpUrl),
    headers: {'Content-Type': 'application/json'},
    body: payload,
  );
  return response.body;
}

/// Multipart adapter for the upload server on port 9998.
/// Parts map: 'operations' and 'map' are Strings; numbered keys are GLUpload.
Future<String> realMultipartAdapter(
    Map<String, Object> parts, UploadProgressCallback? onProgress) async {
  final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));

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

GraphLinkClient newClient() => GraphLinkClient(
      adapter: realHttpAdapter,
      wsAdapter: DefaultGraphLinkWebSocketAdapter(url: _wsUrl),
    );

GraphLinkClient newUploadClient() => GraphLinkClient(
      adapter: realHttpAdapter,
      uploadAdapter: realMultipartAdapter,
      wsAdapter: DefaultGraphLinkWebSocketAdapter(url: _wsUrl),
    );

DefaultGraphLinkWebSocketAdapter newWsAdapter() =>
    DefaultGraphLinkWebSocketAdapter(url: _wsUrl);
