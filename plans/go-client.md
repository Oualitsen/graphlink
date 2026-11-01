# Go client

Status: implemented. Modelled on the Dart client; same feature set (queries, mutations, subscriptions, `@glCache`, uploads, `@glCaptureErrors`, persisted queries with GET).

## Decisions

- **One flat package.** Go forbids import cycles between packages and GraphQL types routinely reference each other (`Author` ↔ `Article`), so every type, input, enum and the client are generated into a single package (`packageName`), one file per type (`<snake_name>.go`). A stem that Go would read as a build constraint (`user_linux.go`) gets a `_gl` suffix.
- **Plain structs and `encoding/json`.** Fields are exported `PascalCase` (`NamingConvention.go`) with the wire name in the `json` tag. There is no generated `toJson`/`fromJson`: only the types that need it get `MarshalJSON` (to emit `__typename`) or `UnmarshalJSON` (to decode interface/union fields).
- **Nullability.** Nullable scalars, enums and objects are pointers; nullable lists, maps, interfaces and `any` use their nil value. `Ptr[T]` is generated for building pointers.
- **Defaults.** Struct literals cannot carry defaults, so an input with defaults gets `New<Input>()`. Defaults on operation arguments are applied inside the method when the option is nil.
- **Arguments.** Required arguments are positional; optional ones and those with a default go in a trailing variadic `<Operation>Options`, so `client.Queries.Greet(ctx)` works. Hoisted `FieldArgs` follow the same rule.
- **Interfaces and unions** are Go interfaces with an `Is<Name>()` marker and getters for the interface fields. Concrete types are decoded by value from `__typename` by a generated `unmarshal<Name>` function; fields of those types decode through `glDecodeList` for any list depth. An unknown typename is an error, as in Dart.
- **Errors.** Operations return `(value, error)`; GraphQL errors are a `*GraphLinkException`. With `captureErrors` the `…FullResponse` is returned instead.
- **Generics instead of per-type `fromJson`.** Go methods cannot have type parameters, so `glExecuteFull/Data/Cached[T GraphLinkFullResponse]` are package functions taking the resolver. `GraphLinkFullResponse` is a generated interface exposing `GetErrors()`.
- **Subscriptions** return `<-chan GraphLinkEvent[T]`. An error event does not close the channel (the adapter may reconnect and resume); cancelling the context sends `complete` to the server and closes it. One WebSocket carries all subscriptions; the adapter contract is `Connect`, `SendMessage`, `Close`, `ConnectionInitPayload` and two registered callbacks (message, reconnect).
- **Dependencies.** The core uses only the standard library (`crypto/sha256` replaces Dart's pure SHA-256). The default WebSocket adapter needs `github.com/coder/websocket`; `wsAdapter: "none"` removes it.
- **Query text** is generated with `GLGraphqlSerializer(parser, false)` (no `$` escaping), like every non-Dart target. Fragment names are ordered slices because the assembled text is hashed for persisted queries.

## Known limits

- Types in a non-null cycle (`type A { b: B! } type B { a: A! }`) do not compile as Go value fields.
- `typeMappings` for custom scalars may name `time.Time`, `json.RawMessage`, `big.Int`, `url.URL`, `uuid.UUID`, which get their import; any other package must already be importable by name.
- A getter whose interface type differs from the implementing field's type in more than nullability falls back to a plain return and may not compile.
- Generated files are not run through `gofmt`.
