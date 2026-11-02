import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:graphlink_rest_client_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'rest_adapter.dart';

const product = {'id': 'p1', 'name': 'Pen', 'price': 2.5, 'status': 'ACTIVE', 'tags': ['a', 'b']};

void main() {
  late MockRest rest;
  late GraphLinkClient client;

  setUp(() {
    rest = MockRest();
    client = clientFor(rest);
  });

  group('requests', () {
    test('path variable is encoded and enum query value sent', () async {
      rest.on('GET', '/products/a%20b', json: product);
      final result = await client.queries.product(id: 'a b', status: Status.archived);
      expect(result!.name, 'Pen');
      expect(rest.last.method, 'GET');
      expect(q(rest.last), 'status=ARCHIVED');
      expect(rest.last.headers['Accept'], 'application/json');
      expect(rest.last.body, isNull);
      expect(rest.last.headers.containsKey('Content-Type'), isFalse);
    });

    test('defaults are sent, lists repeat the key, input spreads, input header spreads', () async {
      rest.on('GET', '/products', json: [product]);
      await client.queries.products(
        filter: Filter(tag: 'x', minPrice: 3),
        ids: ['1', '2'],
        auth: Auth(token: 't', requestId: 'r1'),
      );
      expect(q(rest.last), 'tag=x&minPrice=3.0&page=1&ids=1&ids=2');
      expect(rest.last.headers['token'], 't');
      expect(rest.last.headers['X-Request-Id'], 'r1');
    });

    test('null optional arguments are omitted', () async {
      rest.on('GET', '/products', json: <Object>[]);
      await client.queries.products();
      expect(q(rest.last), 'page=1');
    });

    test('FLAT objects in a list use indexed keys and lists of scalars repeat', () async {
      rest.on('GET', '/products/search', json: {'data': {'total': 1, 'items': [product]}});
      final page = await client.queries.search(
        q: 'pen',
        groups: [Group(name: 'g', ids: [1, 2]), Group(name: 'h')],
        tags: ['x', 'y'],
      );
      expect(q(rest.last), 'q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y');
      expect(page.total, 1);
      expect(page.items.single.id, 'p1');
    });

    test('JSON body is the argument itself with Content-Type', () async {
      rest.on('POST', '/products', status: 201, json: product);
      final created = await client.mutations.createProduct(input: ProductIn(name: 'Pen', price: 2.5));
      expect(created.id, 'p1');
      expect(jsonDecode(rest.bodies.single), {'name': 'Pen', 'price': 2.5});
      expect(rest.last.headers['Content-Type'], 'application/json');
    });

    test('form body carries only non-null fields', () async {
      rest.on('POST', '/products/p1/rename', json: product);
      await client.mutations.rename(id: 'p1', name: 'New');
      final body = rest.last.body as RestFormBody;
      expect(body.fields.map((e) => '${e.key}=${e.value}'), ['name=New']);
      expect(rest.last.headers['Content-Type'], 'application/x-www-form-urlencoded');
    });

    test('multipart carries text and file parts', () async {
      rest.on('POST', '/products/p1/gallery', json: product);
      await client.mutations.gallery(
        id: 'p1',
        title: 'T',
        files: [GLUpload.fromBytes(Uint8List.fromList([1]), filename: 'a.png'), GLUpload.fromBytes(Uint8List.fromList([2]), filename: 'b.png')],
      );
      final body = rest.last.body as RestMultipartBody;
      expect(body.parts.map((p) => p.name), ['title', 'files', 'files']);
      expect(body.parts.first.value, 'T');
      expect(body.parts.last.file!.filename, 'b.png');
      expect(rest.last.headers.containsKey('Content-Type'), isFalse);
    });

    test('raw body streams the upload with its mime type', () async {
      rest.on('PUT', '/products/p1/avatar', status: 204);
      await client.mutations.avatar(
        id: 'p1',
        file: GLUpload.fromBytes(Uint8List.fromList(utf8.encode('bytes')), mimeType: 'image/png'),
      );
      expect(rest.bodies.single, 'bytes');
      expect(rest.last.headers['Content-Type'], 'image/png');
    });
  });

  group('responses', () {
    test('Void accepts any 2xx and ignores the body', () async {
      rest.on('DELETE', '/products/p1', status: 200, text: 'whatever');
      await client.mutations.deleteProduct(id: 'p1');
      expect(rest.last.method, 'DELETE');
    });

    test('nullable result with an empty body is null', () async {
      rest.on('GET', '/products/p1', status: 204);
      expect(await client.queries.product(id: 'p1'), isNull);
    });

    test('non-null result with an empty body is a decode error', () async {
      rest.on('GET', '/products/count', status: 200);
      await expectLater(client.queries.count(), throwsFormatException);
    });

    test('non-2xx raises RestError with status, headers and body', () async {
      rest.on('GET', '/products/p1', status: 404, text: 'nope', headers: {'x-a': 'b'});
      try {
        await client.queries.product(id: 'p1');
        fail('should throw');
      } on RestError catch (e) {
        expect(e.status, 404);
        expect(e.body, 'nope');
        expect(e.headers['x-a'], 'b');
      }
    });

    test('TEXT response is returned verbatim', () async {
      rest.on('GET', '/products/p1/note', text: 'hello');
      expect(await client.queries.note(id: 'p1'), 'hello');
    });

    test('scalar JSON result', () async {
      rest.on('GET', '/products/count', json: 7);
      expect(await client.queries.count(), 7);
    });
  });

  group('cache', () {
    test('a cached GET query hits the adapter once', () async {
      rest.on('GET', '/products/cached/p1', json: product);
      await client.queries.cached(id: 'p1');
      await client.queries.cached(id: 'p1');
      expect(rest.calls, hasLength(1));
      rest.on('GET', '/products/cached/p2', json: product);
      await client.queries.cached(id: 'p2');
      expect(rest.calls, hasLength(2));
    });

    test('a REST mutation invalidates the tag after a 2xx', () async {
      rest.on('GET', '/products/cached/p1', json: product);
      rest.on('PUT', '/products/cached/p1', json: product);
      await client.queries.cached(id: 'p1');
      await client.mutations.updateCached(id: 'p1', input: ProductIn(name: 'x'));
      await client.queries.cached(id: 'p1');
      expect(rest.calls.where((c) => c.method == 'GET'), hasLength(2));
    });

    test('a failed mutation does not invalidate', () async {
      rest.on('GET', '/products/cached/p1', json: product);
      rest.on('PUT', '/products/cached/p1', status: 500, text: 'boom');
      await client.queries.cached(id: 'p1');
      await expectLater(client.mutations.updateCached(id: 'p1', input: ProductIn(name: 'x')), throwsA(isA<RestError>()));
      await client.queries.cached(id: 'p1');
      expect(rest.calls.where((c) => c.method == 'GET'), hasLength(1));
    });

    test('staleIfOffline serves stale data on a transport failure only', () async {
      rest.on('GET', '/products/offline/p1', json: product);
      await client.queries.cachedOffline(id: 'p1');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      rest.failTransport = true;
      expect((await client.queries.cachedOffline(id: 'p1'))!.id, 'p1');
      rest.failTransport = false;
      rest.on('GET', '/products/offline/p1', status: 500, text: 'down');
      await expectLater(client.queries.cachedOffline(id: 'p1'), throwsA(isA<RestError>()));
    });
  });

  test('GraphQL and REST operations share one client', () async {
    rest.on('GET', '/products/count', json: 3);
    expect((await client.queries.ping()).ping, 'pong');
    expect(await client.queries.count(), 3);
  });

  group('downloads', () {
    test('stream, filename, content type and length come from the response', () async {
      rest.on('GET', '/products/p1/export',
          text: 'abcdef',
          headers: {'Content-Type': 'text/csv', 'Content-Length': '6', 'Content-Disposition': 'attachment; filename="p 1.csv"'});
      final received = <int>[];
      final download = await client.queries.export_(id: 'p1', onReceiveProgress: (r, t) => received.add(r * 100 + t));
      expect(download.filename, 'p 1.csv');
      expect(download.contentType, 'text/csv');
      expect(download.length, 6);
      expect(rest.last.headers['Accept'], '*/*');
      expect(utf8.decode(await download.bytes()), 'abcdef');
      expect(received.last, 606);
    });

    test('an RFC 5987 filename* is decoded', () async {
      rest.on('GET', '/products/p1/export', text: 'x', headers: {'Content-Disposition': "attachment; filename*=UTF-8''p%201%C3%A9.csv"});
      expect((await client.queries.export_(id: 'p1')).filename, 'p 1é.csv');
    });

    test('a nullable download is null on 204', () async {
      rest.on('GET', '/products/p1/maybe', status: 204);
      expect(await client.queries.maybeExport(id: 'p1'), isNull);
    });

    test('a non-null download on 204 is a decode error', () async {
      rest.on('GET', '/products/p1/export', status: 204);
      await expectLater(client.queries.export_(id: 'p1'), throwsFormatException);
    });

    test('non-2xx still raises RestError', () async {
      rest.on('GET', '/products/p1/export', status: 500, text: 'x');
      await expectLater(client.queries.export_(id: 'p1'), throwsA(isA<RestError>()));
    });
  });
}
