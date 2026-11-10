---
title: "Why GraphLink Supports REST"
description: "Why a GraphQL code generator also generates REST clients: try GraphLink on the API you have, get a real client-side cache, and migrate to GraphQL one field at a time."
---

# Why Support REST?

GraphLink is a GraphQL code generator, so why does it also generate clients for plain REST APIs? Because the API you have today is probably REST, and three things follow from that.

<div class="grid cards" markdown>

- **:material-rocket-launch: Taste it today**

    Put `@glRest` on a field and get a typed client in seven languages for the API you already have. No GraphQL server needed.

- **:material-database-clock: A real client-side cache**

    The same `@glCache` that GraphQL operations use, with TTL, tags and invalidation, on REST calls. It does not depend on HTTP headers.

- **:material-swap-horizontal: A path to GraphQL**

    Migrate one field at a time. Remove the directive, and the call site does not change.

</div>

## 1. Taste GraphLink on the API you already have

The hardest part of trying a code generator is the setup: you need a GraphQL server before you can see any of it work. REST operations remove that step. Describe an existing REST endpoint in a schema file, run `glink`, and use the generated client right away.

```graphql
scalar Void @glVoid

type Product { id: ID! name: String! }
input ProductIn { name: String! }

type Query {
  ping: String
}

extend type Query @glRestPrefix(path: "/products") {
  product(id: ID!): Product @glRest(path: "/{id}")
}

extend type Mutation @glRestPrefix(path: "/products") {
  createProduct(input: ProductIn! @glRestBody): Product! @glRest(path: "", method: POST)
  deleteProduct(id: ID!): Void @glRest(path: "/{id}", method: DELETE)
}
```

A schema with only REST operations needs no GraphQL `url` and no GraphQL adapter. You pass the base URL of the REST API and call the methods:

=== "Dart"

    ```dart
    final product = await client.queries.product(id: 'p1');
    await client.mutations.createProduct(input: ProductIn(name: 'Pen'));
    ```

=== "TypeScript"

    ```typescript
    const product = await client.queries.product({ id: 'p1' });
    ```

=== "Kotlin"

    ```kotlin
    val product = client.queries.product(id = "p1")
    ```

=== "Java"

    ```java
    Product product = client.queries.product("p1", null);
    ```

=== "Swift"

    ```swift
    let product = try await client.queries.product(id: "p1")
    ```

=== "Python"

    ```python
    product = await client.queries.product(id="p1")
    ```

=== "Go"

    ```go
    product, err := client.Queries.Product(ctx, "p1")
    ```

That is a few lines of schema, and here is what you did not write:

- **Models, inputs and enums** with JSON serialization, in your language's idiom.
- **Every request detail.** Path parameters, query strings, headers, JSON, form and multipart bodies, and file uploads and downloads with progress. You choose the role of each argument in the schema (`@glRestPath`, `@glRestParam`, `@glRestHeader`, `@glRestBody`, `@glRestField`, `@glRestPart`).
- **Typed errors.** A non-2xx status always throws `RestError` with the status, headers and body. It is never silently turned into `null`.
- **The transport.** A generated HTTP adapter, or your own function if you prefer. The client has no hard dependency on an HTTP library.
- **No runtime dependency on GraphLink.** The output is ordinary code. If you decide GraphLink is not for you, delete the generator and everything still compiles.

If you are evaluating GraphLink, this is the fastest honest test: point it at one endpoint you know well, and compare the generated client with the one you would have written by hand. See [REST operations](rest-client.md) for the whole directive reference.

## 2. A real cache on the frontend, not an HTTP cache

REST caching usually means HTTP caching: `Cache-Control`, `ETag`, and whatever the browser or an HTTP library decides to do. That depends on the server sending the right headers, and it gives you no direct way to say "when this mutation succeeds, everything about products is stale."

GraphLink caches in the generated client, and it uses the same cache GraphQL operations use. You declare the policy in the schema:

```graphql
extend type Query @glRestPrefix(path: "/products") {
  product(id: ID!): Product @glRest(path: "/{id}") @glCache(ttl: "2m", tags: ["products"])
}

extend type Mutation @glRestPrefix(path: "/products") {
  createProduct(input: ProductIn! @glRestBody): Product!
    @glRest(path: "", method: POST) @glCacheInvalidate(tags: ["products"])
}
```

The second `product("p1")` call within two minutes is served from the client store, with no request. `createProduct` evicts every entry tagged `products` after a successful response. What makes this a real cache, and not a side effect of HTTP:

- **The schema decides, not the server's headers.** TTL, tags and invalidation live in your `.graphql` file, so an API that sends no caching headers at all can still be cached on the client.
- **It is one store and one tag space with GraphQL.** A GraphQL mutation can invalidate a tag held by a REST query, and the reverse. During a migration you do not have two caches that disagree.
- **Tag-based invalidation.** A mutation names what it makes stale. You do not have to compute cache keys.
- **Offline fallback.** With `staleIfOffline`, an expired entry is served when the request fails at the transport level (no network). A real server error, a `RestError`, is never masked.
- **Pluggable store.** The default store is in memory. Implement `GraphLinkCacheStore` to persist the cache or share it.

Only `GET` queries are cached, and `@glCacheInvalidate` runs after a 2xx response. See [Caching](caching.md) for the full reference.

!!! note "What this cache is not"
    GraphLink caches per operation and arguments, with tag invalidation. It is not a normalized entity cache, so one mutation does not rewrite every query that shows the same object. If you need that, see [When another tool fits better](philosophy.md#when-another-tool-fits-better).

## 3. A way to migrate, one field at a time

Migrations from REST to GraphQL fail when they are all-or-nothing. GraphLink makes them incremental because the call site does not care how a field is served.

=== "Today: REST"

    ```graphql
    type Query {
      product(id: ID!): Product @glRest(path: "/products/{id}")
    }
    ```

=== "After: GraphQL"

    ```graphql
    type Query {
      product(id: ID!): Product
    }
    ```

```dart
// the same line, before and after the migration
final product = await client.queries.product(id: 'p1');
```

The schema, the types and the client are the same. You migrate by removing the directive from a field once the GraphQL server can resolve it, and nothing that calls `client.queries.product` changes. Everything else keeps working over REST until its turn.

Three details make this practical:

- **The schema is the target contract.** Declare the fields as you want them to be in GraphQL. If the REST API you call today omits fields or sends `null` for fields the schema declares non-null, mark the operation `@glRestNullable`. The client decodes into a copy of the type (`Product` becomes `ProductRest`) in which every field is nullable, so the call does not fail while the API catches up.
- **One cache throughout.** Because REST and GraphQL operations share a cache and its tags, `@glCache` and `@glCacheInvalidate` keep working while fields move.
- **Mixed schemas are normal.** A `Query` type can have REST fields and GraphQL fields side by side, in any proportion, for as long as the migration takes.

!!! warning "One thing changes"
    If you used `@glRestNullable`, the result type goes back from `ProductRest` to `Product` when the field moves to GraphQL, and there is no automatic conversion. Code that names the type needs a one-time update.

## Frequently asked questions

??? "Do I need a GraphQL server to use REST operations?"

    No. A schema with only REST operations needs no GraphQL URL or adapter. GraphLink uses the schema only as a description of your REST API and generates the client from it.

??? "Which languages support REST operations?"

    Dart, Java (blocking and reactive), TypeScript, Kotlin, Swift, Python and Go. See [Supported Targets](targets.md).

??? "Is the REST cache an HTTP cache?"

    No. It is a client-side store configured with `@glCache` in the schema, so its policy does not come from HTTP caching headers. It shares its entries and tags with GraphQL operations.

??? "Are REST subscriptions supported?"

    No. Subscriptions are always GraphQL.

??? "Does it replace my REST client library?"

    It replaces the hand-written part: the models, the serialization, the request building and the response handling. The HTTP transport is a function you can supply, or a generated adapter.

## Where to go next

- [REST operations](rest-client.md): the directives, argument roles, responses and the adapter.
- [Caching](caching.md): TTL, tags, `staleIfOffline` and custom stores.
- [Getting Started](getting-started.md): install `glink` and generate your first client.
- [Supported Targets](targets.md): every language and the features each supports.
