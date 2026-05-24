import 'dart:async';
import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/user_created_response.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late MockWebSocketAdapter wsAdapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    wsAdapter = MockWebSocketAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: wsAdapter);
  });

  // ── userCreated ────────────────────────────────────────────────────────────

  group('userCreated', () {
    test('single event is deserialized correctly', () async {
      final future = client.subscriptions.userCreated().first;
      await wsAdapter.subscriptionReady;

      wsAdapter.pushEvent({'userCreated': kUserAliceJson});

      final event = await future;
      expect(event.userCreated.id, equals('user-1'));
      expect(event.userCreated.name, equals('Alice Smith'));
      expect(event.userCreated.status, equals(UserStatus.ACTIVE));
    });

    test('stream emits multiple events in order', () async {
      final events = <UserCreatedResponse>[];
      final sub = client.subscriptions.userCreated().listen(events.add);
      await wsAdapter.subscriptionReady;

      wsAdapter.pushEvent({'userCreated': kUserAliceJson});
      wsAdapter.pushEvent({'userCreated': kUserBobJson});

      await Future.delayed(Duration.zero); // flush async StreamController delivery
      await sub.cancel();
      expect(events, hasLength(2));
      expect(events[0].userCreated.id, equals('user-1'));
      expect(events[1].userCreated.id, equals('user-2'));
    });

    test('complete message closes the stream', () async {
      final events = <UserCreatedResponse>[];
      final done = Completer<void>();
      client.subscriptions
          .userCreated()
          .listen(events.add, onDone: done.complete);
      await wsAdapter.subscriptionReady;

      wsAdapter.pushEvent({'userCreated': kUserAliceJson});
      wsAdapter.pushComplete();

      await done.future;
      expect(events, hasLength(1));
      expect(events.first.userCreated.id, equals('user-1'));
    });

    test('cancelling stops further event delivery', () async {
      final events = <UserCreatedResponse>[];
      final sub = client.subscriptions.userCreated().listen(events.add);
      await wsAdapter.subscriptionReady;

      wsAdapter.pushEvent({'userCreated': kUserAliceJson});
      await Future.delayed(Duration.zero); // flush async StreamController delivery
      await sub.cancel();

      wsAdapter.pushEvent({'userCreated': kUserBobJson});

      expect(events, hasLength(1));
      expect(events.first.userCreated.id, equals('user-1'));
    });
  });

  // ── userStatusChanged ──────────────────────────────────────────────────────

  group('userStatusChanged', () {
    test('event is deserialized correctly', () async {
      final future =
          client.subscriptions.userStatusChanged(userId: 'user-1').first;
      await wsAdapter.subscriptionReady;

      wsAdapter.pushEvent({'userStatusChanged': kUserAliceJson});

      final event = await future;
      expect(event.userStatusChanged.id, equals('user-1'));
      expect(event.userStatusChanged.status, equals(UserStatus.ACTIVE));
    });

    test('userId variable is sent in the subscribe message', () async {
      client.subscriptions
          .userStatusChanged(userId: 'user-42')
          .listen((_) {});
      await wsAdapter.subscriptionReady;

      final subscribeMsg =
          wsAdapter.sentMessages.firstWhere((m) => m['type'] == 'subscribe');
      expect(
        subscribeMsg['payload']['variables']['userId'],
        equals('user-42'),
      );
    });
  });
}
