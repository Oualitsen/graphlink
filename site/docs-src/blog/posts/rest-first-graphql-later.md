---
date: 2026-11-10
slug: rest-first-graphql-later
categories:
  - REST
description: "Generate a typed client for the REST API you already have, cache it with schema tags, and move to GraphQL one field at a time, in seven languages."
id: R-61
demo_repo_path: ""
docs_page: "why-rest.md"
---

# Start With the REST API You Have: A Typed Client Today, GraphQL Later

Most teams that want GraphQL already have a REST API. They cannot switch in a weekend, and they should not have to. So the realistic plan is: keep calling REST, and move to GraphQL as the server catches up. GraphLink 6.0 is built for that plan.

**TL;DR**

- Describe a REST endpoint in a schema file, run `glink`, and get a typed client in Dart, Java, TypeScript, Kotlin, Swift, Python or Go.
- Cache REST calls on the client with `@glCache`, using the same store and tags as GraphQL.
- Migrate a field to GraphQL by removing one directive. The call site does not change.

<!-- more -->

## The problem

A hand-written REST client is a pile of small chores. A model class for every response. A serializer for every model. A function per endpoint that builds the path, the query string and the body, sends them, checks the status, and decodes the result. Then the same chores in the mobile app, the web app and the backend service, in three languages.

When the API later moves to GraphQL, all of that gets rewritten, because REST calls and GraphQL calls look nothing alike.

## One schema file

GraphLink describes a REST endpoint with a directive on a field of `Query` or `Mutation`:

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

`@glRestPrefix` shares a path across a block, and each argument gets a role: here the `id` fills the `{id}` placeholder and `@glRestBody` is the JSON body. Other roles cover query strings, headers, form fields and multipart parts.

A schema with only REST operations needs no GraphQL URL and no GraphQL adapter. You do not need a GraphQL server to try this.

## Using the generated code

Run `glink`, and the client has one method per field:

```dart
final product = await client.queries.product(id: 'p1');
await client.mutations.createProduct(input: ProductIn(name: 'Pen'));
```

The same schema generates the equivalent in TypeScript, Kotlin, Java, Swift, Python and Go. A non-2xx status throws a `RestError` with the status, headers and body, so a server error is never silently turned into `null`.

## A cache that is not an HTTP cache

Now the part that REST clients rarely have. Add the cache policy to the schema:

```graphql
extend type Query @glRestPrefix(path: "/products") {
  product(id: ID!): Product @glRest(path: "/{id}") @glCache(ttl: "2m", tags: ["products"])
}

extend type Mutation @glRestPrefix(path: "/products") {
  createProduct(input: ProductIn! @glRestBody): Product!
    @glRest(path: "", method: POST) @glCacheInvalidate(tags: ["products"])
}
```

Within two minutes, a second `product("p1")` is answered from the client's store without a request. A successful `createProduct` evicts everything tagged `products`. The policy comes from your schema, not from `Cache-Control` headers, so it works even when the API sends none.

It is the same store and the same tag space that GraphQL operations use. A GraphQL mutation can invalidate a tag held by a REST query, and the reverse. That matters for the next step.

This is a per-operation cache with tags and an offline fallback (`staleIfOffline`, for transport failures only). It is not a normalized entity cache.

## What happens under the hood

The generated client never touches the network by itself. It builds a request (method, path, query, headers, body) and calls one function you provide, or a generated adapter for `package:http`, Dio, `fetch`, axios, OkHttp, `URLSession`, `httpx` or `net/http`. The response is decoded into the generated types. There is no runtime dependency on GraphLink.

## Migrating, one field at a time

The day the GraphQL server can resolve `product`, remove the directive from that one field:

```graphql
type Query {
  product(id: ID!): Product
}
```

```dart
// unchanged
final product = await client.queries.product(id: 'p1');
```

The type, the method and the call are the same. Only the transport changed. Every other field keeps working over REST until its turn, and the shared cache keeps `@glCache` and `@glCacheInvalidate` working while you move.

If today's REST API omits fields that the schema declares non-null, mark the operation `@glRestNullable`. The client then decodes into a copy of the type (`ProductRest`) where every field is nullable, so calls do not fail while the API catches up.

## Limitations

- REST operations exist in the Dart, Java, TypeScript, Kotlin, Swift, Python and Go clients.
- Subscriptions are always GraphQL.
- Only `GET` queries are cached.
- If you used `@glRestNullable`, the result type goes back from `ProductRest` to `Product` when the field moves to GraphQL, with no automatic conversion.
- The cache is per operation and arguments, not normalized by entity.

## Try it

- Why REST: <https://graphlink.dev/why-rest.html>
- REST operations reference: <https://graphlink.dev/rest-client.html>
- Install: <https://graphlink.dev/getting-started.html>
