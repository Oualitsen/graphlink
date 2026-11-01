# Persisted Queries — Manifest

Status: **proposal, no code**. Builds on `plans/persisted-queries.md` (APQ, shipped in 5.6.0).

## Goal

Avoid the first-request retry. The generator writes a JSON file listing every persisted operation with its hash; a server loads it at
startup so the hash is already known when the first client request arrives.

The manifest is language agnostic and **needs no client change**. Clients keep the APQ protocol exactly as is, including the retry with
the text on `PersistedQueryNotFound`. Whether a server also refuses unlisted queries is the server's policy, not the client's.

## Config

A manifest output path, e.g. `persistedQueriesManifest: "persisted-queries.json"`. Requires `persistedQueries: "apq"` (same rule as
`persistedQueriesUseGet`). `persistedQueries` itself keeps its values `false | "apq"`.

## What goes in it

- Every operation the client would hash: those whose final text reaches the threshold (144 chars). Shorter ones are sent in full and have
  no first retry to avoid.
- `@glCache` operations: the full operation plus each single-element subset, so `n + 1` entries for `n` cached elements (not `2^n - 1`).
  Any other combination is simply not pre-warmed and falls back to the normal retry.

## Format

Apollo's operation manifest, so it can be published with `rover persisted-queries publish`:

```json
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    { "id": "<sha256 hex>", "name": "GetUser", "type": "query", "body": "query GetUser($id: ID!) { ... }" }
  ]
}
```

Documented by example only (Rover, GraphOS safelisting and Apollo Client docs); no formal schema or JSON schema is published.

- `id`: SHA-256 hex of `body`. `type`: `query | mutation | subscription`. `body`: the full operation text, fragments included.
- `clientName` is optional per operation; Apollo's own `generate` does not write it. We omit it.
- Publishing the same `id` with different content fails the whole publish; otherwise publishing is additive.
- Not verified: that `rover persisted-queries publish` accepts our file unchanged. Check with a real publish before release.

## The one real risk: generator text must equal client text

Clients hash at runtime over the assembled string (fragments appended, `@glCache` partials merged). The generator must produce the same
string, or the manifest holds hashes the client never sends (harmless: the retry still works, the benefit is lost silently).

- Do not re-implement the assembly: extract it into one function in the IR layer used by both the client serializers and the manifest
  writer.
- Guard with a test: run each language's client against a recording adapter, collect every hash it sends, assert each is in the manifest.

## Server side

- **Spring (reference, not a library):** an interceptor that loads the manifest once and pre-populates the hash → body store. Optionally a
  strict flag that rejects unknown hashes and any request carrying query text.
- **Apollo Server / Router:** publish with Rover; nothing else to generate.

## Phases

1. Config + generation error cases (TDD in `test/persisted_queries/`).
2. IR extraction of query assembly + manifest writer, unit-tested on the generator output.
3. Drift test against the real clients (start with Dart, then the others).
4. Reference Spring pre-warm interceptor + real-server test showing the first request is a hit with zero registrations.
5. Docs, changelog, release.

## Open questions

- Multiple client targets in one `glink.json`: one manifest each, or merged? Merged is what a single server wants.
- Does the manifest include the operations of every language target, given the text is identical across them? (It should be.)
- Subscriptions over WebSocket: unchanged, same as APQ.
