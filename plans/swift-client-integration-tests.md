# Swift client integration tests — plan

Goal: bring the Swift client generator to parity with Kotlin's three-tier test
setup:

1. `integration_tests/swift_client_tests/` — mock-adapter assertion tests
   against `schema_mock`, mirroring `kotlin_client_tests/`.
2. `integration_tests/swift_client_tests_real/` — same test surface, but
   against the real running Spring Boot JAR (`schema_real`), mirroring
   `kotlin_client_tests_real/`.
3. `server_integration_tests/clients/swift_client/` — client-vs-server-matrix
   harness, mirroring `server_integration_tests/clients/kotlin_client/`.

Kotlin is the source pattern for all three (see file/dir references below).
Swift differs from Kotlin in one big way that simplifies phases 2 and 3: the
generated Swift client already ships real `Default*Adapter` implementations
(`DefaultGraphLinkURLSessionAdapter`, `DefaultGraphLinkURLSessionMultipartAdapter`,
`DefaultGraphLinkWebSocketAdapter`) plus a `GraphLinkClient.create(url:wsUrl:)`
convenience factory — so unlike Kotlin (which hand-writes `OkHttpGraphLinkClientAdapter`
etc.), the "real" test clients just call `.create(...)`, no custom adapter code needed.

## Toolchain finding (blocking infra fact)

This machine's active `xcode-select` toolchain is CommandLineTools-only, which
has **neither `XCTest` nor `swift-testing`** available — confirmed by probe
(`import XCTest` / `import Testing` both fail to resolve under plain `swift
test`). However `/Applications/Xcode.app` **is** installed, and setting
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per-invocation (no
global `xcode-select -s` change) makes `XCTest` resolve and `swift test` pass.
All new Swift Makefiles must run `swift test` with that env var prefixed
instead of assuming a bare `swift test` works. Do not run global
`xcode-select -s` — that's a shared system setting change, out of scope.

## Phase 0 — Test-target infra

- [x] Add `Tests/GraphLinkGeneratedTests/` target to
      `integration_tests/swift_client_tests/Package.swift`.
- [x] Add `pubspec.yaml` to `swift_client_tests/` (graphlink path dep) so
      `dart run ../generate.dart` resolves, matching Kotlin's.
- [x] Extend `swift_client_tests/Makefile` with `generate`/`test`/`ci`
      targets mirroring `kotlin_client_tests/Makefile` (using the
      `DEVELOPER_DIR` prefix on the `test` target).

## Progress log — ALL THREE PHASES COMPLETE

- Phase 0 infra done and verified (`swift test` green via `DEVELOPER_DIR`).
- Phase 1 COMPLETE: 218/218 tests green against the mock adapter.
- Built `spring_server`/`spring_upload_server` JARs (one-time ~3.5min Gradle
  build each) and ran them live on ports 9999/9998 — this unlocked real
  runtime verification (not just compile-checking) for phase 2.
- Phase 2 COMPLETE: 223/223 tests green against the live real server.
  `SubscriptionReconnectTest` intentionally skipped (stretch goal, not
  required for parity — matches original plan).
- Phase 3 COMPLETE: all 8 files compile cleanly (`swift build --build-tests`)
  against the real generated matrix-client API. Runtime pass/fail against
  the actual server matrix (TS/Java/Kotlin/Java-reactive servers) is left
  for a follow-up — those servers weren't built/started this pass, only the
  two `integration_tests/` Spring JARs were (see below).
- Servers shut down cleanly after verification (`actuator/shutdown` on both
  management ports).

## Phase 1 — `swift_client_tests` (mock, schema_mock)

Port from `integration_tests/kotlin_client_tests/client-app/src/test/kotlin/dev/graphlink/test/`:

- [x] `GraphLinkCall.swift` (equiv of `GraphLinkCall.kt`)
- [x] `MockAdapter.swift` (equiv of `MockAdapter.kt`) — closure-based since
      `GraphLinkClientAdapter` is `(Data) async throws -> Data`, not a protocol.
- [x] `MockMultipartAdapter.swift`
- [x] `MockWebSocketAdapter.swift`
- [x] `Fixtures.swift` (client factory + JSON fixtures)
- [x] `ScalarsTest.swift`
- [x] `NullabilityTest.swift`
- [x] `EnumsTest.swift`
- [x] `ListsTest.swift`
- [x] `NestedTypesTest.swift`
- [x] `CycleTest.swift`
- [x] `InputsTest.swift`
- [x] `QueriesTest.swift`
- [x] `QueryStringsTest.swift`
- [x] `MutationsTest.swift`
- [x] `CacheTest.swift`
- [x] `SubscriptionsTest.swift`
- [x] `UploadTest.swift`
- [x] `ErrorCaptureTest.swift`
- [x] `swift test` green (all files compile + pass) — iterate on real
      compiler/runtime errors as they surface.

## Phase 2 — `swift_client_tests_real` (real Spring Boot server, schema_real)

- [x] Scaffold dir: `Package.swift`, `config.json` (schema_real, wsAdapter
      urlsession), `Makefile` (start/stop server + upload server ports 9999/9998
      mgmt 9990/9991, matching Kotlin's), `pubspec.yaml`.
- [x] `Fixtures.swift` using `GraphLinkClient.create(url:wsUrl:)` for the real
      client (no hand-written adapter needed) — huge simplification vs Kotlin.
- [x] Port test files from `kotlin_client_tests_real` (same names as phase 1
      plus `DefaultValuesTest`, `GlExpandTest`, `NormalizationTest`); skip
      `SubscriptionReconnectTest` (stretch goal, not required for parity).
- [x] Wire into `integration_tests/Makefile`: add `swift`/`swift-real`
      targets, append to `all`/`all-real`.
- [x] `swift test` green against the real live server — 223/223 passing
      (verified after building + starting `spring_server`/`spring_upload_server`).

## Phase 3 — `server_integration_tests/clients/swift_client`

- [x] Scaffold: `Package.swift` (+ test target), `config.json` (schema/*.gql +
      queries.gql, wsAdapter urlsession), `Makefile` (`install` no-op,
      `generate`, `test` w/ `SERVER_PORT` env + `DEVELOPER_DIR`, `ci`).
- [x] `Fixtures.swift` reading `SERVER_PORT` env at runtime, feeding
      `GraphLinkClient.create(url:wsUrl:)`.
- [x] Port test files: `DefaultsTest`, `HoistArgsTest`, `InterceptTest`,
      `KeywordsTest`, `MutationsTest`, `NestingTest`, `QueriesTest`,
      `SubscriptionsTest`.
- [x] Append `swift` to `CLIENTS` in `server_integration_tests/Makefile`.
- [x] `swift build --build-tests` clean (0 errors) against the real
      generated matrix-client API.
- [x] Full runtime run against the java server: `make ci-java-client
      CLIENT=swift` from `server_integration_tests/` — 41/41 passing,
      server started/stopped cleanly. (Not run against the other 4 servers
      — see CI wiring below for why swift is scoped to java only.)

## Phase 4 — CI wiring (`.github/workflows/`)

Added Swift to CI: `ci.yml` (`swift-client`, `swift-real`,
`swift-vs-java-matrix-client` jobs) and `integration-tests-real.yml`
(`swift-real`). Verified via `act` (local GitHub Actions runner, Docker) for
every Linux job, and via direct local execution for every macOS job (`act`
only supports Linux containers, so macOS jobs can't be simulated — but the
exact commands were run and verified end-to-end on this real Xcode/macOS
machine instead).

- [x] `swift-client` job (mock tests vs `schema_mock`) — runs on
      `macos-latest`, not `ubuntu-latest` like every other client. Reason:
      Linux's `URLSessionWebSocketTask` (via swift-corelibs-foundation's
      `FoundationNetworking`) has real API gaps vs Darwin (different
      completion-handler shapes, missing overloads) — not worth chasing for
      a client whose actual target platform is iOS/macOS. Decided with the
      user after hitting several distinct Linux-only compile errors.
- [x] `swift-real` job (real-server tests vs `schema_real`) — same
      `macos-latest` reasoning, added to both `ci.yml` and
      `integration-tests-real.yml`.
- [x] `swift-vs-java-matrix-client` job — swift is deliberately **not**
      folded into the main 5-server `matrix` job (that would 5x one extra
      client's job count). Runs swift against the java server only, via
      `make ci-java-client CLIENT=swift`, on `macos-latest`.
- [x] `server_integration_tests/Makefile`'s `CLIENTS` var still includes
      `swift` (for local convenience — `make kotlin`/`make java` etc. — no
      Linux/Darwin Foundation issue there since only the CLIENT runs Swift,
      not the server); the *CI* matrix job's client list excludes it.

## Bugs found & fixed along the way

All in the Swift code generator (`lib/src/`), surfaced by cross-checking
generated output against a real Linux Swift 6.0 toolchain (via `act`) — none
of these were caught by the extensive macOS/Xcode 6.3 testing in phases 1-3,
since Swift 6.3 silently accepts syntax that strict/older toolchains reject:

1. **Trailing comma in parameter/argument lists** (`swift_code_gen_utils.dart`
   `initDecl`, `swift_serializer.dart` `_generateFromJson` /
   `generateToMappingMethod` / `generateFromMethod`) — every one of these
   unconditionally appended `,` to each element before joining with `\n`,
   producing a trailing comma before the closing `)`. Valid on Swift 6.1+
   (SE-0439) but a hard parse error before that. Fixed to only comma
   *between* elements.
2. **`URLSession` unavailable on Linux** — swift-corelibs-foundation moves
   `URLSession` into a separate `FoundationNetworking` module; plain
   `import Foundation` doesn't pull it in like it does on Darwin. Fixed by
   making `SwiftSerializer.serializeImport('Foundation')` also emit a
   `#if canImport(FoundationNetworking) import FoundationNetworking #endif`
   guard — harmless everywhere, required for the three `Default*Adapter`
   files that touch `URLSession`.
3. **`nil` needs a contextual type** in
   `task?.cancel(with: .normalClosure, reason: nil)` — ambiguous overload
   resolution on Linux's `URLSessionWebSocketTask.cancel`. Fixed with an
   explicit `nil as Data?`.
4. **Trailing-closure `send` call rejected on Linux** —
   `task?.send(.string(message)) { _ in }` hit "extra trailing closure
   passed in call" there. Fixed to the explicit
   `task?.send(.string(message), completionHandler: { _ in })` form, which
   both platforms accept.
5. Deeper, **not fixed** (led to the macOS-runner decision instead): further
   Linux-only errors in `DefaultGraphLinkWebSocketAdapter`'s `.receive`
   trailing closure and a `cancel(...)` call with an extra `completionHandler`
   argument that doesn't exist there — genuine API-shape differences in
   Linux's `URLSessionWebSocketTask`, not portable one-line fixes.

(One pre-existing, unrelated stray file — an out-of-argument-order
`InputsTest.swift` left over from a prior session — was fixed by a porting
agent as a drive-by during phase 1; not a generator bug.)

## Final counts

- `swift_client_tests` (mock): 218/218 passing (macOS + verified Linux-
  compile-clean via `act` post-fix)
- `swift_client_tests_real` (live server): 223/223 passing
- `server_integration_tests/clients/swift_client` vs java server: 41/41
  passing (real run, not just compile-check)
- CI: `swift-client`, `swift-real` (both workflow files),
  `swift-vs-java-matrix-client` all wired up and running on `macos-latest`
