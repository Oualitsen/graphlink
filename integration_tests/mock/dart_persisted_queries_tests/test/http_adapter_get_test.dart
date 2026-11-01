import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:graphlink_persisted_queries_tests/generated/graphlink.dart';
import '../../dart_client_tests/test/fixtures.dart';
import 'apq_server.dart';

class HttpRequestLog {
  final String method;
  final Map<String, String> query;
  final String? authorization;
  HttpRequestLog(this.method, this.query, this.authorization);
}

void main() {
  late HttpServer http;
  late ApqServer server;
  late GraphLinkClient client;
  late List<HttpRequestLog> seen;

  setUp(() async {
    server = ApqServer()..respondTo('persistedLongQuery', {'getUser': kUserAliceJson});
    seen = [];
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      seen.add(HttpRequestLog(request.method, request.uri.queryParameters, request.headers.value('authorization')));
      String body;
      try {
        if (request.method == 'GET') {
          final params = request.uri.queryParameters;
          body = await server.get(jsonEncode({
            if (params.containsKey('operationName')) 'operationName': params['operationName'],
            'variables': params.containsKey('variables') ? jsonDecode(params['variables']!) : {},
            'extensions': jsonDecode(params['extensions']!),
          }));
        } else {
          body = await server.call(await utf8.decoder.bind(request).join());
        }
      } on GraphLinkGetNotSupported {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(body);
      await request.response.close();
    });
    client = GraphLinkClient.withHttp(
      url: 'http://127.0.0.1:${http.port}/graphql',
      wsUrl: 'ws://127.0.0.1:${http.port}/graphql',
      headersProvider: () async => {'authorization': 'Bearer token'},
    );
  });

  tearDown(() => http.close(force: true));

  test('a cold long query is a GET with the hash, then a POST with the query', () async {
    final res = await client.queries.persistedLongQuery(id: 'user-1');

    expect(res.getUser.name, 'Alice Smith');
    expect(seen.map((r) => r.method), ['GET', 'POST']);
  });

  test('the GET carries the operation, its variables and the hash in the URL', () async {
    await client.queries.persistedLongQuery(id: 'user-1');

    final query = seen.first.query;
    expect(query.keys.toSet(), {'operationName', 'variables', 'extensions'});
    expect(query['operationName'], 'persistedLongQuery');
    expect(jsonDecode(query['variables']!), {'id': 'user-1'});
    expect(jsonDecode(query['extensions']!)['persistedQuery']['version'], 1);
  });

  test('a warm query is a single GET', () async {
    await client.queries.persistedLongQuery(id: 'user-1');
    seen.clear();

    await client.queries.persistedLongQuery(id: 'user-2');

    expect(seen.map((r) => r.method), ['GET']);
  });

  test('the headers provider applies to the GET as well', () async {
    await client.queries.persistedLongQuery(id: 'user-1');

    expect(seen.first.authorization, 'Bearer token');
  });

  test('a 405 on GET sends the same request as a POST and remembers it', () async {
    server.getSupported = false;

    final res = await client.queries.persistedLongQuery(id: 'user-1');

    expect(res.getUser.name, 'Alice Smith');
    expect(seen.map((r) => r.method), ['GET', 'POST', 'POST']);
    seen.clear();

    await client.queries.persistedLongQuery(id: 'user-2');
    expect(seen.map((r) => r.method), ['POST']);
  });
}
