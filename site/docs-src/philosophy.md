---
title: "Philosophy: Pure GraphQL Code Generation"
description: "Why GraphLink is pure code generation, and how it compares with Apollo, GraphQL Code Generator, genqlient, ariadne-codegen, ferry and Netflix DGS."
---

# The GraphLink Philosophy

Pure code generation. No runtime abstractions. Only what the server needs.

## What pure code generation means

GraphLink is a code generator, not a runtime library. When you run `glink`, it reads your schema and writes ordinary Dart, Java, TypeScript, Kotlin, Swift, Python, or Go source files. Those files have zero dependency on GraphLink itself — no base classes to extend, no interfaces to implement, no runtime to ship.

Every generated class is plain code in the target language. A generated `Vehicle` class in Dart is just a Dart class with fields, a constructor, `fromJson`, and `toJson`. A generated `Vehicle.java` is just a POJO with a builder. A generated Kotlin `Vehicle` is a `data class`, and a generated Swift `Vehicle` is a `Sendable` struct. You could hand-write these classes yourself; GraphLink simply writes them faster and keeps them in sync with your schema.

**Delete GraphLink from your project tomorrow and everything still compiles.** There is nothing to uninstall, no peer dependency to satisfy, no API surface that could be deprecated. The generated code is yours.

!!! success "The practical implication"
    You can upgrade GraphLink independently of your app. You can audit every line of code that runs in production. You can add methods to generated classes without fighting a framework. You own the output.

## Only what the server needs

This is one of the most important design decisions in GraphLink, and it directly affects Spring Boot compatibility.

Many GraphQL clients (such as ferry in Dart) serialize the *entire schema document* and send it with every request. This includes type definitions, directives, fragment definitions, comments, and whitespace. On the wire this looks like:

```json title="What other clients send"
{
  "query": "fragment _all_fields_Vehicle on Vehicle { id brand model year fuelType ownerId } query getVehicle($id: ID!) { getVehicle(id: $id) { ...  _all_fields_Vehicle } }",
  "variables": { "id": "42" }
}
```

Spring Boot's `graphql-java` validates the query document on every request. If the client sends fragment definitions for types or fields that the server doesn't know about — or just sends unnecessary bulk — the server may reject the request or log validation warnings.

GraphLink generates minimal, precise query strings. The client sends exactly the fields needed for the response type, no fragment boilerplate, no extra definitions:

```json title="What GraphLink sends"
{
  "query": "query getVehicle($id: ID!) { getVehicle(id: $id) { id brand model year fuelType ownerId } }",
  "variables": { "id": "42" }
}
```

This is a significant operational difference. It means GraphLink clients work out-of-the-box with strict Spring Boot GraphQL servers, with AWS AppSync, and with any other server that validates incoming documents carefully.

## The schema is the single source of truth

In a typical project without code generation, the same concept is expressed in three places: the GraphQL schema, the data transfer objects (DTOs) in the server language, and the model classes in the client language. When the schema changes, all three must be updated manually. When they get out of sync — which they always do — you get runtime errors, not compile-time errors.

GraphLink collapses all three into one. You edit the schema. You re-run the generator. Every DTO, every model class, every query string, every serializer is immediately regenerated and consistent. Schema drift becomes impossible.

This also means code review is simpler: a schema change in a pull request implies a corresponding regeneration of client and server code. Reviewers can read the schema diff and know immediately what changed.

## No generics at the Java call site

Most Java GraphQL clients force you to carry type information through generics. A typical query call looks like:

```java title="Other clients — the generic soup"
// What you write with most clients
GraphQLResponse<Map<String, Object>> response =
    client.query(new SimpleGraphQLRequest<>(
        QUERY_STRING,
        variables,
        new TypeReference<GraphQLResponse<Map<String, Object>>>() {}
    ));
Vehicle vehicle = objectMapper.convertValue(
    response.getData().get("getVehicle"), Vehicle.class
);
```

```java title="GraphLink — no generics, no casting"
// What you write with GraphLink
GetVehicleResponse res = client.queries.getVehicle("42");
System.out.println(res.getGetVehicle().getBrand());
```

GraphLink generates a specific `getVehicle(String id)` method that returns a specific `GetVehicleResponse` type. The compiler knows the exact return type. There are no anonymous `TypeReference` subclasses, no unchecked casts, no `Map<String, Object>` to navigate manually.

## Keyword-safe identifiers

GraphQL has its own set of reserved words, and they rarely overlap with those of a target language. A field, input field, argument, or enum value may legally be named `default`, `class`, `object`, or `val` in your schema — all perfectly valid GraphQL, all reserved words in Dart, Java, or Kotlin. A naive generator would emit code that does not compile.

GraphLink keeps two names for every identifier:

- The **wire name** — the original GraphQL token. It is what travels in the query string, the JSON keys, and the variables map. It is never altered.
- The **code name** — a sanitized identifier used only where the target language needs one. When the wire name collides with a reserved word, GraphLink appends an underscore (`default` → `default_`), resolving further collisions numerically (`default_2`, `default_3`).

A **leading underscore** is sanitized the same way. In Dart a leading underscore means *private*, so a field named `_link` would be inaccessible and break the generated code. GraphLink moves the underscore to the end (`_link` → `link_`). The same applies to enum values (`_ACTIVE` → `ACTIVE_`). For consistency this rule is applied across **all** target languages, not just Dart — the wire name still keeps its leading underscore.

The serialization layer bridges the two, so the wire format stays exactly as your schema declares it:

```graphql title="Schema — a field named after a Dart/Java/Kotlin keyword"
type Settings {
  default: String
  theme: String
}
```

```dart title="Dart — identifier sanitized, JSON key untouched"
class Settings {
  final String? default_;
  final String? theme;

  Map<String, dynamic> toJson() => {
        'default': default_,   // wire key stays "default"
        'theme': theme,
      };

  Settings.fromJson(Map<String, dynamic> json)
      : default_ = json['default'] as String?,
        theme = json['theme'] as String?;
}
```

Enum values get the same treatment. Because Java and Kotlin couple a constant's name to its wire string via `valueOf()` / `name()`, GraphLink emits an explicit `switch` / `when` mapping for the sanitized constants — but only when sanitization actually happened, so enums without keyword collisions keep their clean `name()` / `valueOf()` form. On the Spring Boot server, a sanitized resolver argument is pinned back to the wire name with `@Argument(name = "default")` so request binding still works.

TypeScript needs none of this: its reserved words are legal as object property names and enum members, so identifiers are emitted verbatim. The whole mechanism is automatic — there is no configuration and nothing to opt into. Name a field after a keyword and the generated code simply compiles.

## Framework agnostic

GraphLink generates the logic — the query strings, the serialization, the client wiring — but it never dictates how you make HTTP requests. You provide the transport as a simple function:

- In Dart: `Future<String> Function(String payload)`
- In Java: a `@FunctionalInterface` that takes a JSON string and returns a JSON string
- In TypeScript: `(payload: string) => Promise<string>`
- In Kotlin: a `fun interface` with a single `suspend` method
- In Swift: a `GraphLinkClientAdapter` closure typealias
- In Python: an `async` function that takes the JSON payload and returns the response body
- In Go: a function that takes a `context.Context` and the JSON payload and returns the response body and an error

This means you can use `http`, `dio`, `fetch`, `OkHttp`, `URLSession`, `httpx`, `net/http`, Spring's `WebClient`, a mock, or anything else. The generated client does not import any HTTP library. You swap the transport at construction time. This makes testing trivial — pass a function that returns a hardcoded JSON string and you have a complete mock client.

## How it compares

GraphLink is built around one idea: **one schema generates the client and the server for every language you ship**, with no runtime library in between. Most other tools are the opposite: excellent at one language or one framework. This section shows where each one fits so you can choose on facts.

### Scope: what each tool generates

| Tool | Language | What it generates | Server code |
|---|---|---|---|
| **GraphLink** | Dart / Flutter, Java, TypeScript, Kotlin, Swift, Python, Go | Typed models, inputs, enums, a client with queries, mutations, subscriptions, caching, uploads, persisted queries and REST operations | **Spring Boot** (Java, Kotlin), **Express / Apollo** (TypeScript) |
| [Apollo Kotlin](https://www.apollographql.com/docs/kotlin) | Kotlin (multiplatform) | Models and queries, used with the Apollo runtime library and its normalized cache | No |
| Apollo iOS | Swift | Models and queries, used with the Apollo iOS library | No |
| [GraphQL Code Generator](https://the-guild.dev/graphql/codegen) | TypeScript first, plugin-based | Types and typed documents for the GraphQL client you choose | Resolver types through plugins |
| [genqlient](https://github.com/Khan/genqlient) | Go | Type-safe helpers for the queries you write, with a small runtime package | No |
| [ariadne-codegen](https://github.com/mirumee/ariadne-codegen) | Python | Pydantic models and an async or sync client from your schema and operations, with a plugin system | No |
| [Netflix DGS codegen](https://netflix.github.io/dgs/generating-code-from-schema) | Java, Kotlin | Types, inputs and a query builder API, tied to the DGS framework | Types for the DGS server framework |
| ferry | Dart | Typed operations on top of the ferry client | No |

### Features documented by each tool

This matrix compares GraphLink with the dedicated generator for each of its target languages. **—** means the feature was not found in the documentation we checked (November 2026), which is not the same as "no". Tools change, so check their documentation before you decide.

| Feature | GraphLink | Apollo Kotlin | Apollo iOS | ferry (Dart) | ariadne-codegen (Python) | genqlient (Go) | GraphQL Code Generator (TS) | Netflix DGS (Java) |
|---|---|---|---|---|---|---|---|---|
| Typed client from the schema | **Yes** | Yes | Yes | Yes | Yes | Typed helpers for queries you write | Types and typed documents, you bring the client | Types and a query builder API |
| Runtime library in your app | **None** | Yes (Apollo runtime) | Yes (Apollo library) | Yes (ferry client) | — | Small runtime package | Depends on your client | Optional DGS client |
| Subscriptions | **Yes** | Yes (`Flow`) | Yes | — | Yes (graphql-transport-ws) | — | Types only | Yes (WebSocket, SSE) |
| File uploads | **Yes** | Yes | Yes (one operation, no batches) | — | Yes (multipart) | — | — | — |
| Persisted queries (APQ) | **Yes** | Yes | — | — | — | — | — | — |
| Custom scalar mapping | **Yes** | Yes | Yes | — | Yes | Yes (bindings) | Yes (`scalars`) | — |
| Client cache | Per operation, tag invalidation | Normalized (memory, SQLite) | Normalized | Normalized | — | — | — | — |
| REST operations in the same client | **Yes** | — | — | — | — | — | — | — |
| Server code from the same schema | **Yes** | — | — | — | — | — | Resolver types (plugin) | Types for the DGS framework |

Read it as scope, not as a verdict. The Apollo clients and ferry have normalized caches, which GraphLink does not. ariadne-codegen has a plugin system. GraphQL Code Generator works with whichever client you already use. What GraphLink adds is the same schema, features and call syntax across all of the languages.

### Feature comparison

| Feature | GraphLink | ferry (Dart) | Apollo (JS/Kotlin) | Manual code |
|---|---|---|---|---|
| Runtime dependency in app | **None** | Yes (ferry, gql) | Yes (Apollo runtime) | None |
| Languages from one schema | **7 clients** | Dart only | One library per platform | Manual |
| Sends whole schema on request | **No** | Yes | Partial | No |
| Generics at Java call site | **No** | N/A | Yes | Yes |
| Server-side generation | **Yes** | No | Partial | Manual |
| Java client support | **Yes** | No | Kotlin only | Manual |
| Caching directives in schema | **Yes** | No | No | No |
| Partial query caching | **Yes** | No | No | No |
| Spring Boot controller gen | **Yes** | No | No | Manual |

The competitor columns describe each project's documented approach and may be out of date. Check their documentation before deciding.

### What GraphLink gives you

- **Classes and client operations, generated together.** Other generators stop at types, or at types plus typed documents, and leave you to pick, wire and maintain a client library. GraphLink also generates the client: every query, mutation and subscription becomes a typed method, with the serialization, caching and transport wiring included.
- **A generated backend you only fill in.** For Spring Boot (Java and Kotlin) and Express / Apollo, GraphLink generates the controllers or resolvers and the service interfaces. You implement the generated interfaces and the routing is done, so the architecture is the same in every project. The generated handlers are asynchronous by default (`CompletableFuture` on Java MVC, coroutines on Kotlin, `async` resolvers on Express), so sibling query fields can run concurrently. See [Concurrent execution](spring-server.md#concurrent-execution).
- **N+1 is built into the workflow.** `@glSkipOnServer(batch: true)` turns a field into a batch mapping (`@BatchMapping` on Spring, a per-request DataLoader on Express). One directive argument is all it takes, and it pushes developers to fix the N+1 problem instead of discovering it in production. See [Skip directives](skip-directives.md).
- **One schema for every target, or just one.** GraphLink works the same with a single client as with seven clients and two servers. Add a language later and the schema, the features and the call syntax carry over.
- **GraphQL and REST in one client.** A field annotated with `@glRest` is served over HTTP/JSON with the same call syntax, in all seven clients. Remove the directive and it becomes a GraphQL field without changing the call site. See [REST operations](rest-client.md).
- **Cache policy in the schema.** `@glCache` and `@glCacheInvalidate` set TTL, tags and offline fallback. There is no cache code in your application.
- **No runtime library.** The generated files compile without GraphLink. Stop using it tomorrow and nothing breaks.
- **Hardened decoding.** A bad response fails with a named error in every client instead of returning `null` or crashing.

### When another tool fits better

GraphLink does not cover everything, and these are the cases where something else is the better choice:

- **You need a normalized client cache.** GraphLink caches per operation and arguments, with tag invalidation. Apollo's normalized cache, which stores entities by identity so one mutation updates every query that shows them, is a different and more powerful model. ferry offers one for Dart too.
- **You rely on optimistic updates or cache watchers.** Apollo Kotlin has watchers that react to cache changes, and ferry has an optimistic cache. GraphLink's generated clients do not have an equivalent.
- **Your language is not one of the seven clients.** GraphLink generates Dart / Flutter, Java, TypeScript, Kotlin, Swift, Python and Go clients, and Spring Boot and Express / Apollo servers. For any other language or server framework you need another tool.

If you are in between, you can adopt GraphLink for one target first. The generated code is plain code in your language, so you are not locked in.
