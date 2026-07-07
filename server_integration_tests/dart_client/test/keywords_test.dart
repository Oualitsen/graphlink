import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('reserved-word fields round-trip (both / dart-only / java-only)', () async {
    final r = (await client.queries.reserved()).reserved;
    expect(r.class_, 'cls');
    expect(r.return_, 42);
    expect(r.new_, true);
    expect(r.default_, 'def');
    expect(r.is_, 'yes');
    expect(r.in_, 'inside');
    expect(r.with_, 'w');
    expect(r.int_, 7); // `int` shadows the dart:core type -> sanitized to int_
    expect(r.synchronized, false);
    expect(r.native, 'n');
    expect(r.kind, Keyword.class_);
    expect(r.nested.value, 'v');
    expect(r.secret.token, 'tok');
  });

  test('reserved operation name + reserved argument names', () async {
    final res = await client.queries.switch_(class_: 'x', return_: 5);
    expect(res.switch_.class_, 'x');
    expect(res.switch_.return_, 5);
  });

  test('leading-underscore operation', () async {
    final res = await client.queries.status();
    expect(res.status, 'ok');
  });

  test('colliding field names stay distinct', () async {
    final c = (await client.queries.collide()).collide;
    expect([c.class_2, c.class2], containsAll(['A', 'B']));
  });

  test('reserved-word input fields (mutation)', () async {
    final res = await client.mutations.echoReserved(
      input: const ReservedInput(
          class_: 'X', return_: 5, default_: 'D', is_: true, synchronized: 3),
    );
    expect(res.echoReserved.class_, 'X');
    expect(res.echoReserved.return_, 5);
    expect(res.echoReserved.default_, 'D');
  });
}
