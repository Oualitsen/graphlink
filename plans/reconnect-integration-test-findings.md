# Reconnect Integration Test — Debug Findings

## Summary

Ran the reconnect integration test (`dart_client_tests_real/test/subscriptions_test.dart`)
against the shared Spring server. The test SIGKILLs the server and verifies the Dart
WebSocket adapter reconnects and resumes the `counterTick` subscription. Found and fixed
three bugs in the test and two bugs in the generated adapter.

---

## Bugs found and fixed

### Bug 1: `lsof -ti :9999` returns the test's own PID (test)

`lsof -ti :9999` returns ALL processes with port 9999 open, including outbound
client connections. When the Dart VM's WebSocket connection to port 9999 appears
in the list, `kill -9` kills the test process itself (exit code 137).

**Fix:** use `-sTCP:LISTEN` to restrict to listening sockets only:

```dart
// Before
final lsof = await Process.run('lsof', ['-ti', ':9999']);

// After
final lsof = await Process.run('lsof', ['-ti', ':9999', '-sTCP:LISTEN']);
```

### Bug 2: `lsof -ti` can return multiple PIDs, `kill` gets a single multi-line argument (test)

`lsof -ti` output is `"40939\n40958"`. Passing this as a single string to
`Process.run('kill', ['-9', pid])` means `kill` receives one argument
`"40939\n40958"` instead of two separate PIDs. The kill fails silently (exit code 2).

**Fix:** split the output on newlines and kill each PID individually:

```dart
// Before
final pid = lsof.stdout.toString().trim();
if (pid.isNotEmpty) await Process.run('kill', ['-9', pid]);

// After
final pids = pidOutput.isEmpty ? <String>[] : pidOutput.split('\n');
for (final pid in pids) {
  if (pid.isNotEmpty) await Process.run('kill', ['-9', pid]);
}
```

### Bug 3: `_reconnect()` does not retry on failure (generated adapter)

When `_reconnect()` calls `_connectOnce()` and it fails (server not up yet), the
exception is caught but there's no retry. The reconnect gives up after one failed
attempt. The server takes ~1.5s to start, so the first reconnect attempt races the
server startup and usually loses.

**Fix:** wrap the connect attempt in a `while` loop with backoff. Keep trying until
success or `_maxReconnectAttempts` is exhausted:

```dart
// Before
Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    final delay = _backoffDelay(_reconnectAttempts);
    _reconnectAttempts++;
    await Future.delayed(delay);
    try {
      await _connectOnce();
      _reconnectAttempts = 0;
      _reconnectController.add(null);
    } catch (e) {
      // gives up — no retry
    }
}

// After
Future<void> _reconnect() async {
    _reconnecting = true;
    try {
      while (_reconnectAttempts < _maxReconnectAttempts) {
        final delay = _backoffDelay(_reconnectAttempts);
        _reconnectAttempts++;
        await Future.delayed(delay);
        try {
          await _connectOnce();
          _reconnectAttempts = 0;
          _reconnectController.add(null);
          return;
        } catch (e) {
          // loop continues to next attempt
        }
      }
    } finally {
      _reconnecting = false;
    }
}
```

### Bug 4: Race condition — two concurrent `_reconnect()` loops (generated adapter)

When a reconnect attempt fails, `_createConnection()` leaves `_channel` and
`_subscription` set on a failed WebSocket. That failed stream eventually fires
`_onError`, which calls `_reconnect()` **again** while the original `_reconnect()`
loop is still running. Two concurrent loops both establish connections, overwrite
each other's `_channel`, and the test's subscription gets broken by the replacement.

Two-part fix:

**4a.** In `_createConnection()`, clean up `_channel` and `_subscription` on failure
so the dead connection never fires `_onError`/`_onDone`:

```dart
} catch (e) {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;            // <— prevent stray _onError/_onDone
    _connectionCompleter?.completeError(e);
}
```

**4b.** Add a `_reconnecting` boolean guard. `_onError` and `_onDone` skip calling
`_reconnect()` if one is already in progress:

```dart
bool _reconnecting = false;

void _onError(Object error) {
    if (_subscription == null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && !_reconnecting) _reconnect();  // <— guard
}

void _onDone() {
    if (_subscription == null) return;
    final closeCode = _channel?.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && closeCode != 1000 && !_reconnecting) _reconnect();  // <— guard
}
```

### Bug 5: `_onReconnect()` does not re-send `subscribe` messages (generated client — NOT YET FIXED)

`_SubscriptionHandler._onReconnect()` re-does the graphql-ws handshake
(`connection_init` → `connection_ack`) but never re-sends the `subscribe` messages
for active subscriptions in `_payloads`. The server has no active subscription for
this client after reconnect, so no events flow.

The test currently times out at the "waiting for next tick after reconnect" step
because the subscription is never re-established server-side.

**Required fix** (in the serializer that generates `_SubscriptionHandler`):

After the handshake succeeds in `_onReconnect()`, iterate `_payloads` and re-send
`subscribe` messages:

```dart
final sink = await _doHandshake();
completer?.complete(sink);
// Re-send subscribe messages for all active subscriptions
for (final entry in _payloads.entries) {
    final msg = GraphLinkSubscriptionMessage(
        id: entry.key,
        type: GraphqlWsMessageTypes.subscribe,
        payload: GraphLinkSubscriptionPayload(
          query: entry.value.query,
          operationName: entry.value.operationName,
          variables: entry.value.variables,
        ));
    await sink.sendMessage(json.encode(msg.toJson()));
}
```

---

## What still needs to be done

- [ ] **Serializer fix — adapter**: Backport bugs 3, 4a, 4b from the adapter code
      in the appendix below into the serializer that generates
      `graph_link_websocket_adapter.dart`.
- [ ] **Serializer fix — client**: Backport bug 5 into the serializer that generates
      `_SubscriptionHandler._onReconnect()` in `graph_link_client.dart`.
- [ ] **Test fix**: Backport bugs 1 and 2 into `subscriptions_test.dart` (already
      applied to the working copy).
- [ ] **Re-run**: Once serializer fixes are in place, regenerate and re-run the test.
- [ ] **Remove debug prints**: Strip all `DIAG:` and `TEST:` print statements from
      generated code and test before merging.

---

## Files modified during debugging

| File | Status |
|---|---|
| `integration_tests/dart_client_tests_real/test/subscriptions_test.dart` | Debug prints + fixes applied (bugs 1, 2) |
| `integration_tests/dart_client_tests_real/lib/generated/client/graph_link_websocket_adapter.dart` | Debug prints + fixes applied (bugs 3, 4a, 4b) |
| `integration_tests/dart_client_tests_real/lib/generated/client/graph_link_client.dart` | Bug 5 identified but NOT fixed (generated code) |

---

## Adapter debug output trace (after bugs 1-4 fixed)

```
DIAG: _createConnection connecting to ws://localhost:9999/graphql
TEST: waiting for first tick...
DIAG: _createConnection connected
TEST: first tick received
TEST: lsof found server pids=[41169]
TEST: kill -9 41169 exit=0
DIAG: _onDone called, closeCode=1005, _reconnecting=false
DIAG: _onDone calling _reconnect()
DIAG: _reconnect() enter, _reconnectAttempts=0
DIAG: _reconnect attempt 1, delay=1070ms
TEST: after kill, port 9999 pids=""
TEST: starting new server...
TEST: new server PID 41195
TEST: waiting for onReconnect...
DIAG: _createConnection connecting to ws://localhost:9999/graphql
DIAG: _onError called, error=Connection refused, _reconnecting=true
DIAG: _onError skipping reconnect: reconnect=true _reconnecting=true  ← guard works
DIAG: _createConnection error: Connection refused
DIAG: _reconnect attempt 1 FAILED: Connection refused
DIAG: _reconnect attempt 2, delay=2289ms
DIAG: _createConnection connecting to ws://localhost:9999/graphql
DIAG: _createConnection connected
DIAG: _reconnect success, onReconnect fired
TEST: onReconnect received, waiting for next tick...
        ← times out here — Bug 5: subscribe messages never re-sent
```

---

## Appendix: Fixed adapter with debug prints

Copy of `graph_link_websocket_adapter.dart` with bugs 3, 4a, and 4b applied.
Debug prints kept for re-verification after serializer backport.

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND. ANY MODIFICATION WILL BE LOST ON NEXT GENERATION
// Generated by GraphLink dev
// GitHub: https://github.com/Oualitsen/graphlink
// Site: https://graphlink.dev
// Pub.dev https://pub.dev/packages/graphlink
// ignore_for_file: use_rethrow_when_possible, camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names, no_leading_underscores_for_local_identifiers, unused_local_variable, annotate_overrides, library_private_types_in_public_api

import 'dart:async';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'graph_link_client.dart';

class DefaultGraphLinkWebSocketAdapter extends GraphLinkWebSocketAdapter {
  final String url;
  final Future<Map<String, String>?> Function()? headersProvider;
  final bool reconnect;

  WebSocketChannel? _channel;
  final _messageController = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _connectionCompleter;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static final Random _random = Random();

  DefaultGraphLinkWebSocketAdapter({
    required this.url,
    this.headersProvider,
    this.reconnect = true,
  });

  @override
  Future<void> connect() async {
    await _connectOnce();
  }

  Future<void> _connectOnce() {
    if (_channel != null) return _channel!.ready;
    if (_connectionCompleter != null) return _connectionCompleter!.future;
    _connectionCompleter = Completer<void>();
    _createConnection();
    return _connectionCompleter!.future;
  }

  Future<void> _createConnection() async {
    try {
      print('DIAG: _createConnection connecting to $url');
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) => _messageController.add(data as String),
        onError: _onError,
        onDone: _onDone,
      );
      await _channel!.ready;
      print('DIAG: _createConnection connected');
      _connectionCompleter?.complete();
    } catch (e) {
      print('DIAG: _createConnection error: $e');
      // Clean up the failed channel so it doesn't trigger _onError/_onDone later
      _subscription?.cancel();
      _subscription = null;
      _channel = null;
      _connectionCompleter?.completeError(e);
    } finally {
      _connectionCompleter = null;
    }
  }

  void _onError(Object error) {
    print('DIAG: _onError called, error=$error, _subscription=$_subscription, _reconnecting=$_reconnecting');
    if (_subscription == null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && !_reconnecting) { print('DIAG: _onError calling _reconnect()'); _reconnect(); }
    else { print('DIAG: _onError skipping reconnect: reconnect=$reconnect _reconnecting=$_reconnecting'); }
  }

  void _onDone() {
    print('DIAG: _onDone called, _subscription=$_subscription, closeCode=${_channel?.closeCode}, _reconnecting=$_reconnecting');
    if (_subscription == null) return;
    final closeCode = _channel?.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && closeCode != 1000 && !_reconnecting) { print('DIAG: _onDone calling _reconnect()'); _reconnect(); }
    else { print('DIAG: _onDone skipping reconnect: reconnect=$reconnect closeCode=$closeCode _reconnecting=$_reconnecting'); }
  }

  Future<void> _reconnect() async {
    print('DIAG: _reconnect() enter, _reconnectAttempts=$_reconnectAttempts');
    _reconnecting = true;
    try {
      while (_reconnectAttempts < _maxReconnectAttempts) {
        final delay = _backoffDelay(_reconnectAttempts);
        _reconnectAttempts++;
        print('DIAG: _reconnect attempt $_reconnectAttempts, delay=${delay.inMilliseconds}ms');
        await Future.delayed(delay);
        try {
          await _connectOnce();
          _reconnectAttempts = 0;
          _reconnectController.add(null);
          print('DIAG: _reconnect success, onReconnect fired');
          return;
        } catch (e) {
          print('DIAG: _reconnect attempt $_reconnectAttempts FAILED: $e');
        }
      }
      print('DIAG: _reconnect max attempts ($_maxReconnectAttempts) reached');
    } finally {
      _reconnecting = false;
    }
  }

  Duration _backoffDelay(int attempt) {
    final exp = min(_initialDelay.inMilliseconds * pow(2, attempt), _maxDelay.inMilliseconds);
    final jitter = _random.nextInt(1000);
    return Duration(milliseconds: exp.toInt() + jitter);
  }

  @override
  Stream<String> get onMessageStream => _messageController.stream;

  @override
  Stream<void> get onReconnect => _reconnectController.stream;

  @override
  Future<Map<String, dynamic>?> connectionInitPayload() async {
    final headers = await headersProvider?.call();
    if (headers == null || headers.isEmpty) return null;
    return headers;
  }

  @override
  Future<void> sendMessage(String message) async {
    if (_channel == null) throw StateError('WebSocket is not connected');
    _channel!.sink.add(message);
  }

  @override
  Future<void> close() async {
    _reconnectAttempts = 0;
    _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'normal closure');
    _channel = null;
  }
}
```
