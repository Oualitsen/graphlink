# Java reactive (RxJava 3, Mutiny): upload wire tests and reconnect tests — TODO

Follow-ups to the RxJava 3 / Mutiny REST and GraphQL real suites. Nothing here is started.

## 1. GraphQL multipart uploads over the wire (RxJava 3, Mutiny)

Gap: the GraphQL real suites upload through the test-only `RealMultipartAdapter` (reads whole files into memory).
The generated streaming multipart adapter for these two flavors has no wire-level test. Only Reactor has one
(`real/java_client_upload_reactor_tests_real`).

- [ ] Add `real/java_client_upload_rxjava3_tests_real` and `real/java_client_upload_mutiny_tests_real` (config, pubspec, pom with the flavor dependency, Makefile, `.gitignore`), modeled on `java_client_upload_tests_real` with the JDK adapter only (WebClient is Reactor-only).
- [ ] Register both in `real/generate_reactor_tests.dart` with `wrapInRx: true` (package `dev/graphlink/upload`); each package gets its own small `Rx.java` (`block`).
- [ ] Run the same tests as the other targets: 6 MB sha256, Content-Length for known length, chunked for unknown length, progress ends at the total, file not read in full before the first progress report, no progress when the length is unknown, two-file list.
- [ ] Run the env-gated Spring upload server tests too (`UPLOAD_SERVER_URL`, ports 9998/9991).
- [ ] Check the reactive multipart adapter is lazy: `executeMultipart` builds the request and calls `httpClient.sendAsync(...)` when the method is called, then bridges the future, so the upload may start before anyone subscribes. Add a test (nothing sent until subscribed); fix the generator if it fails.
- [ ] Mutation check: temporarily make the generated adapter buffer the body and confirm the no-read-ahead and chunked tests fail.
- [ ] Wire up: root `Makefile` targets (`java-upload-rxjava3-real`, `java-upload-mutiny-real`, `.PHONY`, `all-real`), CI jobs in `ci.yml` (and `integration-tests-real.yml` if the reactor upload job is listed there), `CLAUDE.md` uploads bullet.

## 2. Subscription reconnect tests (RxJava 3, Mutiny)

Gap: `SubscriptionReconnectTest` exists only for blocking and Reactor. It is a manual target (`reconnect-test`), excluded from CI.
The WebSocket adapter is shared, but the stream wrappers (`Observable.create`, `Multi.createFrom().emitter`) and their
cancel/error semantics are not tested across a server restart.

- [ ] Move the Reactor `SubscriptionReconnectTest` to `real/java_reactive_shared/` and make it flavor-neutral with `Rx.subscribe(...)`; drop the hand-written Reactor copy.
- [ ] Keep `SubscriptionReconnectTest.java` in the derive excludes for the derived copies (blocking listener version).
- [ ] Add a `reconnect-test` target to the RxJava 3 and Mutiny GraphQL real packages (needs `SERVER_JAR`).
- [ ] Cover the three existing cases on each flavor: stream resumes after the server is halted and restarted; subscribing before the server is available; `maxReconnectAttempts = null` retries indefinitely.
- [ ] Ports: the test uses fixed ports 9996, 9993 and 9988 and kills processes with `lsof`. Run the three flavors one after another, and not while REST suites that use those ports are running. Consider a per-flavor port offset.
- [ ] Decide whether this runs in CI (it spawns its own server JARs and takes minutes) or stays a manual target like the others. Default: manual, document it.
- [ ] `CLAUDE.md`: update the note that `SubscriptionReconnectTest` is blocking/Reactor only.

## Done when

- Both flavors pass the upload wire tests, with the mutation check failing as expected.
- Reconnect tests pass on both flavors locally; CI decision recorded.
- New CI jobs have run green on GitHub at least once.
