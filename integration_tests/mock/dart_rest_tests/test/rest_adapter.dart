import 'dart:async';
import 'dart:convert';

import 'package:graphlink_rest_client_tests/generated/graphlink.dart';

class MockRest {
  final calls = <RestRequest>[];
  final bodies = <String>[];
  final _responses = <String, RestResponse Function()>{};
  bool failTransport = false;

  void on(String method, String path, {int status = 200, Object? json, String? text, Map<String, String> headers = const {}}) {
    final bytes = utf8.encode(text ?? (json == null ? '' : jsonEncode(json)));
    _responses['$method $path'] = () => RestResponse(status: status, headers: headers, stream: Stream.value(bytes));
  }

  RestRequest get last => calls.last;

  Future<RestResponse> call(RestRequest request) async {
    if (failTransport) throw StateError('offline');
    calls.add(request);
    final body = request.body;
    if (body is RestJsonBody) {
      bodies.add(body.json);
    } else if (body is RestRawBody) {
      bodies.add(utf8.decode(await body.upload.stream.expand((e) => e).toList()));
    }
    final response = _responses['${request.method} ${request.path}'];
    if (response == null) return RestResponse(status: 404, stream: Stream.value(utf8.encode('no mock')));
    return response();
  }
}

String q(RestRequest r) => r.query.map((e) => '${e.key}=${e.value}').join('&');

GraphLinkClient clientFor(MockRest rest) => GraphLinkClient(
      adapter: (payload) async => '{"data":{"ping":"pong"}}',
      restAdapter: rest.call,
    );
