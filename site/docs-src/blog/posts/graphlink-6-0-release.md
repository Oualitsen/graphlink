---
date: 2026-11-10
slug: graphlink-6-0-release
categories:
  - Release
description: "GraphLink 6.0: REST operations in all seven clients, new Python and Go clients, scalar codecs, validated directives and streaming uploads."
id: R-60
demo_repo_path: ""
docs_page: "rest-client.md"
---

# GraphLink 6.0: REST, Python, Go and a Stricter Generator

GraphLink 6.0 adds a Python and a Go client, serves REST operations through the same generated client in all seven languages, converts custom scalars with codecs, and fails loudly where it used to guess. Some of that is breaking, so the migration notes are at the end.

<!-- more -->

## Seven clients

Dart, Java, Kotlin, TypeScript, Swift, Python and Go all generate from the same schema. The two new ones follow the idioms of their language:

- **Python**: pydantic v2 models, an `asyncio` client with keyword-only arguments, `AsyncIterator` subscriptions, and `httpx` and `websockets` adapters.
- **Go**: plain structs with `json` tags in one package, a `context`-aware client whose methods return `(value, error)`, channel subscriptions, and `net/http` and `coder/websocket` adapters. Go 1.22 or later.

Both have caching with tag invalidation, file uploads, `@glCaptureErrors` and persisted queries.

## REST operations

Annotate a field of `Query` or `Mutation` with `@glRest` and the generated client calls it over HTTP/JSON instead of GraphQL.

```graphql
extend type Query @glRestPrefix(path: "/products") {
  product(id: ID!): Product @glRest(path: "/{id}")
}
```

```dart
final product = await client.queries.product(id: 'p1');
```

The call site is the same as for a GraphQL field. To move an API from REST to GraphQL one field at a time, remove the directive. Arguments get explicit roles (`@glRestPath`, `@glRestParam`, `@glRestHeader`, `@glRestBody`, `@glRestField`, `@glRestPart`), responses can be JSON, text, `Void` or a streamed `Download`, and `@glCache` works on REST operations too. `@glRestNullable` decodes into a copy of the response type where every field is nullable, for APIs that omit fields the schema declares non-null. See [REST operations](../../rest-client.md).

## Scalar codecs

A `typeMappings` entry can now be an object, so a custom scalar is converted when it is decoded and encoded:

```json
{
  "typeMappings": {
    "Decimal": {
      "type": "Decimal",
      "import": "package:decimal/decimal.dart",
      "fromJson": "Decimal.parse({} as String)",
      "toJson": "{}.toString()"
    }
  }
}
```

`{}` stands for the value. The codec applies to fields, list elements, input fields and operation arguments, and `jsonType` makes the generated decoder check the JSON type before your `fromJson` runs.

## A stricter generator

- **Directives are validated.** Every directive must be built in or declared with `directive @name ... on ...`. Unknown or misspelled arguments, wrong value kinds and wrong locations fail generation with the line and column. `glink --print-directives` prints the declarations of GraphLink's own directives for your IDE.
- **Bad responses fail clearly.** A response with no `data` and no errors, or a non-2xx status without a GraphQL body, now fails with the client's error type instead of returning `null` or crashing.
- **Uploads stream** in every client instead of being built in memory, with exact progress and chunked transfer when the length is unknown.

## Migrating from 5.x

1. **Declare your custom directives** (federation's `@key`, your own `@auth`) and fix the typos the new errors point to.
2. **Regenerate** and review the diff. Projected interface and union names, and the `_all_fields` fragments of types in a cycle, can change.
3. **Swift:** `fromJson` of every type that holds an interface or union is now `throws`; call it with `try`.
4. **Java and Kotlin:** `DefaultGraphLinkClientAdapter` takes a decoder. The `GraphLinkClient` factory methods are unchanged.
5. **Python and Go:** a missing non-null field is now an error that names the type and the field.

The full list is in the [changelog](https://github.com/Oualitsen/graphlink/blob/main/CHANGELOG.md).

## Try it

- Install: <https://graphlink.dev/getting-started.html>
- REST operations: <https://graphlink.dev/rest-client.html>
