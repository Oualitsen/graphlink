import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('transport edge cases', () {
    test('a gzip-encoded response is decompressed before decoding', () async {
      expect((await client.queries.gzipped()).map((p) => p.id), ['p1', 'p2']);
    });

    test('a redirect is followed', () async {
      expect(await client.queries.redirected(), 7);
    });

    test('a large JSON response is decoded completely', () async {
      final items = await client.queries.big(n: 50000);
      expect(items.length, 50000);
      expect(items.last.name, 'big-49999');
    });

    test('a 200 with invalid JSON is a format error, not a RestError', () async {
      await expectLater(client.queries.invalidJson(), throwsA(isA<FormatException>()));
    });

    test('a non-JSON error body is kept as text on the RestError', () async {
      await expectLater(
        client.queries.htmlError(),
        throwsA(isA<RestError>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.body, 'body', contains('Internal Server Error'))
            .having((e) => e.headers['content-type'], 'content-type', startsWith('text/html'))),
      );
    });
  });
}
