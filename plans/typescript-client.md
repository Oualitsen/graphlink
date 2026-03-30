# TypeScript Client Generation

## Design Decisions

### Types
- GraphQL `type` → TypeScript `interface` with `readonly __typename: 'TypeName'`
- GraphQL `interface` / `union` → TypeScript discriminated union type `type Foo = A | B`
- No `fromJson`/`toJson` — plain cast (`data as FooResponse`) since TS types are structural
- Exception: GraphQL `interface`/`union` fields still resolved via `__typename` at runtime (cast works because server includes `__typename`)
- `readonly` fields controlled by `immutableTypeFields` config flag

### Inputs
- GraphQL `input` → TypeScript `interface`
- Nullable input fields use optional syntax: `field?: T | null` (not `field: T | null`)
- Controlled by `optionalNullableInputFields` config flag (default `true`)

### Enums
- GraphQL `enum` → TypeScript string union: `export type Status = 'A' | 'B'`

### Client
- HTTP adapter: user-provided `(payload: string) => Promise<string>` — zero runtime deps
- WebSocket adapter: injectable `GraphLinkWsAdapter` interface — works in browser, Node, React Native
- Subscriptions: `AsyncGenerator<T>` (zero deps, modern TS)
- Typed errors: `class GraphLinkError extends Error` with `errors: GraphLinkErrorItem[]`
- Cache: port of Dart cache (TTL, tags, staleIfOffline, FNV-1a key, InMemoryGraphLinkCacheStore)
- Module system: ESM only (`import`/`export`, `.js` extensions in import paths)
- `strict: true` compatible

### Output structure
```
generated/
  types/          ← regular types + GraphQL interface union types
  inputs/
  enums/
  client/
    graph_link_client.ts
    graph_link_ws_adapter.ts   ← default WS adapter (optional)
  index.ts        ← barrel re-exports
```

### Config (`config.json`)
```json
{
  "clientConfig": {
    "typescript": {
      "generateAllFieldsFragments": true,
      "autoGenerateQueries": true,
      "immutableTypeFields": true,
      "optionalNullableInputFields": true
    }
  }
}
```
No `packageName` needed — only top-level `outputDir`.

---

## Files to Create / Modify

| File | Change |
|---|---|
| `lib/src/serializers/language.dart` | Add `typescript` to `Language` enum |
| `lib/src/config.dart` | Add `TypeScriptClientConfig`; add `typescript` field to `ClientConfig`; relax assert |
| `lib/src/cache_store_typescript.dart` | New — TypeScript template strings (cache infra, error types, WS adapter) |
| `lib/src/serializers/typescript_serializer.dart` | New — `TypeScriptSerializer extends GLSerializer` |
| `lib/src/serializers/client_serializers/typescript_client_serializer.dart` | New — `TypeScriptClientSerializer extends GLClientSerilaizer` |
| `lib/src/main.dart` | Add `generateTypeScriptClientClasses()`; dispatch when `clientConfig.typescript != null` |
