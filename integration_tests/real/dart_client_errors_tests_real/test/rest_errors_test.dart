import 'package:graphlink_dart_errors_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() => client = GraphLinkClient.withHttp(url: 'http://127.0.0.1:9930/graphql', restBaseUrl: 'http://127.0.0.1:9930'));

  Future<Object> thrownBy(Future<Object?> Function() call) async {
    try {
      await call();
    } catch (e) {
      return e;
    }
    fail('expected an exception');
  }

  test('a successful call returns its data', () async {
    expect((await client.queries.item(id: '1')).name, 'Item 1');
  });

  test('a status-only error is thrown with the fields of the body', () async {
    final e = await thrownBy(() => client.queries.item(id: 'missing'));
    expect(e, isA<ItemNotFound>());
    expect(e, isA<GraphLinkDomainError>());
    expect((e as ItemNotFound).id, 'missing');
    expect(e.message, 'Item missing not found');
  });

  test('it can be caught by type', () async {
    var caught = '';
    try {
      await client.queries.item(id: 'conflict');
    } on ItemConflict catch (e) {
      caught = e.reason;
    }
    expect(caught, 'duplicate');
  });

  test('a status with its own value matches the body code', () async {
    final e = await thrownBy(() => client.queries.item(id: 'conflict'));
    expect(e, isA<ItemConflict>());
    expect((e as ItemConflict).message, 'Conflict');
  });

  test('a custom field path is read from the body', () async {
    final e = await thrownBy(() => client.queries.item(id: 'rate'));
    expect(e, isA<RateLimited>());
    expect((e as RateLimited).retryAfter, 30);
  });

  test('a status-only error does not need a JSON body', () async {
    expect(await thrownBy(() => client.queries.item(id: 'teapot')), isA<Teapot>());
  });

  test('a status-only error with an HTML body still matches by status', () async {
    final e = await thrownBy(() => client.queries.item(id: 'html-404'));
    expect(e, isA<ItemNotFound>());
    expect((e as ItemNotFound).id, isNull);
  });

  test('a mutation throws its declared error', () async {
    final e = await thrownBy(() => client.mutations.createItem(input: ItemInput(name: 'dup')));
    expect(e, isA<ItemConflict>());
    expect((e as ItemConflict).reason, 'name taken');
  });

  test('a mutation returns its data', () async {
    expect((await client.mutations.createItem(input: ItemInput(name: 'fresh'))).id, 'new');
  });

  group('falls back to RestError', () {
    final cases = [
      ['a body missing a required field', 'conflict-no-reason', 409],
      ['a code the client does not know', 'conflict-other', 409],
      ['a mistyped field', 'rate-bad', 429],
      ['a proxy error with an HTML body', 'bad-gateway', 502],
    ];
    for (final c in cases) {
      test(c[0] as String, () async {
        final e = await thrownBy(() => client.queries.item(id: c[1] as String));
        expect(e, isA<RestError>());
        expect(e, isNot(isA<GraphLinkDomainError>()));
        expect((e as RestError).status, c[2]);
      });
    }

    test('an operation without @glThrows', () async {
      final e = await thrownBy(() => client.queries.itemPlain(id: 'x'));
      expect(e, isA<RestError>());
      expect((e as RestError).status, 404);
    });
  });
}
