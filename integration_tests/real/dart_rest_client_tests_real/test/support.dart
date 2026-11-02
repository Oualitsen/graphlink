import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'variant.dart';

final serverUrl = 'http://127.0.0.1:${variant.port}';

GraphLinkClient newClient({
  String? baseUrl,
  Future<Map<String, String>?> Function()? headers,
  GraphLinkCacheStore? store,
}) =>
    GraphLinkClient.withHttp(
        url: '${baseUrl ?? serverUrl}/graphql', restBaseUrl: baseUrl ?? serverUrl, headersProvider: headers, store: store);

Future<void> resetServer() async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$serverUrl/_reset'));
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close();
  }
}

String pair(Pair p) => '${p.name}=${p.value}';

extension EchoX on Echo {
  List<String> get queryPairs => query.map(pair).toList();
  List<String> get formPairs => form.map(pair).toList();

  String? header(String name) {
    for (final h in headers) {
      if (h.name == name.toLowerCase()) return h.value;
    }
    return null;
  }

  Part part(String name) => parts.firstWhere((p) => p.name == name);

  List<Part> partsNamed(String name) => parts.where((p) => p.name == name).toList();

  String? queryValue(String name) {
    for (final p in query) {
      if (p.name == name) return p.value;
    }
    return null;
  }

  String? formValue(String name) {
    for (final p in form) {
      if (p.name == name) return p.value;
    }
    return null;
  }

  Object? get bodyJson => jsonDecode(bodyText!);
}

Uint8List pattern(int size) => Uint8List.fromList([for (var i = 0; i < size; i++) i % 251]);

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

GLUpload uploadOf(List<int> bytes, {String? filename, String mimeType = 'application/octet-stream', bool knownLength = true}) =>
    GLUpload(
      stream: Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 16384) bytes.sublist(i, i + 16384 > bytes.length ? bytes.length : i + 16384),
      ]),
      length: knownLength ? bytes.length : null,
      filename: filename,
      mimeType: mimeType,
    );

Future<List<int>> collect(Stream<List<int>> stream) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    out.add(chunk);
  }
  return out.takeBytes();
}
