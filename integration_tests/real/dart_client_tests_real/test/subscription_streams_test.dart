import 'dart:async';

import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

const _timeout = Duration(seconds: 10);

void main() {
  late GraphLinkClient client;

  setUp(() {
    client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: newWsAdapter());
  });

  group('arguments of every shape', () {
    test('lists, nested lists, nulls and enums round-trip', () async {
      final events = await client.subscriptions
          .subEchoArgs(
            a: [1, 2],
            b: [1, null],
            c: [[1], [], [2, 3]],
            e: [Spelling.xY, Spelling.http2Ok],
            f: [null, Spelling.v1],
          )
          .toList()
          .timeout(_timeout);
      expect(events, hasLength(1));
      final r = events.single.subEchoArgs;
      expect(r.a, [1, 2]);
      expect(r.b, [1, null]);
      expect(r.c, [[1], [], [2, 3]]);
      expect(r.e, [Spelling.xY, Spelling.http2Ok]);
      expect(r.f, [null, Spelling.v1]);
    });

    test('omitted arguments are null and declared defaults apply', () async {
      final r = (await client.subscriptions
              .subEchoArgs(a: [], e: [])
              .first
              .timeout(_timeout))
          .subEchoArgs;
      expect(r.b, isNull);
      expect(r.c, isNull);
      expect(r.f, isNull);
      expect(r.g, [Spelling.a, Spelling.b2]);
      expect(r.one, OnlyOne.only);
    });

    test('explicit null overrides a default', () async {
      final r = (await client.subscriptions
              .subEchoArgs(a: [], e: [], g: null)
              .first
              .timeout(_timeout))
          .subEchoArgs;
      expect(r.g, isNull);
    });

    test('an input object with list and enum members round-trips', () async {
      final input = ListsInput(
        a: [3, 4],
        b: [null, 5],
        c: [[1, 2], []],
        e: [Spelling.snakeCase2],
        f: [Spelling.a, null],
        g: [Spelling.v1],
      );
      final r = (await client.subscriptions
              .subEchoInput(input: input)
              .first
              .timeout(_timeout))
          .subEchoInput;
      expect(r.a, [3, 4]);
      expect(r.b, [null, 5]);
      expect(r.c, [[1, 2], []]);
      expect(r.e, [Spelling.snakeCase2]);
      expect(r.f, [Spelling.a, null]);
      expect(r.g, [Spelling.v1]);
    });
  });

  group('server-side completion', () {
    test('the stream delivers every event and then completes', () async {
      final events = await client.subscriptions
          .finiteTicks(count: 5)
          .map((e) => e.finiteTicks)
          .toList()
          .timeout(_timeout);
      expect(events, [1, 2, 3, 4, 5]);
    });

    test('a stream that completes without events is empty', () async {
      final events =
          await client.subscriptions.finiteTicks(count: 0).toList().timeout(_timeout);
      expect(events, isEmpty);
    });

    test('onDone fires for a listener', () async {
      final done = Completer<void>();
      final seen = <int>[];
      client.subscriptions.finiteTicks(count: 3).listen(
            (e) => seen.add(e.finiteTicks),
            onDone: done.complete,
          );
      await done.future.timeout(_timeout);
      expect(seen, [1, 2, 3]);
    });
  });

  group('error mid-stream', () {
    test('events before the failure arrive, then the error', () async {
      final seen = <int>[];
      Object? error;
      final done = Completer<void>();
      client.subscriptions.flakyTicks(failAfter: 3).listen(
            (e) => seen.add(e.flakyTicks),
            onError: (Object e) => error = e,
            onDone: done.complete,
          );
      await done.future.timeout(_timeout);
      expect(seen, [1, 2, 3]);
      expect(error, isNotNull);
    });

    test('a failure before the first event surfaces as an error', () async {
      await expectLater(
        client.subscriptions.flakyTicks(failAfter: 0).toList().timeout(_timeout),
        throwsA(anything),
      );
    });

    test('a failed stream does not break the next subscription', () async {
      await client.subscriptions
          .flakyTicks(failAfter: 1)
          .toList()
          .timeout(_timeout)
          .then((_) {}, onError: (_) {});
      final events =
          await client.subscriptions.finiteTicks(count: 2).toList().timeout(_timeout);
      expect(events, hasLength(2));
    });
  });
}
