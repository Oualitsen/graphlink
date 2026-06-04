# Real-Server Integration Tests

## Goal

Replace mock-based client integration tests with tests against a real Spring Boot GraphQL
server. Keep mock tests untouched — add real-server tests alongside them.

Upload tests are excluded (Spring for GraphQL cannot handle subscriptions + multipart on
the same server).

---

## Phase 1 — Spring Boot server (`integration_tests/spring_server/`) (done)

- Java 21, Gradle
- `spring-boot-starter-graphql` + WebSocket support
- Port **9999**
- Schema copied from `dart_client_tests/schema/schema.gql`, minus `Upload` scalar and
  upload mutations (`uploadOneFile`, `uploadFileList`)
- `DataFixtures.java` with same hardcoded data as the Kotlin/Java test fixtures
- Controllers:
  - `QueryController` — all Query resolvers returning fixture data
  - `MutationController` — all Mutation resolvers (non-upload)
  - `SubscriptionController` — `userCreated`, `userCreateds`, `userStatusChanged`
- Resolver lookup strategy: key by argument ID (e.g. `getUser("user-1")` → Alice,
  `getUser("user-2")` → Bob, unknown → GraphQL error)
- Makefile targets: `build`, `start`, `stop`, `ci`

---

## Phase 2 — Dart real-server tests (`integration_tests/dart_client_tests_real/`)

- Same structure as `dart_client_tests/` (`pubspec.yaml`, `config.json`, `lib/generate.dart`)
- Same `config.json` (same schema, same Dart client config)
- Tests use `DioAdapter("http://localhost:9999/graphql")` instead of mock
- Makefile: start server → generate → test → stop server
- No upload tests

---

## Phase 3+ — Java, TypeScript, Kotlin real-server tests (TS done)

Same pattern as Phase 2 for each client target. Planned but not yet started.

---

## Task list

- [ ] Phase 1: Create Spring Boot server project scaffold
- [ ] Phase 1: Write schema.graphqls (schema minus upload)
- [ ] Phase 1: Write DataFixtures + domain model classes
- [ ] Phase 1: Write QueryController
- [ ] Phase 1: Write MutationController
- [ ] Phase 1: Write SubscriptionController
- [ ] Phase 1: Run and verify server starts and responds correctly
- [ ] Phase 2: Create dart_real_server_tests project
- [ ] Phase 2: Write real-server Dart tests (queries, mutations, subscriptions)
- [ ] Phase 2: Wire Makefile (start server → generate → test → stop)
