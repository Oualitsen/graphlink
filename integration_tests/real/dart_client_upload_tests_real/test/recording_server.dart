import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ReceivedPart {
  ReceivedPart(this.name, this.filename, this.contentType, this.bytes);
  final String name;
  final String? filename;
  final String? contentType;
  final Uint8List bytes;

  String get sha256Hex => sha256.convert(bytes).toString();
  String get text => utf8.decode(bytes);
}

class ReceivedRequest {
  ReceivedRequest(this.contentLength, this.chunked, this.parts);
  final int contentLength;
  final bool chunked;
  final List<ReceivedPart> parts;

  ReceivedPart part(String name) => parts.firstWhere((p) => p.name == name);
}

/// Minimal GraphQL endpoint that records every multipart request on the wire
/// and answers `{"data": {<operation>: true}}`.
class RecordingServer {
  RecordingServer._(this._server);
  final HttpServer _server;
  final requests = <ReceivedRequest>[];

  static Future<RecordingServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final recording = RecordingServer._(server);
    server.listen(recording._handle);
    return recording;
  }

  String get url => 'http://127.0.0.1:${_server.port}/graphql';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    final contentType = request.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    final parts = boundary == null ? <ReceivedPart>[] : _parseMultipart(builder.takeBytes(), boundary);
    requests.add(ReceivedRequest(
      request.headers.contentLength,
      request.headers.chunkedTransferEncoding,
      parts,
    ));
    request.response
      ..headers.contentType = ContentType.json
      ..write('{"data":{"uploadOneFile":true,"uploadFileList":true}}');
    await request.response.close();
  }
}

List<ReceivedPart> _parseMultipart(Uint8List body, String boundary) {
  final delimiter = ascii.encode('--$boundary');
  final crlfcrlf = ascii.encode('\r\n\r\n');
  final starts = <int>[];
  for (var i = 0; i <= body.length - delimiter.length;) {
    final at = _indexOf(body, delimiter, i);
    if (at < 0) break;
    starts.add(at);
    i = at + delimiter.length;
  }
  final parts = <ReceivedPart>[];
  for (var i = 0; i < starts.length - 1; i++) {
    final from = starts[i] + delimiter.length + 2;
    final to = starts[i + 1] - 2;
    final headerEnd = _indexOf(body, crlfcrlf, from);
    final headers = ascii.decode(body.sublist(from, headerEnd), allowInvalid: true);
    final disposition = RegExp(r'name="([^"]*)"(?:; filename="([^"]*)")?').firstMatch(headers)!;
    final type = RegExp(r'content-type: ([^\r\n]+)', caseSensitive: false).firstMatch(headers)?.group(1);
    parts.add(ReceivedPart(
      disposition.group(1)!,
      disposition.group(2),
      type,
      Uint8List.sublistView(body, headerEnd + 4, to),
    ));
  }
  return parts;
}

int _indexOf(Uint8List haystack, List<int> needle, int start) {
  for (var i = start; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
