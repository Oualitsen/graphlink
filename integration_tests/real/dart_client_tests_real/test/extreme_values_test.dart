import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  Future<EverythingEcho> echo(EverythingInput input) async => (await client.queries.echoEverything(input: input)).echoEverything;

  test('Int at both 32-bit limits', () async {
    final r = await echo(const EverythingInput(i: 2147483647, neg: -2147483648));
    expect(r.i, 2147483647);
    expect(r.neg, -2147483648);
  });

  test('Float at 1e308 and negative zero', () async {
    final r = await echo(const EverythingInput(f: 1e308, exp: -0.0));
    expect(r.f, 1e308);
    expect(r.exp, 0.0);
    expect(r.exp!.isNegative, isTrue, reason: 'the sign of -0.0');
  });

  test('a string with a NUL character', () async {
    final r = await echo(const EverythingInput(s: 'a\u0000b'));
    expect(r.s, 'a\u0000b');
  });

  test('a string with lone surrogates', () async {
    final sent = 'x\ud800y\udc00z';
    final r = await echo(EverythingInput(s: sent));
    expect(r.s, sent);
  });
}
