import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('a scalar with a codec', () {
    test('is decoded in a response', () async {
      final bag = (await client.queries.scalarFixture()).scalarFixture;
      expect(bag.opaque, 'opaque:o-1');
    });

    test('is encoded in an input field and decoded again', () async {
      final input = ScalarsInput(dt: 'x', long: 1, dts: [], opaque: 'opaque:xyz');
      final bag = (await client.queries.echoScalars(input: input)).echoScalars;
      expect(bag.opaque, 'opaque:xyz');
    });

    test('is encoded in an operation argument and decoded again', () async {
      final bag = (await client.queries.echoScalarArgs(dt: 'x', dts: [], opaque: 'opaque:abc')).echoScalarArgs;
      expect(bag.opaque, 'opaque:abc');
    });

    test('keeps null as null in both directions', () async {
      final fromArgs = (await client.queries.echoScalarArgs(dt: 'x', dts: [])).echoScalarArgs;
      expect(fromArgs.opaque, isNull);
      final fromInput = (await client.queries.echoScalars(input: ScalarsInput(dt: 'x', long: 1, dts: []))).echoScalars;
      expect(fromInput.opaque, isNull);
    });
  });

  group('scalars that are plain aliases', () {
    test('a Long beyond 2^53 survives', () async {
      final bag = (await client.queries.scalarFixture()).scalarFixture;
      expect(bag.long, 9007199254740993);
      expect(bag.longs, [1, null, 9223372036854775807]);
    });

    test('a JSON scalar keeps its shape', () async {
      final bag = (await client.queries.scalarFixture()).scalarFixture;
      expect(bag.json, {'name': 'x', 'n': 1, 'list': [1, 'two', false]});
    });

    test('a string-like scalar is passed through', () async {
      final bag = (await client.queries.scalarFixture()).scalarFixture;
      expect(bag.dt, '2026-01-02T03:04:05Z');
      expect(bag.dts, ['2026-01-02T03:04:05Z', '2027-02-03T04:05:06Z']);
    });

    test('the Long default reaches the server', () async {
      final bag = (await client.queries.echoScalarArgs(dt: 'x', dts: [])).echoScalarArgs;
      expect(bag.long, 9007199254740993);
    });
  });
}
