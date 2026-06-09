---
title: GraphLink — GraphQL Code Generation for Dart, Java, TypeScript & Kotlin
description: GraphLink compiles your .graphql schema into fully typed clients and server code for Dart, Flutter, Java, TypeScript, Kotlin, and Spring Boot. No runtime. No boilerplate. No schema drift.
---

# GraphLink

> Your `.graphql` schema compiles to a fully typed client and server — for Dart, Flutter, Java, TypeScript, Kotlin, and Spring Boot — in milliseconds.

[![pub.dev](https://img.shields.io/pub/v/graphlink?label=pub.dev)](https://pub.dev/packages/graphlink)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Oualitsen/graphlink/blob/main/LICENSE)
[![GitHub Releases](https://img.shields.io/github/v/release/Oualitsen/graphlink)](https://github.com/Oualitsen/graphlink/releases/latest)

**No runtime. No boilerplate. No schema drift.**

---

## One schema. Every client. Every language.

Write your API once in GraphQL. Run `glink`. Every target regenerates in milliseconds.

```
schema/*.graphql
  │
  ├── lib/generated/                        Flutter / Dart client
  ├── src/main/java/com/app/generated/      Java client
  ├── src/generated/                        TypeScript client
  ├── src/main/kotlin/com/app/generated/    Kotlin client
  └── src/main/java/com/app/generated/      Spring Boot server
```

Add a field to the schema — run `glink` — it appears in every client, every language, immediately typed. No hand-written DTOs. No copy-pasted response classes. No drift between frontend and backend.

=== "Dart / Flutter"

    ```dart
    final res = await client.queries.getVehicle("v-1");
    print("${res.getVehicle.brand} ${res.getVehicle.model}");
    ```

=== "Java"

    ```java
    Vehicle v = client.queries.getVehicle("v-1").getVehicle();
    System.out.println(v.getBrand() + " " + v.getModel());
    ```

=== "TypeScript"

    ```typescript
    const res = await client.queries.getVehicle("v-1");
    console.log(`${res.getVehicle.brand} ${res.getVehicle.model}`);
    ```

=== "Kotlin"

    ```kotlin
    val v = client.queries.getVehicle("v-1").getVehicle
    println("${v.brand} ${v.model}")
    ```

The call site is clean in every language. One schema. Zero boilerplate.

---

## Why GraphLink?

### 1. Cache control lives in the schema

Annotate any query or mutation directly in your `.graphql` file. The generated client handles TTL, tag-based invalidation, partial query caching, and offline fallback automatically — across every target language.

```graphql
type Query {
  getVehicle(id: ID!): Vehicle! @glCache(ttl: "2m", tags: ["vehicles"])
  listVehicles: [Vehicle!]!     @glCache(ttl: "1m", tags: ["vehicles"])
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}
```

The second call is served from cache. `addVehicle` evicts the `"vehicles"` tag automatically. No cache layer to wire up. No manual invalidation logic. The schema says it; the generated client does it.

---

### 2. Subscriptions — with auto-reconnect out of the box

This is where most GraphQL client libraries fall short: they generate a WebSocket subscription method but leave reconnection entirely to you. Network drops, server restarts, idle timeouts — your app silently stops receiving events.

GraphLink generates a default WebSocket adapter for every target — **with auto-reconnect enabled by default**. The connection drops, it comes back, your `Flow` / `Stream` / `Observable` keeps emitting. No reconnection logic to write. No silent failures.

=== "Kotlin"

    ```kotlin
    scope.launch {
        client.subscriptions.userCreated().collect { event ->
            println("New user: ${event.userCreated.name}")
        }
    }
    ```

=== "Dart"

    ```dart
    client.subscriptions.onUserCreated().listen((event) {
      print("New user: ${event.userCreated.name}");
    });
    ```

=== "TypeScript"

    ```typescript
    client.subscriptions.userCreated().subscribe(event => {
      console.log("New user:", event.userCreated.name);
    });
    ```

The generated adapter speaks the [graphql-ws](https://github.com/enisdenjo/graphql-ws) protocol and handles the full connection lifecycle — `connection_init`, `connection_ack`, `subscribe`, `ping/pong`, and reconnect — all covered by integration tests.

---

### 3. The server is generated too

GraphLink isn't only a client generator. Switch to `mode: server` and point it at your Spring Boot project. It generates controllers, service interfaces, input classes, and DTOs — wired up to the schema, ready to implement.

```
schema/*.graphql  →  @SchemaMapping controllers
                     Service interfaces to implement
                     Input classes with null-safety
                     Type DTOs
```

You implement the business logic. GraphLink handles the plumbing.

---

### 4. Generated code you own completely

The output is ordinary Dart, Java, TypeScript, or Kotlin — no runtime dependency on GraphLink whatsoever. Stop using it tomorrow and everything keeps compiling. Commit the output to your repo, vendor it, ship it. It's just code.

---

## In production

Measured in [Optidialysis](https://www.optidialysis.com/) — a multi-tenant dialysis clinic management platform.

**72% of the Spring Boot backend — generated.** Controllers, service interfaces, DTOs, input classes, enums — all from one `.graphql` file. Only **135 files (~11.8k lines)** written by hand across the entire backend.

| What | Generated |
|---|---|
| Spring Boot files | **72%** |
| Spring Boot lines | **64%** |
| Flutter codebase | **21.5%** |

Every generated file compiles, ships, and runs with zero runtime dependency on GraphLink.

---

## Supported targets

**Stable:** Dart · Flutter · Java · Spring Boot · TypeScript · Kotlin

**Planned:** Express / Node.js · Go

---

## Installation

Download the single self-contained binary — no JVM, no package manager required.

=== "macOS (ARM)"

    ```bash
    curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-arm64 -o glink
    chmod +x glink && sudo mv glink /usr/local/bin/glink
    ```

=== "macOS (x64)"

    ```bash
    curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-macos-x64 -o glink
    chmod +x glink && sudo mv glink /usr/local/bin/glink
    ```

=== "Linux (x64)"

    ```bash
    curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-linux-x64 -o glink
    chmod +x glink && sudo mv glink /usr/local/bin/glink
    ```

=== "Windows"

    Download [`glink-windows-x64.exe`](https://github.com/Oualitsen/graphlink/releases/latest) and add it to your PATH.

=== "Dart / Flutter (pub)"

    ```bash
    flutter pub add --dev graphlink
    # or
    dart pub add --dev graphlink
    ```

---

## Quick Start

### 1. Write your schema

```graphql
type Vehicle {
  id: ID!
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
}

enum FuelType { GASOLINE DIESEL ELECTRIC HYBRID }

input AddVehicleInput {
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
}

type Query {
  getVehicle(id: ID!): Vehicle!  @glCache(ttl: "2m", tags: ["vehicles"])
  listVehicles: [Vehicle!]!      @glCache(ttl: "1m", tags: ["vehicles"])
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}
```

### 2. Configure

Pick your target and drop a `glink.yaml` next to your schema:

=== "Dart / Flutter"

    ```yaml
    schemaPaths:
      - lib/**/*.graphql
    mode: client
    typeMappings:
      ID: String
      Float: double
      Int: int
      Boolean: bool
    outputDir: lib/generated
    clientConfig:
      dart:
        packageName: my_app
    ```

=== "Java"

    ```yaml
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: String
      Float: Double
      Int: Integer
      Boolean: Boolean
    outputDir: src/main/java/com/example/generated
    clientConfig:
      java:
        packageName: com.example.generated
    ```

=== "TypeScript"

    ```yaml
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: string
      Float: number
      Int: number
      Boolean: boolean
    outputDir: src/generated
    clientConfig:
      typescript:
        httpAdapter: fetch
    ```

=== "Kotlin"

    ```yaml
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: String
      Float: Double
      Int: Int
      Boolean: Boolean
    outputDir: src/main/kotlin/com/example/generated
    clientConfig:
      kotlin:
        packageName: com.example.generated
    ```

=== "Spring Boot"

    ```yaml
    schemaPaths:
      - src/main/resources/graphql/*.graphqls
    mode: server
    typeMappings:
      ID: String
      Float: Double
      Int: Integer
      Boolean: Boolean
    outputDir: src/main/java/com/example/generated
    serverConfig:
      spring:
        basePackage: com.example.generated
    ```

### 3. Generate

```bash
glink       # auto-discovers glink.yaml / glink.json / glink.yml
glink -w    # watch mode — regenerate on every save
```

→ See [Getting Started](getting-started.md) for a complete walkthrough per language.

---

## FAQ

??? "Does the generated code have a runtime dependency on GraphLink?"

    None. If you stop using GraphLink tomorrow, every generated file continues to compile
    and work exactly as before. The output is ordinary Dart, Java, TypeScript, or Kotlin —
    you own it completely.

??? "What happens when I add a field to the schema?"

    Run `glink` (or let `glink -w` pick it up automatically). All affected files are
    regenerated and the new field is immediately available as a typed property in every
    target. One file to edit — GraphLink handles the rest.

??? "How does the built-in caching work?"

    Cache behaviour is declared in the schema using two directives.
    `@glCache(ttl: "5m", tags: ["cars"])` caches a query result for 5 minutes under the
    tag `"cars"`. `@glCacheInvalidate(tags: ["cars"])` on a mutation evicts all entries
    tagged `"cars"` when the mutation succeeds. Individual fields inside a compound query
    can each carry their own TTL — if one tag is invalidated, the others stay warm.
    See [Caching](caching.md) for the full reference.

??? "Is GraphLink production-ready?"

    Yes. In one production deployment (multi-tenant SaaS, dialysis clinic management),
    72% of Spring Boot files and 64% of lines are generated — only 135 files written by
    hand across the entire backend. On the Flutter side, 21.5% of the codebase is
    generated, covering all DTOs, input classes, enums, and GraphQL client wiring.

??? "Can I use GraphLink with an existing project?"

    Yes. Point `schemaPaths` at your existing `.graphql` files and set `outputDir` to
    wherever you want the generated files. GraphLink does not touch any of your existing
    source files.

??? "Does it work for full-stack monorepos?"

    Yes — this is the primary use case. Run `glink` with different config files (or different
    `outputDir` values) to generate the Flutter client, the Java client, and the Spring Boot
    server from the same schema. One schema, multiple configs, all in sync.

---

## Documentation

<div class="grid cards" markdown>

- **[Philosophy](philosophy.md)** — Why pure code generation? Why no runtime abstractions?
- **[Getting Started](getting-started.md)** — Zero to generated code in 5 minutes.
- **[Dart / Flutter Client](dart-client.md)** — Typed queries, mutations, subscriptions. Adapter pattern.
- **[Java Client](java-client.md)** — No generics. No casting. Builder pattern on all inputs.
- **[TypeScript Client](typescript-client.md)** — Typed client for Angular, React, Vue, and Node.
- **[Kotlin Client](kotlin-client.md)** — Coroutine-based client with data classes and kotlinx.serialization.
- **[Spring Boot](spring-server.md)** — Generated controllers, service interfaces, types, inputs.
- **[Caching](caching.md)** — `@glCache` and `@glCacheInvalidate`. Tag-based invalidation.
- **[Directives](directives.md)** — Complete reference for all GraphLink directives.
- **[Configuration](configuration.md)** — Every `glink.json` / `glink.yaml` option explained.
- **[AI Agents](ai-agents.md)** — Ready-to-copy instructions for Claude Code, Gemini CLI, and others.

</div>

---

**GraphLink** — MIT License — [graphlink.dev](https://graphlink.dev)

| | |
|---|---|
| **Source** | [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink) |
| **Package** | [pub.dev/packages/graphlink](https://pub.dev/packages/graphlink) |
| **Releases** | [github.com/Oualitsen/graphlink/releases](https://github.com/Oualitsen/graphlink/releases) |
| **Changelog** | [CHANGELOG.md](https://github.com/Oualitsen/graphlink/blob/main/CHANGELOG.md) |
| **Bug reports** | [github.com/Oualitsen/graphlink/issues](https://github.com/Oualitsen/graphlink/issues) |
| **Discussions** | [github.com/Oualitsen/graphlink/discussions](https://github.com/Oualitsen/graphlink/discussions) |
| **Author** | [github.com/Oualitsen](https://github.com/Oualitsen) |
