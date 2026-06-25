import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/types/counter_tick_response.dart';
import 'real_server_adapter.dart';

void main() {
  // ── userCreated ────────────────────────────────────────────────────────────

  group('userCreated', () {
    test('first event is Alice', () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final event = await client.subscriptions
            .userCreated()
            .first
            .timeout(const Duration(seconds: 10));
        expect(event.userCreated.id, equals('user-1'));
        expect(event.userCreated.name, equals('Alice Smith'));
        expect(event.userCreated.status, equals(UserStatus.ACTIVE));
      } finally {
      }
    });

    test('stream emits multiple events', () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final events = await client.subscriptions
            .userCreated()
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 10));
        expect(events, hasLength(2));
        expect(events[0].userCreated.id, equals('user-1'));
        expect(events[1].userCreated.id, equals('user-2'));
      } finally {
      }
    });
  });

  // ── reconnect ─────────────────────────────────────────────────────────────

  group('reconnect', () {
    test('counterTick resumes after server shutdown and restart', () async {
      final serverJar = Platform.environment['SERVER_JAR'];
      if (serverJar == null) {
        markTestSkipped(
            'SERVER_JAR env var not set — run via make reconnect-test');
        return;
      }

      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);

      final firstCompleter = Completer<void>();
      final afterReconnectCompleter = Completer<void>();
      var firstDone = false;
      Process? newProc;

      final sub = client.subscriptions.counterTick().listen(
        (event) {
          if (!firstDone) {
            firstDone = true;
            firstCompleter.complete();
          } else if (!afterReconnectCompleter.isCompleted) {
            afterReconnectCompleter.complete();
          }
        },
        onError: (_) {},
      );

      try {
        // confirm subscription is live
        print('TEST: waiting for first tick...');
        await firstCompleter.future.timeout(const Duration(seconds: 10));
        print('TEST: first tick received');

        // SIGKILL the server — abrupt drop, no close frame, triggers _onError → reconnect.
        // (actuator shutdown sends close code 1000 which the adapter skips for reconnect)
        // -sTCP:LISTEN ensures we only get the server, not our own client connection
        final lsof =
            await Process.run('lsof', ['-ti', ':9999', '-sTCP:LISTEN']);
        final pidOutput = lsof.stdout.toString().trim();
        final pids = pidOutput.isEmpty ? <String>[] : pidOutput.split('\n');
        print('TEST: lsof found server pids=$pids');
        for (final pid in pids) {
          if (pid.isNotEmpty) {
            final killResult = await Process.run('kill', ['-9', pid]);
            print('TEST: kill -9 $pid exit=${killResult.exitCode}');
          }
        }
        // Verify all are dead
        await Future.delayed(const Duration(milliseconds: 500));
        final lsof2 =
            await Process.run('lsof', ['-ti', ':9999', '-sTCP:LISTEN']);
        print(
            'TEST: after kill, port 9999 pids="${lsof2.stdout.toString().trim()}"');

        // restart the server in the background
        print('TEST: starting new server...');
        newProc = await Process.start('java', ['-jar', serverJar]);
        print('TEST: new server PID ${newProc.pid}');

        // adapter detects the drop and reconnects once the server is back up
        print('TEST: waiting for onReconnect...');
        await ws.onReconnect.first.timeout(const Duration(seconds: 30));

        // existing stream resumes delivering ticks
        print('TEST: onReconnect received, waiting for next tick...');
        await afterReconnectCompleter.future
            .timeout(const Duration(seconds: 15));
        print('TEST: next tick received, test passed!');
      } finally {
        await sub.cancel();
        await ws.close();
        newProc?.kill(ProcessSignal.sigkill);
      }
    });
  });

  // ── multipleSubscriptions ─────────────────────────────────────────────────

  group('multipleSubscriptions', () {
    test('userCreated and counterTick run concurrently on one connection',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        // Both futures are created (subscriptions started) before either is awaited.
        final userFuture = client.subscriptions
            .userCreated()
            .first
            .timeout(const Duration(seconds: 10));
        final counterFuture = client.subscriptions
            .counterTick()
            .first
            .timeout(const Duration(seconds: 10));

        final userEvent = await userFuture;
        final counterEvent = await counterFuture;

        expect(userEvent.userCreated.id, equals('user-1'));
        expect(counterEvent.counterTick, isA<int>());
      } finally {
        await ws.close();
      }
    });

    test(
        'two userStatusChanged subscriptions with different args receive independent events',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final user1Future = client.subscriptions
            .userStatusChanged(userId: 'user-1')
            .first
            .timeout(const Duration(seconds: 10));
        final user2Future = client.subscriptions
            .userStatusChanged(userId: 'user-2')
            .first
            .timeout(const Duration(seconds: 10));

        final user1Event = await user1Future;
        final user2Event = await user2Future;

        expect(user1Event.userStatusChanged.id, equals('user-1'));
        expect(user1Event.userStatusChanged.status, equals(UserStatus.ACTIVE));
        expect(user2Event.userStatusChanged.id, equals('user-2'));
        expect(
            user2Event.userStatusChanged.status, equals(UserStatus.INACTIVE));
      } finally {
        await ws.close();
      }
    });

    test(
        'three concurrent subscriptions each deliver their first event independently',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final f1 = client.subscriptions
            .userCreated()
            .first
            .timeout(const Duration(seconds: 10));
        final f2 = client.subscriptions
            .userStatusChanged(userId: 'user-1')
            .first
            .timeout(const Duration(seconds: 10));
        final f3 = client.subscriptions
            .counterTick()
            .first
            .timeout(const Duration(seconds: 10));

        final e1 = await f1;
        final e2 = await f2;
        final e3 = await f3;

        expect(e1.userCreated.id, equals('user-1'));
        expect(e2.userStatusChanged.id, equals('user-1'));
        expect(e3.counterTick, isA<int>());
      } finally {
        await ws.close();
      }
    });

    test('cancelling one subscription does not stop the other', () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      StreamSubscription<CounterTickResponse>? counterSub;
      final firstTickCompleter = Completer<void>();
      var tickCount = 0;
      try {
        // Start counterTick first — runs indefinitely.
        counterSub = client.subscriptions.counterTick().listen(
          (event) {
            tickCount++;
            if (!firstTickCompleter.isCompleted) firstTickCompleter.complete();
          },
          onError: (_) {},
        );

        // Run userCreated to completion (server emits Alice + Bob, then closes).
        await client.subscriptions
            .userCreated()
            .drain()
            .timeout(const Duration(seconds: 10));

        // counterTick must still be alive.
        await firstTickCompleter.future.timeout(const Duration(seconds: 10));
        expect(tickCount, greaterThanOrEqualTo(1));
      } finally {
        await counterSub?.cancel();
        await ws.close();
      }
    });

    test(
        'two identical userCreated subscriptions each receive all events independently',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        // Same operation registered twice — each gets its own UUID and server-side stream.
        final f1 = client.subscriptions
            .userCreated()
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 10));
        final f2 = client.subscriptions
            .userCreated()
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 10));

        final events1 = await f1;
        final events2 = await f2;

        expect(events1, hasLength(2));
        expect(events1[0].userCreated.id, equals('user-1'));
        expect(events1[1].userCreated.id, equals('user-2'));
        expect(events2, hasLength(2));
        expect(events2[0].userCreated.id, equals('user-1'));
        expect(events2[1].userCreated.id, equals('user-2'));
      } finally {
        await ws.close();
      }
    });

    test(
        'two identical userStatusChanged(user-1) subscriptions each receive the event independently',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final f1 = client.subscriptions
            .userStatusChanged(userId: 'user-1')
            .first
            .timeout(const Duration(seconds: 10));
        final f2 = client.subscriptions
            .userStatusChanged(userId: 'user-1')
            .first
            .timeout(const Duration(seconds: 10));

        final e1 = await f1;
        final e2 = await f2;

        expect(e1.userStatusChanged.id, equals('user-1'));
        expect(e1.userStatusChanged.status, equals(UserStatus.ACTIVE));
        expect(e2.userStatusChanged.id, equals('user-1'));
        expect(e2.userStatusChanged.status, equals(UserStatus.ACTIVE));
      } finally {
        await ws.close();
      }
    });

    test(
        'userCreated and userCreateds run concurrently and return distinct typed streams',
        () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final singleFuture = client.subscriptions
            .userCreated()
            .first
            .timeout(const Duration(seconds: 10));
        final listFuture = client.subscriptions
            .userCreateds(ids: ['user-1', 'user-2'])
            .first
            .timeout(const Duration(seconds: 10));

        final singleEvent = await singleFuture;
        final listEvent = await listFuture;

        expect(singleEvent.userCreated.id, equals('user-1'));
        expect(listEvent.userCreateds, isNotNull);
        expect(listEvent.userCreateds!, hasLength(2));
        expect(listEvent.userCreateds![0].id, equals('user-1'));
        expect(listEvent.userCreateds![1].id, equals('user-2'));
      } finally {
        await ws.close();
      }
    });
  });

  // ── userStatusChanged ──────────────────────────────────────────────────────

  group('userStatusChanged', () {
    test('first event is the requested user', () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final event = await client.subscriptions
            .userStatusChanged(userId: 'user-1')
            .first
            .timeout(const Duration(seconds: 10));
        expect(event.userStatusChanged.id, equals('user-1'));
        expect(event.userStatusChanged.status, equals(UserStatus.ACTIVE));
      } finally {
        await ws.close();
      }
    });

    test('userStatusChanged for user-2 returns Bob', () async {
      final ws = newWsAdapter();
      final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
      try {
        final event = await client.subscriptions
            .userStatusChanged(userId: 'user-2')
            .first
            .timeout(const Duration(seconds: 10));
        expect(event.userStatusChanged.id, equals('user-2'));
        expect(event.userStatusChanged.status, equals(UserStatus.INACTIVE));
      } finally {
        await ws.close();
      }
    });
  });
}
