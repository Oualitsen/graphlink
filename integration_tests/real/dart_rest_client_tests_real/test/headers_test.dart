import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('header arguments', () {
    test('a scalar header uses its declared name; an input spreads one header per field', () async {
      final e = await client.queries.eHeaders(tenant: 't-1', trace: Trace(traceId: 'tr', spanId: 'sp'));
      expect(e.header('X-Tenant'), 't-1');
      expect(e.header('X-Trace-Id'), 'tr');
      expect(e.header('X-Span-Id'), 'sp');
    });

    test('a null header field and a null header argument are not sent', () async {
      final e = await client.queries.eHeaders(tenant: 't', trace: Trace(traceId: 'tr'));
      expect(e.header('X-Span-Id'), isNull);
      expect(e.header('X-Opt'), isNull);
      expect(e.header('X-Roles'), isNull);
    });

    test('a list header is joined with commas', () async {
      final e = await client.queries.eHeaders(tenant: 't', roles: ['admin', 'ops']);
      expect(e.header('X-Roles'), 'admin,ops');
    });
  });

  group('Accept and Content-Type', () {
    test('Accept defaults to JSON and can be overridden per operation', () async {
      expect((await client.queries.eAccept()).header('accept'), 'application/json');
      expect((await client.queries.eAcceptOverride()).header('accept'), 'application/vnd.test+json');
    });

    test('a GET sends no Content-Type', () async {
      final e = await client.queries.eAccept();
      expect(e.contentType, isNull);
    });
  });

  group('adapter headers', () {
    test('the headers provider is consulted for every request', () async {
      var calls = 0;
      final c = newClient(headers: () async {
        calls++;
        return {'X-Provider': 'call-$calls'};
      });
      expect((await c.queries.eAccept()).header('X-Provider'), 'call-1');
      expect((await c.queries.eAccept()).header('X-Provider'), 'call-2');
    });

    test('an argument header wins over the provider', () async {
      final c = newClient(headers: () async => {'X-Tenant': 'from-provider', 'X-Other': 'kept'});
      final e = await c.queries.eHeaders(tenant: 'from-arg');
      expect(e.header('X-Tenant'), 'from-arg');
      expect(e.header('X-Other'), 'kept');
    });

    test('the provider may return null', () async {
      final c = newClient(headers: () async => null);
      expect((await c.queries.eAccept()).method, 'GET');
    });

    test('auth through the provider reaches a protected route; without it the call is a RestError 401', () async {
      await expectLater(client.queries.authCheck(),
          throwsA(isA<RestError>().having((e) => e.status, 'status', 401).having((e) => e.headers['www-authenticate'], 'challenge', 'Bearer')));
      final c = newClient(headers: () async => {'Authorization': 'Bearer secret'});
      final who = await c.queries.authCheck(tenant: 'acme');
      expect(who.user, 'ann');
      expect(who.tenant, 'acme');
    });
  });
}
