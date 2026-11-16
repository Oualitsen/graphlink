# server_integration_tests hardening — progress and findings

Autonomous run. Newest status at the top of each section.

## What was done

### 1. Harness (`scripts/`)
- `scripts/server.sh` + `scripts/server.mk`: one start/stop implementation for all six servers.
  - Start waits for a real readiness signal: an HTTP `{__typename}` query answered with 200, **and** a WebSocket
    upgrade (`101`) on `/graphql` (skipped with `SKIP_WS=1` for the upload server, which has no subscriptions).
  - Fails fast if the process dies before it is ready (prints the log tail) or after `READY_TIMEOUT` (300s).
  - Starts the server in its own process group and stops by killing that group (TERM, then KILL). This also
    takes down the JVM child of `gradlew bootRun`, which the old `kill $(cat pid)` missed.
  - Refuses to start when the port is held by a process it did not start (the old Makefiles `kill -9`'d whatever
    held the port). `FORCE_KILL_PORT=1` restores the old behaviour.
  - Log is `<server dir>/.server.log` instead of shared `/tmp/*.log` files, so parallel runs and reruns do not collide.
- All six server Makefiles now only set `NAME`, `PORT`, `START_CMD` and include `scripts/server.mk`.
  Replaces `sleep 2` (TS servers) and the WS-blind `curl` loop (Java/Kotlin).

### 2. Server fault suite (`server_faults/`)
- `cases.json`: malformed and hostile HTTP requests plus raw WebSocket protocol abuse (graphql-transport-ws).
- `run_faults.py`: stdlib-only runner, `run_faults.py <server> <port>`. Per case it checks status class, that a GraphQL
  `errors` array is returned, that no stack trace / file path leaks, and that the server still answers a valid query
  afterwards. Adds a 100-way concurrency check.
- `known_defects.json`: per-server defects not fixed yet, with the reason. A known defect that starts passing fails the run
  (remove the entry), same as the client suites.

## Bugs found (server side) and fixes

### Fixed in the generator (`express_apollo_server_*.dart`, covered by `test/server/express_apollo_hardening_test.dart`)

| # | Bug (found by) | Fix |
|---|---|---|
| 1 | Every GraphQL error response carried `extensions.stacktrace` with absolute file paths (all error cases) | `includeStacktraceInErrorResponses: false` in both `ApolloServer` variants |
| 2 | Malformed / `null` / string JSON body and oversized body (6 MB) got Express's HTML error page with a stack trace (`malformed_json`, `json_null_body`, `json_string_body`, `huge_body`) | `graphLinkErrorHandler` registered after the Apollo middleware: 400 / 413 / 500 with a `{"errors": [...]}` body and a fixed message |
| 3 | **Process crash**: one 15 KB query nested 300 levels deep ran Node out of memory (4 GB heap, `FATAL ERROR: Ineffective mark-compacts`), taking the server down for every client (`deep_query`) | `maxQueryDepth` (default 32, option on `GraphLinkServices`): an iterative depth check (follows fragments, cycle-safe) before validation. HTTP: `queryDepthGuard` middleware answers 400. WebSocket: `onSubscribe`. Throwing from an Apollo plugin hook was tried first and gives a masked 500, so it is a middleware |
| 4 | A subscription with a syntax error made `graphql-ws` close the socket with 4500 instead of sending an `error` message (`ws_query_syntax_error`) | the same `onSubscribe` returns the parse error |

Client suites re-run against the changed TS server: ts, dart, python, go all pass. The upload server regenerates, typechecks and passes its suite.

### Found, not fixed: Spring servers (Java MVC, Java reactive, Kotlin blocking, Kotlin suspend)
Listed in `server_faults/known_defects.json`. All come from Spring GraphQL itself, not from generated code, and fixing them means
generating extra Spring infrastructure (a `@ControllerAdvice`, a custom WebSocket handler). I did not add that without a decision.

| Case | Servers | What happens | Likely fix |
|---|---|---|---|
| `json_null_body` | all four | body `null` gives 500 (NPE in the handler) | `@ControllerAdvice` / filter returning 400 |
| `unknown_operation_name`, `ambiguous_operation` | reactive + both Kotlin (Java MVC answers correctly) | `graphql.execution.UnknownOperationException` escapes, 500 | `@ExceptionHandler(UnknownOperationException)` returning 400 |
| `ws_unknown_message_type`, `ws_invalid_json`, `ws_subscribe_without_payload` | all four | socket closed with 1011 instead of the protocol's 4400 | custom `WebSocketHandler` or upstream fix |
| `ws_unknown_variable_type` | all four | subscribe with an uncoercible variable never gets an answer (no `error`, no `complete`): the client waits forever | upstream issue; `WebGraphQlInterceptor` may catch it |

Passing on every server, worth knowing: no stack trace or path leaks, a failing resolver gives 200 with `errors`, invalid enum / missing
variable / Int overflow are rejected, 6 MB bodies, 2000 aliases and 100 parallel requests do not hurt the server.

### Harness bugs fixed along the way
- The old TS Makefiles used `sleep 2` as the readiness check; a slow start made the first client fail with a connection error.
- Java/Kotlin only checked that `/graphql` answered over HTTP, never that the WebSocket endpoint was up (subscription tests could race it).
- `kill $(cat .server.pid)` only killed the `gradlew` wrapper, not the JVM it spawned, so a stopped Java/Kotlin server could keep its port.
- Starting killed whatever listened on the port, including unrelated processes.
- A server that died mid-run was only visible as client connection errors; the readiness loop now reports the log tail if it dies at startup.
- Local aggregate targets (`make typescript`, `java`, `java-reactive`, `kotlin`) ran every client against one long-lived server whose data earlier clients had mutated. They now restart the server per client (CI jobs already ran one server per client).
- Local note: `servers/typescript_upload_server/node_modules` was a corrupt install (`@apollo/usage-reporting-protobuf` without `generated/`), so the server did not start. I deleted and reinstalled it. Not a repo change.

## New commands
- `make -C server_integration_tests faults` (all five servers) or `ci-faults-typescript|java|java-reactive|kotlin-blocking|kotlin-suspend`.
- `make ci` now also runs `ci-faults-typescript`.
- CI: new `server-faults` job (5 servers, not 35) in `.github/workflows/ci.yml`.
- Swift stays on the Java server only, as you decided.

## Not done / for your review
- Not covered: the TS upload server has no fault cases (its schema differs; `cases.json` targets the core schema).
- Not covered: batch-mapping size mismatches and resolvers that return null for a non-null field need server impls that misbehave on purpose.
- `CHANGELOG.md` has an "Unreleased" entry; I did not bump `pubspec.yaml` or open a PR.
- Query depth 32 is a default I chose; the matrix clients pass with it.
