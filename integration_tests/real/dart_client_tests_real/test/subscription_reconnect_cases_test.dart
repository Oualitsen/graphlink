import 'dart:async';
import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';
import 'real_server_adapter.dart';

const _port = 9933;

class _Stream {
  final events = <String>[];
  Object? error;
  var completed = false;
  late final StreamSubscription<LabelTicksResponse> subscription;

  _Stream(GraphLinkClient client, String label, int count) {
    subscription = client.subscriptions.labelTicks(label: label, count: count).listen(
          (e) => events.add(e.labelTicks),
          onError: (Object e) => error = e,
          onDone: () => completed = true,
        );
  }

  Future<void> nextEvent(String label) async {
    final seen = events.length;
    await _until('an event for $label after the restart',
        () => events.skip(seen).any((e) => e.startsWith('$label-')));
  }
}

Future<void> _until(String what, bool Function() check,
    {Duration timeout = const Duration(minutes: 1)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out: $what');
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  late DefaultGraphLinkWebSocketAdapter ws;
  late GraphLinkClient client;
  var reconnects = 0;
  final streams = <_Stream>[];

  Future<void> connect({
    Future<Map<String, String>?> Function()? headers,
    int? maxAttempts = 10,
    Duration maxDelay = const Duration(seconds: 30),
  }) async {
    await startServer(_port);
    ws = DefaultGraphLinkWebSocketAdapter(
      url: 'ws://localhost:$_port/graphql',
      reconnect: true,
      headersProvider: headers,
      maxReconnectAttempts: maxAttempts,
      maxReconnectDelay: maxDelay,
    );
    client = GraphLinkClient(adapter: httpAdapterForPort(_port), wsAdapter: ws);
    reconnects = 0;
    ws.onReconnect.listen((_) => reconnects++);
  }

  _Stream subscribe(String label, {int count = 1000}) {
    final stream = _Stream(client, label, count);
    streams.add(stream);
    return stream;
  }

  Future<int> starts(String label) async =>
      (await client.queries.labelTickStarts(label: label)).labelTickStarts;

  tearDown(() async {
    for (final s in streams) {
      await s.subscription.cancel();
    }
    streams.clear();
    await ws.close();
    await killPort(_port);
  });

  const timeout = Timeout(Duration(minutes: 3));

  test('resubscribes with the same variables', () async {
    await connect();
    final bob = subscribe('bob');
    await _until('first event', () => bob.events.isNotEmpty);
    expect(bob.events.first, 'bob-1');

    await startServer(_port);
    await _until('a reconnect', () => reconnects >= 1);
    await bob.nextEvent('bob');
    expect(await starts('bob'), 1);
  }, timeout: timeout);

  test('does not resubscribe a completed subscription', () async {
    await connect();
    final done = subscribe('done', count: 2);
    await _until('completion', () => done.completed);
    expect(done.events, hasLength(2));

    await startServer(_port);
    await Future.delayed(const Duration(seconds: 6));
    expect(await starts('done'), 0);
    expect(done.events, hasLength(2));
  }, timeout: timeout);

  test('does not revive a cancelled subscription', () async {
    await connect();
    final cancelled = subscribe('cancelled');
    await _until('first event', () => cancelled.events.isNotEmpty);
    await cancelled.subscription.cancel();
    await Future.delayed(const Duration(seconds: 1));

    await startServer(_port);
    await Future.delayed(const Duration(seconds: 6));
    expect(await starts('cancelled'), 0);
  }, timeout: timeout);

  test('resumes every open subscription on one socket', () async {
    await connect();
    final a = subscribe('a');
    final b = subscribe('b');
    await _until('first events', () => a.events.isNotEmpty && b.events.isNotEmpty);

    await startServer(_port);
    await _until('a reconnect', () => reconnects >= 1);
    await a.nextEvent('a');
    await b.nextEvent('b');
    expect(await starts('a'), 1);
    expect(await starts('b'), 1);
  }, timeout: timeout);

  test('a restart during connection_init subscribes once', () async {
    await connect(headers: () async => {'Ack-Delay': '3000'});
    final init = subscribe('init');
    await Future.delayed(const Duration(seconds: 1));

    await startServer(_port);
    await init.nextEvent('init');
    await Future.delayed(const Duration(seconds: 2));
    expect(await starts('init'), 1);
  }, timeout: timeout);

  test('gives up with a visible error', () async {
    await connect(maxAttempts: 2, maxDelay: const Duration(seconds: 1));
    final giveUp = subscribe('giveup');
    await _until('first event', () => giveUp.events.isNotEmpty);
    await killPort(_port);

    await _until('an error or an end after the reconnect attempts ran out',
        () => giveUp.error != null || giveUp.completed);
    expect(giveUp.error, isNotNull);
  }, timeout: timeout);
}
