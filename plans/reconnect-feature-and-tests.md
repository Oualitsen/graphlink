# WebSocket Subscription Reconnect — Feature Design & Test Guide

This document describes everything needed to port the reconnect feature tests to the
TypeScript, Java, and Kotlin clients. It covers the full design: what was built, why
each decision was made, and the exact test scenarios to reproduce.

---

## 1. What was built

Two orthogonal pieces of work:

### 1a. `DefaultGraphLinkWebSocketAdapter` — reconnect engine

Located in the generated file `graph_link_websocket_adapter.dart` (emitted by
`lib/src/serializers/client_serializers/dart_client_constants.dart`,
`defaultWebSocketAdapter` constant).

**New constructor parameters**

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `maxReconnectAttempts` | `int?` | `10` | Max attempts before giving up. `null` = retry forever. |
| `maxReconnectDelay` | `Duration` | `30 s` | Backoff ceiling. Once reached, retries at this fixed interval. |

**Public getter**

```dart
int get reconnectAttempts => _reconnectAttempts;
```

Exposes the internal `_reconnectAttempts` counter so tests can poll it directly
without needing a mock server or external TCP sink to count connection events.

**Reconnect algorithm**

Exponential backoff with jitter:
```
delay(attempt) = min(1000ms * 2^attempt, maxReconnectDelay) + rand(0..999ms)
```

Attempt 0 → ~1 s, attempt 1 → ~2 s, … plateaus at `maxReconnectDelay`.

After a successful reconnect `_reconnectAttempts` resets to 0, so the backoff
restarts from the beginning on the next drop.

**`_disposed` flag** — set by `close()`, checked:
- At the top of each loop iteration
- Immediately after `Future.delayed` returns (so the loop exits without
  attempting one more connect after `close()`)
- In `_onError` / `_onDone` / `_createConnection` catch (prevents a new
  reconnect loop from starting after `close()`)

**Initial-failure reconnect** — before this feature, if the server was off when
`connect()` was first called, `_createConnection()` failed the completer and
stopped. No reconnect was triggered. Fix: the `catch` block of
`_createConnection()` now calls `_reconnect()` (with the same `!_disposed &&
!_reconnecting` guard used by `_onError`/`_onDone`). This unifies the
"live drop" and "server off at startup" code paths.

**`close()` behaviour** — sets `_disposed = true` before tearing down the
channel. The reconnect loop will exit on its next iteration (after the current
`Future.delayed` completes — worst case `maxReconnectDelay` + jitter).

---

### 1b. `_SubscriptionHandler` — payload survival across failures

Located in the same file, `dartSubscriptionHandler` constant.

**Problem that was fixed**

When the initial `_initWs()` future rejected (server off), the `catchError`
called `_removeController(uuid)` which wiped `_payloads[uuid]` and closed the
stream controller. When reconnect eventually fired, `_payloads.isEmpty` was
true and `_onReconnect` returned early — nothing was re-subscribed.

**Fix 1 — `handle()` catchError**

Changed from:
```dart
.catchError((e) {
  controller.addError(e);
  _removeController(uuid);   // ← deleted _payloads[uuid] and closed controller
});
```
To:
```dart
.catchError((e) {
  controller.addError(e);
  _subs.remove(uuid)?.cancel();
  // _payloads[uuid] and _map[uuid] stay alive for _onReconnect
});
```

**Fix 2 — `_onReconnect()` re-establishes listeners**

After a successful reconnect + handshake, for each entry in `_payloads`:
1. If `_subs` does not already contain that uuid (listener was cancelled by the
   catchError), create a new broadcast-stream listener and store it in `_subs`.
2. Send the `subscribe` message.

```dart
for (final entry in _payloads.entries) {
  final id = entry.key;
  if (!_subs.containsKey(id)) {
    final sub = sink.stream
        .map(_parseEvent)
        .where((event) => event.id == id)
        .listen((msg) => _handleMessage(msg, id));
    _subs[id] = sub;
  }
  // send subscribe message …
}
```

---

## 2. Spring Boot test server

**Location:** `integration_tests/spring_server/`

**Relevant subscription:** `counterTick: Int!`

Emits an incrementing integer (starting from 1) every 1 second via
`Flux.interval(Duration.ofSeconds(1)).map(i -> i.intValue() + 1)`.

The server is a standard Spring Boot + Spring for GraphQL app. Nothing special
is needed server-side for the reconnect tests — the test harness kills and
restarts the JVM externally.

**`counterTickRestart` was removed.** It was a server-side self-restart
mechanism that turned out to be unnecessary once the test harness could
kill/restart the server externally.

**Schema (relevant excerpt):**
```graphql
type Subscription {
  counterTick: Int!
}
```

**Build:** `cd integration_tests/spring_server && ./gradlew bootJar`
produces `build/libs/graphlink-test-server-0.0.1.jar`.

**Starting on a custom port:**
```bash
java -jar graphlink-test-server-0.0.1.jar --server.port=9996
```

---

## 3. Test infrastructure (`real_server_adapter.dart`)

Three utility functions used by both reconnect tests:

```dart
/// Kill only the process LISTENING on [port].
/// IMPORTANT: use -sTCP:LISTEN — without it lsof returns client connections
/// too (including the Dart test process itself), killing the test.
Future<void> killPort(int port) async {
  await Process.run('bash',
      ['-c', 'lsof -ti :$port -sTCP:LISTEN | xargs kill -9 2>/dev/null || true']);
  await Future.delayed(const Duration(milliseconds: 500));
}

/// Kill port, start JAR on that port, poll until TCP port accepts connections.
Future<void> startServer(int port) async {
  await killPort(port);
  final process = await Process.start('java', ['-jar', _jarPath(), '--server.port=$port']);
  unawaited(process.stdout.drain());
  unawaited(process.stderr.drain());
  await _waitForPort(port);
}

/// Poll TCP until port accepts connections (replaces blind sleep).
Future<void> _waitForPort(int port, {timeout = 20 s}) async { … }
```

The `-sTCP:LISTEN` flag on `lsof` is critical. Without it:
- `lsof -ti :9996` returns every process that has a socket on port 9996 —
  including the test process (connected as a WebSocket client).
- `xargs kill -9` then kills the test process mid-run.

Port assignments used in the Dart tests:
- `9996` — test 1 (server halts during active subscription)
- `9997` — test 2 (subscribe before server starts)

These are separate from the main integration-test server (`9999`) so the two
test groups can run independently without interfering with other tests.

---

## 4. Test scenarios

All three tests live in
`integration_tests/dart_client_tests_real/test/subscription_reconnect_test.dart`.
**Use this file as the canonical reference when porting tests to other languages.**
It shows the exact flow, assertion strategy, and server lifecycle management for
each scenario.

---

### Scenario 1 — Server halts during an active subscription

**Setup:** server is running on port 9996.

**Flow:**
1. Subscribe to `counterTick`.
2. Collect ticks in a `Set<int>` (set is used, not list, to detect duplicates).
3. When `tick == stopAt - 1` (tick 4 in the Dart test), call `startServer(port)`:
   - `killPort` kills the listening process with `kill -9` (LISTEN only — test
     process is safe).
   - JVM restarts; `_waitForPort` polls until TCP is ready.
4. Adapter detects the dropped connection (`_onDone`) → `_reconnect()` fires.
5. Once the new server is ready, reconnect succeeds → `onReconnect` fires.
6. Handler re-does graphql-ws handshake, re-sends `subscribe`.
7. New server starts emitting from tick 1 again.
8. When tick 1 arrives and is already in the set → duplicate detected → test
   completes.

**Assertions:**
```dart
expect(reconnected, isTrue);           // onReconnect fired
expect(eventSet, containsAll([1, 2, 3, stopAt - 1]));  // ticks before halt
// (implicit: test completed = duplicate tick received after reconnect)
```

**Key detail:** `startServer` is called at `stopAt - 1`, not `stopAt`, to give
the new JVM a head start. By the time the adapter detects the drop (connection
loss is async), the new server is already starting.

---

### Scenario 2 — Subscribe before the server is up

**Setup:** server is explicitly killed before the test starts (`setUpAll`).

**Flow:**
1. Subscribe to `counterTick` — server is off.
2. Adapter calls `connect()` → `_createConnection()` fails immediately.
3. Fix: `_createConnection()` catch now calls `_reconnect()`.
4. Fix: `handle()` catchError does NOT remove `_payloads[uuid]` — keeps it alive.
5. Call `startServer(port)` — takes ~8–10 s (JVM startup).
6. By the time `startServer` returns, the adapter has already failed at least
   one reconnect attempt (first backoff is ~1 s).
7. Adapter connects to the now-ready server → `onReconnect` fires.
8. Handler re-establishes the stream listener (it was cancelled in step 4's
   catchError) and sends `subscribe`.
9. First tick arrives → test completes.

**Assertions:**
```dart
expect(tick, greaterThan(0));  // received at least one tick
expect(reconnected, isTrue);   // onReconnect fired
```

**Key detail:** no artificial delay is needed before `startServer`. The JVM
startup itself (~8–10 s) guarantees the adapter will have attempted and failed
at least once.

---

---

### Scenario 3 — `maxReconnectAttempts: null` retries indefinitely

**Setup:** server is explicitly killed before the test starts. No server is started
at any point during the test.

**Flow:**
1. Create the adapter with `maxReconnectAttempts: null` and
   `maxReconnectDelay: Duration(seconds: 2)` (keeps the test fast).
2. Subscribe to `counterTick` — adapter starts the reconnect loop immediately.
3. Poll `adapter.reconnectAttempts` every 500 ms until it reaches 10.
4. Assert success — the adapter never gave up.

**Why `maxReconnectDelay: 2s`:** with exponential backoff capped at 2 s + up to
1 s of jitter, each attempt takes ~2–3 s. Reaching 10 attempts takes ~17–26 s,
well within a 2-minute timeout.

**No Spring server involved.** The server stays down for the entire test.
The adapter simply keeps incrementing `_reconnectAttempts` every loop iteration.

**Assertions:**
```dart
expect(ws.reconnectAttempts, greaterThanOrEqualTo(10));
expect(reconnected, isFalse);   // never successfully connected
```

**Key detail:** `reconnectAttempts` resets to 0 on a successful connect, so this
getter only remains > 0 while the adapter is still failing — which is exactly the
condition being tested.

---

## 5. What each client needs to implement

To port these tests to TypeScript, Java, or Kotlin clients:

### 5a. Adapter requirements

The client's WebSocket adapter must expose:
- A reconnect-with-backoff mechanism (configurable max attempts + max delay).
  - `maxReconnectAttempts: null` means retry forever (no cap).
- An `onReconnect` event/callback that fires after each successful reconnect.
- A `_disposed`-equivalent guard so `close()` stops the reconnect loop.
- Initial-connection failures must trigger the same reconnect path as live drops.
- A public `reconnectAttempts` getter (read-only) that exposes the internal
  attempt counter so tests can poll it without a mock server.

### 5b. Handler requirements

The subscription handler must:
- Keep the payload (query + variables) alive across connection failures so it
  can re-subscribe after reconnect.
- Re-send `subscribe` messages and re-establish stream listeners in the
  reconnect callback.
- NOT clean up payloads when `_initWs()` rejects (only clean up on explicit
  cancel).

### 5c. Server

Same Spring Boot server. Start it on a port that doesn't conflict with the
shared integration-test server (9999) or upload server (9998). Suggested ports:

| Client | Test 1 port | Test 2 port | Test 3 port |
|---|---|---|---|
| Dart (done) | 9996 | 9997 | 9994 (no server) |
| TypeScript | 9993 | 9995 | 9992 (no server) |
| Java | 9989 | 9991 | 9988 (no server) |
| Kotlin | 9985 | 9987 | 9984 (no server) |

Test 3 ports are marked "no server" as a reminder that no Spring server is
started — the adapter simply retries against a closed port.

### 5d. Test utilities

Port `killPort` / `startServer` / `_waitForPort` to each language's test runner.
The shell command stays the same:
```bash
lsof -ti :PORT -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
java -jar path/to/jar --server.port=PORT
```
`_waitForPort` just opens a TCP socket in a loop with a 500 ms sleep and a 20 s
deadline.

### 5e. Test assertions (language-agnostic)

**Scenario 1 (mid-run halt):**
- `reconnected == true` after the server is killed and restarted.
- Ticks 1 through `stopAt - 1` were received before the kill.
- At least one tick was received after reconnect (duplicate tick detection or
  simply awaiting the next event after `onReconnect`).

**Scenario 2 (subscribe before server starts):**
- At least one tick > 0 was received.
- `reconnected == true`.

**Scenario 3 (`maxReconnectAttempts: null` — no server, poll attempt counter):**
- Create adapter with `maxReconnectAttempts: null`, `maxReconnectDelay: 2 s`.
- Subscribe while server is down. Poll `adapter.reconnectAttempts` every 500 ms.
- Test passes when `reconnectAttempts >= 10`.
- `reconnected == false` (never successfully connected).
- No Spring server is started at any point.

---

## 6. Bug index (for reference)

| Bug | Symptom | Fix |
|---|---|---|
| `lsof` without `-sTCP:LISTEN` | Test process killed mid-run | Add `-sTCP:LISTEN` to restrict to the listener PID |
| `_createConnection` catch didn't call `_reconnect()` | "subscribe before server starts" never reconnected | Call `_reconnect()` in catch (same guard as `_onError`/`_onDone`) |
| `_removeController` called in `handle()` catchError | `_payloads` empty when `_onReconnect` fired | Only cancel `_subs[uuid]`; keep `_payloads` and `_map` |
| `_onReconnect` didn't re-establish listeners | Events from new server never reached stream controller | Re-add listener to `_subs` in `_onReconnect` loop if not present |
| No `_disposed` flag | `close()` didn't stop infinite reconnect loop | Set `_disposed = true` in `close()`; check in loop condition and after each `Future.delayed` |
| `URI is not hierarchical` in Spring `scheduleRestart` | Server couldn't restart itself (nested JAR URI) | Resolved (then removed entirely — external kill is simpler) |
