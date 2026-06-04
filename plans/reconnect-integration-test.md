# Subscription Reconnect Integration Test

## Goal

Add an end-to-end test that verifies the Dart client automatically reconnects and
resumes a subscription after a server-side connection drop.

---

## Why a separate Spring server

The existing `integration_tests/spring_server/` is the shared backend for all real-server
integration tests. Wiring session tracking into it requires subclassing
`GraphQlWebSocketHandler`, which couples test-only infrastructure into the shared server.

Decision: create a **dedicated Spring Boot project** (e.g.
`integration_tests/spring_server_reconnect/`) for the reconnect scenario only.
The shared server stays untouched.

---

## Test flow

```
1. Client opens WebSocket, subscribes to counterTick
2. Receive first tick — confirms subscription is live
3. POST http://localhost:<port>/test/disconnect-ws
4. Await ws.onReconnect.first (timeout 15 s) — confirms adapter detected the
   drop and reconnected
5. Await next tick from the existing stream (timeout 15 s) — confirms
   re-subscription was re-established
6. Assert both events arrived with valid data
```

The close code sent by the server must be **non-1000** (use `1001 Going Away`)
so that `DefaultGraphLinkWebSocketAdapter._onDone` triggers the reconnect path
(it skips reconnect when `closeCode == 1000`).

---

## Dart client reconnect behaviour (verified manually)

`DefaultGraphLinkWebSocketAdapter` (`graph_link_websocket_adapter.dart`):
- Detects close via `_onDone` / `_onError`
- Reconnects with exponential backoff: `min(1000ms * 2^attempt, 30s) + jitter`
- After successful reconnect fires `onReconnect` stream
- Max 10 reconnect attempts

`_SubscriptionHandler._onReconnect()` (`graph_link_client.dart` ~line 1892):
- Re-does the graphql-ws handshake (`connection_init` → `connection_ack`)
- Re-sends `subscribe` messages for all entries in `_payloads`
- Existing stream controllers continue to receive events

---

## Dedicated Spring server — what to build

### Schema (`schema.graphqls`)

Minimal schema — only what the reconnect test needs:

```graphql
type Subscription {
  counterTick: Int!
}
```

`counterTick` emits `0, 1, 2, …` every 500 ms via `Flux.interval`. After a
reconnect, the server-side flux restarts from 0. The test only checks that
events arrive, not their specific values.

### Session tracking

Spring for GraphQL (WebMVC) does not expose `WebSocketSession` through
interceptors or `DataFetchingEnvironment`. The only hook is
`WebSocketHandler.afterConnectionEstablished`.

**Approach**: subclass `GraphQlWebSocketHandler` and override the two lifecycle
hooks. Providing this subclass as a `@Bean` in user `@Configuration` satisfies
the auto-config's `@ConditionalOnMissingBean(GraphQlWebSocketHandler.class)`,
so the auto-configured handler is never created and Spring for GraphQL uses the
subclass transparently.

#### `GraphQlWebSocketHandler` constructor (spring-graphql 1.3.3 / Spring Boot 3.4.1)

```java
new GraphQlWebSocketHandler(
    WebGraphQlHandler webGraphQlHandler,
    HttpMessageConverter<?> converter,
    Duration initTimeoutDuration,
    Duration keepAliveDuration
)
```

Found by decompiling
`spring-boot-autoconfigure-3.4.1.jar!GraphQlWebMvcAutoConfiguration$WebSocketConfiguration`.

The auto-config bean method that gets replaced:

```java
// GraphQlWebMvcAutoConfiguration.WebSocketConfiguration
@Bean
@ConditionalOnMissingBean
public GraphQlWebSocketHandler graphQlWebSocketHandler(
    WebGraphQlHandler webGraphQlHandler,
    GraphQlProperties properties,
    HttpMessageConverters httpMessageConverters) { ... }
```

#### `TestWebSocketConfig` (user `@Configuration`)

```java
@Bean
public GraphQlWebSocketHandler graphQlWebSocketHandler(
        WebGraphQlHandler webGraphQlHandler,
        GraphQlProperties properties,
        HttpMessageConverters httpMessageConverters,
        WebSocketSessionRegistry registry) {

    HttpMessageConverter<?> converter = httpMessageConverters.getConverters().stream()
            .filter(c -> c.getSupportedMediaTypes().stream()
                    .anyMatch(mt -> mt.isCompatibleWith(MediaType.APPLICATION_JSON)))
            .findFirst()
            .orElseThrow();

    return new TrackingGraphQlWebSocketHandler(
            webGraphQlHandler,
            converter,
            properties.getWebsocket().getConnectionInitTimeout(),
            Duration.ZERO,   // keepAlive — ZERO disables server-side pings
            registry);
}
```

#### `TrackingGraphQlWebSocketHandler`

```java
public class TrackingGraphQlWebSocketHandler extends GraphQlWebSocketHandler {
    private final WebSocketSessionRegistry registry;

    // constructor calls super(webGraphQlHandler, converter, initTimeout, keepAlive)

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {  // no throws
        registry.register(session);
        super.afterConnectionEstablished(session);
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {  // no throws
        registry.unregister(session.getId());
        super.afterConnectionClosed(session, status);
    }
}
```

Note: the parent overrides do **not** declare `throws Exception` — compile error
if you add it to the override signatures.

#### `WebSocketSessionRegistry`

```java
@Component
public class WebSocketSessionRegistry {
    private final Map<String, WebSocketSession> sessions = new ConcurrentHashMap<>();

    public void register(WebSocketSession session) { ... }
    public void unregister(String sessionId) { ... }
    public void closeAll() {
        sessions.values().forEach(s -> {
            if (s.isOpen()) try { s.close(CloseStatus.GOING_AWAY); } catch (Exception ignored) {}
        });
        sessions.clear();
    }
}
```

### `TestController`

```java
@RestController
@RequestMapping("/test")
public class TestController {
    @PostMapping("/disconnect-ws")
    public ResponseEntity<Void> disconnectAll() {
        sessionRegistry.closeAll();
        return ResponseEntity.ok().build();
    }
}
```

---

## Dart test sketch (`subscriptions_test.dart`)

```dart
group('reconnect', () {
  test('counterTick resumes after server-side disconnect', () async {
    final ws = newWsAdapter();        // DefaultGraphLinkWebSocketAdapter
    final client = GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
    final reconnectUrl = 'http://localhost:<reconnect_port>/test/disconnect-ws';
    try {
      final stream = client.subscriptions.counterTick();

      // confirm subscription is live
      await stream.first.timeout(const Duration(seconds: 5));

      // force the server to drop the connection
      await http.post(Uri.parse(reconnectUrl));

      // adapter must detect the drop and reconnect
      await ws.onReconnect.first.timeout(const Duration(seconds: 15));

      // stream must resume
      await stream.first.timeout(const Duration(seconds: 15));
    } finally {
      await ws.close();
    }
  });
});
```

`newWsAdapter()` is already defined in `real_server_adapter.dart` — point it at
the reconnect server's port.

---

## What still needs to be done

- [ ] Create `integration_tests/spring_server_reconnect/` (Gradle, Java 21)
- [ ] Write the minimal schema + `counterTick` resolver
- [ ] Implement `WebSocketSessionRegistry`, `TrackingGraphQlWebSocketHandler`,
      `TestWebSocketConfig`, `TestController`
- [ ] Verify server starts and `POST /test/disconnect-ws` drops WebSocket connections
- [ ] Add `counterTick` to the shared `schema.graphqls` (and regenerate Dart client)
- [ ] Write the Dart reconnect test in `dart_client_tests_real/test/subscriptions_test.dart`
- [ ] Wire a Makefile target: start reconnect server → run reconnect test → stop server
