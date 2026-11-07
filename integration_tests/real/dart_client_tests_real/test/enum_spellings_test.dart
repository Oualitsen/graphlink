import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('every spelling round trips through a list argument', () async {
    final r = (await client.queries.echoArgs(a: [], e: Spelling.values.where((v) => v != Spelling.unknownValue__).toList())).echoArgs;
    expect(r.e, Spelling.values.where((v) => v != Spelling.unknownValue__).toList());
  });

  test('wire names are the declared ones', () {
    expect(Spelling.a.toJson(), 'A');
    expect(Spelling.b2.toJson(), 'B2');
    expect(Spelling.xY.toJson(), 'x__y');
    expect(Spelling.http2Ok.toJson(), 'http2_ok');
    expect(Spelling.v1.toJson(), 'v1');
    expect(Spelling.snakeCase2.toJson(), 'snake_case_2');
  });

  test('a single-value enum round trips', () async {
    final r = (await client.queries.echoArgs(a: [], e: [], one: OnlyOne.only)).echoArgs;
    expect(r.one, OnlyOne.only);
  });

  test('an enum used only as an argument', () async {
    expect((await client.queries.argOnly(v: ArgOnly.p2)).argOnly, 'P2');
  });

  test('an enum used only in a response', () async {
    expect((await client.queries.respOnly()).respOnly, RespOnly.r2);
  });

  group('unknown enum value sent by the server', () {
    test('in a field', () async {
      final p = (await client.queries.phaseProbe()).phaseProbe;
      expect(p.single, Phase.unknownValue__);
      expect(p.maybe, Phase.unknownValue__);
    });

    test('in list elements, known ones untouched', () async {
      final p = (await client.queries.phaseProbe()).phaseProbe;
      expect(p.list, [Phase.open, Phase.unknownValue__, Phase.closed]);
      expect(p.nullableList, [Phase.unknownValue__, null]);
    });

    test('in a union member', () async {
      final h = (await client.queries.phaseHolder()).phaseHolder;
      expect((h as Phased).phase, Phase.unknownValue__);
    });
  });
}
