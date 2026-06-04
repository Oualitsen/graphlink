import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_websocket_adapter.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
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
        await ws.close();
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
