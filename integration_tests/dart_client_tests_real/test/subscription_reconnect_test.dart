import 'dart:async';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test 1: subscription resumes after mid-run server halt + restart
  // ---------------------------------------------------------------------------
  group('reconnect: server halts during active subscription', () {
    const port = 9996;
    setUpAll(() async => startServer(port));
    tearDownAll(() async => killPort(port));

    test('counterTick resumes after server halt', () async {
      final ws = newWsAdapter(port: port);
      final client =
          GraphLinkClient(adapter: httpAdapterForPort(port), wsAdapter: ws);
      const stopAt = 5;

      var reconnected = false;
      ws.onReconnect.listen((_) {
        reconnected = true;
        print('[ws] reconnected');
      });

      final eventSet = <int>{};
      final done = Completer<void>();
      StreamSubscription? subscription;

      subscription = client.subscriptions.counterTick().listen(
        (event) async {
          try {
            final tick = event.counterTick;
            print('tick ${eventSet.length + 1}  value=$tick');

            if (tick == stopAt - 1) {
              // Kill and restart the server — client must reconnect and resume.
              await startServer(port);
            }

            if (eventSet.contains(tick)) {
              // Repeated tick confirms post-reconnect events are flowing.
              if (!done.isCompleted) done.complete();
              return;
            }

            eventSet.add(tick);
          } catch (e, st) {
            if (!done.isCompleted) done.completeError(e, st);
          }
        },
        onError: (e) => print('[stream] error: $e'),
        onDone: () => print('[stream] closed'),
      );

      try {
        await done.future.timeout(const Duration(minutes: 2));
        expect(reconnected, isTrue,
            reason: 'ws.onReconnect should have fired after server halt');
        expect(eventSet, containsAll([1, 2, 3, stopAt - 1]),
            reason: 'should have received ticks 1-${stopAt - 1} before halt');
      } finally {
        await subscription.cancel();
        await ws.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ---------------------------------------------------------------------------
  // Test 3: maxReconnectAttempts=null — adapter retries indefinitely
  // ---------------------------------------------------------------------------
  group('reconnect: null maxReconnectAttempts retries indefinitely', () {
    const port = 9994;
    const targetAttempts = 10;

    setUpAll(() async => killPort(port));
    tearDownAll(() async => killPort(port));

    test('makes $targetAttempts connection attempts without giving up',
        () async {
      // maxReconnectAttempts=null + maxReconnectDelay=2s: caps at ~2–3 s per
      // attempt. Poll ws.reconnectAttempts until it reaches targetAttempts,
      // confirming the adapter never gives up when the cap is null.
      final ws = newWsAdapterNeverStop(port: port);
      final client = GraphLinkClient(
        adapter: httpAdapterForPort(port),
        wsAdapter: ws,
      );

      var reconnected = false;
      ws.onReconnect.listen((_) => reconnected = true);

      StreamSubscription? subscription;
      subscription = client.subscriptions.counterTick().listen(
            (_) {},
            onError: (e) => print('[stream] error: $e'),
            onDone: () => print('[stream] closed'),
          );

      try {
        final deadline = DateTime.now().add(const Duration(minutes: 1));
        while (ws.reconnectAttempts < targetAttempts) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
                'Timed out — only reached ${ws.reconnectAttempts}/$targetAttempts attempts');
          }
          await Future.delayed(const Duration(milliseconds: 500));
          print('[test] reconnectAttempts=${ws.reconnectAttempts}');
        }
        expect(ws.reconnectAttempts, greaterThanOrEqualTo(targetAttempts),
            reason:
                'adapter must keep retrying when maxReconnectAttempts is null');
        expect(reconnected, isFalse,
            reason: 'no successful reconnect expected — no server is running');
      } finally {
        await subscription.cancel();
        await ws.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ---------------------------------------------------------------------------
  // Test 2: subscription set up before server is available
  // ---------------------------------------------------------------------------
  group('reconnect: subscribe before server starts', () {
    const port = 9997;
    setUpAll(() async => killPort(port)); // ensure server is off at start
    tearDownAll(() async => killPort(port));

    test('subscription connects once server becomes available', () async {
      final ws = newWsAdapter(port: port);
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);

      var reconnected = false;
      ws.onReconnect.listen((_) {
        reconnected = true;
        print('[ws] reconnected — server came up');
      });

      final firstTick = Completer<int>();
      StreamSubscription? subscription;

      // Subscribe while the server is off; the adapter will keep retrying.
      subscription = client.subscriptions.counterTick().listen(
        (event) {
          if (!firstTick.isCompleted) firstTick.complete(event.counterTick);
        },
        onError: (e) => print('[stream] error: $e'),
        onDone: () => print('[stream] closed'),
      );

      // Bring the server up — startServer takes ~8 s so the adapter will have
      // already failed at least one connect attempt by the time it returns.
      await startServer(port);

      try {
        final tick =
            await firstTick.future.timeout(const Duration(seconds: 30));
        expect(tick, greaterThan(0),
            reason: 'should receive a tick once server is up');
        expect(reconnected, isTrue,
            reason:
                'onReconnect should fire when the server becomes available');
      } finally {
        await subscription.cancel();
        await ws.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
