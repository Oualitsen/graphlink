# Python client

Status: implemented. Modelled on the Dart client; same feature set (queries, mutations, subscriptions, `@glCache`, uploads, `@glCaptureErrors`, persisted queries with GET).

## Decisions

- **pydantic v2 models** for types, inputs, interfaces/unions and enums. Third-party dependencies are fine (the rule is no dependency on GraphLink). pydantic replaces generated `toJson`/`fromJson`; `to_json` / `from_json` on the shared `GraphLinkModel` base wrap `model_dump(by_alias=True)` / `model_validate`.
- **asyncio, adapter injection.** The transport is `async (payload: str[, operation_name]) -> str`. Default adapters (`httpx`, `websockets`) are optional generated files (`httpAdapter` / `wsAdapter`).
- **snake_case with aliases.** A new `NamingConvention.python` turns fields, arguments and operation names into snake_case; the wire name is the pydantic alias. `NamingConvention.generatedTypeStem` makes `<Op>Response` names PascalCase instead of `Find_first_userResponse`.
- **Import cycles.** Each type is its own module (as in the other targets). Enums and base interfaces are imported eagerly; every other model reference is `TYPE_CHECKING`-only. The package `__init__.py` injects the model classes into each model module and calls `model_rebuild()`, so cycles (`User` ↔ `Post`) resolve without circular imports.
- **Interfaces/unions** are base models with a `wrap` model validator that dispatches on `__typename`; the implementations are imported lazily inside a function. Unknown typenames raise, as in Dart.
- **Fragment names are ordered lists**, not sets: the assembled query text is hashed for persisted queries, so its order must not vary between runs.
- **Hashing** uses `hashlib.sha256` (no pure implementation needed). The GraphQL query serializer is created with `escapeDolar: false`, like every non-Dart language.
- **Errors**: `GraphLinkException(errors)` replaces Dart's `throw List<GraphLinkError>`.

## Known limits

- Upload progress from the httpx adapter is coarse (start and end of the request).
- `typeMappings` entries for custom scalars must be resolvable names in the generated module (for example `Any`); imports for mapped types are not generated.
