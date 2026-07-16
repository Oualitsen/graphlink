# Kotlin client: dead `generatePayloadFile()` / hand-written `GraphLinkPayload` duplication

Found while building the Swift client generator and hitting a real `swift build`
"multiple producers" error caused by the same pattern (see
[`swift-client.md`](swift-client.md) and
[`swift_client_constants.dart`](../lib/src/serializers/client_serializers/swift/swift_client_constants.dart)
comment above `swiftGraphLinkCacheEntry`). Kotlin never hit the equivalent error only
because the duplicate-producing code path is dead — not because the duplication doesn't
exist.

## What's there

- [`kotlin_client_constants.dart:63`](../lib/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart#L63)
  defines `kotlinGraphLinkPayload`, a hand-written `data class GraphLinkPayload(...)`.
- [`kotlin_client_serializer.dart:639`](../lib/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart#L639)
  wraps it: `generatePayloadFile() => GLClassModel(body: kotlinGraphLinkPayload)`.
- **Neither is ever called.** `GraphLinkPayload` is also a synthetic grammar type, so
  [`kotlin_client_generator.dart`](../lib/src/generators/kotlin_client_generator.dart)'s
  `allProjectedTypes` loop (types + interfaces from `parser.projectedTypes` /
  `parser.projectedInterfaces`) already emits a real `GraphLinkPayload.kt` via the
  standard `KotlinSerializer` type-generation path. `generatePayloadFile()` has no call
  site anywhere in `kotlin_client_generator.dart` — the hand-written constant is
  unreachable dead code.
- Kotlin has no hand-written `GraphLinkError` constant at all — that one was only ever a
  Swift-specific mistake, not a Kotlin pattern.

## Why Kotlin never errored

Kotlin doesn't have a "duplicate top-level declaration" compile error the way Swift's
module-wide "multiple producers of X.swift" check does for two files independently
declaring `struct GraphLinkPayload` in the same target — since `generatePayloadFile()`
is simply never invoked, the hand-written constant sits unused in the constants file and
never reaches a `.kt` output file to conflict with the synthetic one. It's latent
duplication, not a live bug.

## Suggested cleanup (not yet done)

- Delete `kotlinGraphLinkPayload` from `kotlin_client_constants.dart:63-68`.
- Delete `generatePayloadFile()` from `kotlin_client_serializer.dart:639`.
- Confirm no other caller exists (`grep -rn generatePayloadFile lib/`) before removing.

Low priority / cosmetic — doesn't affect generated output today, just removes dead code
and a misleading precedent that could get copy-pasted into a future target (as it
temporarily was for Swift).
