---
title: GraphLink — GraphQL Code Generation for Dart, Java & TypeScript
description: GraphLink generates type-safe client and server code from a GraphQL schema for Dart, Flutter, Java, TypeScript, and Spring Boot. No boilerplate. No generics. No runtime dependency.
---

# GraphLink

> Define your GraphQL schema once. Get fully typed client **and** server code — for Dart, Flutter, Java, TypeScript, and Spring Boot — in milliseconds.

[![pub.dev](https://img.shields.io/pub/v/graphlink?label=pub.dev)](https://pub.dev/packages/graphlink)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Oualitsen/graphlink/blob/main/LICENSE)
[![GitHub Releases](https://img.shields.io/github/v/release/Oualitsen/graphlink)](https://github.com/Oualitsen/graphlink/releases/latest)

No runtime. No boilerplate. No schema drift.

---

## In production

Measured in [Optidialysis](https://www.optidialysis.com/) — a multi-tenant dialysis clinic management platform running GraphLink-generated code.

| Metric | Value |
|---|---|
| Spring Boot files generated | **72%** |
| Spring Boot lines generated | **64%** |
| Flutter codebase generated | **21.5%** |
| Files written by hand (entire backend) | **135 files (~11.8k lines)** |

Controllers, service interfaces, DTOs, input classes, enums — all generated.
Every generated file compiles, ships, and runs with **zero runtime dependency** on GraphLink.

---

## Why GraphLink?

**No generics at the Java call site.**
Every other Java GraphQL client makes you write `TypeReference<GraphQLResponse<Map<String,Object>>>`. GraphLink generates fully-resolved return types:

```java
// Other clients
GraphQLResponse<GetUserData> res = client.execute(query, vars,
    new TypeReference<GraphQLResponse<GetUserData>>() {});
User user = res.getData().getGetUser();

// GraphLink
User user = client.queries.getUser("42").getUser();
```

**Cache control belongs in your schema.**
Declare caching once with `@glCache` and `@glCacheInvalidate` — the generated client handles TTL, tag-based invalidation, partial query caching, and offline fallback automatically.

**Only what the server needs.**
GraphLink generates minimal, precise query strings — no full-schema dumps that break Spring Boot's strict GraphQL validation.

**Single source of truth.**
One `.graphql` file drives the Dart client, the Java client, and the Spring Boot controllers. Add a field once, regenerate, both ends stay in sync.

---

## Supported targets

| Target | Status |
|---|---|
| Dart client | ✅ Stable |
| Flutter client | ✅ Stable |
| Java client | ✅ Stable |
| Spring Boot server | ✅ Stable |
| TypeScript client | ✅ Stable |
| Express / Node.js | 📋 Planned |
| Go, Kotlin | 📋 On demand |

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
  getVehicle(id: ID!): Vehicle!  @glCache(ttl: 120, tags: ["vehicles"])
  listVehicles: [Vehicle!]!      @glCache(ttl: 60,  tags: ["vehicles"])
}

type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}
```

### 2. Configure

=== "Dart / Flutter"

    === "JSON"

        ```json
        {
          "schemaPaths": ["lib/**/*.graphql"],
          "mode": "client",
          "typeMappings": { "ID": "String", "Float": "double", "Int": "int", "Boolean": "bool" },
          "outputDir": "lib/generated",
          "clientConfig": {
            "dart": {
              "packageName": "my_app",
              "generateAllFieldsFragments": true,
              "autoGenerateQueries": true
            }
          }
        }
        ```

    === "YAML"

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
            generateAllFieldsFragments: true
            autoGenerateQueries: true
        ```

=== "Java client"

    === "JSON"

        ```json
        {
          "schemaPaths": ["schema/*.graphql"],
          "mode": "client",
          "typeMappings": { "ID": "String", "Float": "Double", "Int": "Integer", "Boolean": "Boolean" },
          "outputDir": "src/main/java/com/example/generated",
          "clientConfig": {
            "java": {
              "packageName": "com.example.generated",
              "generateAllFieldsFragments": true,
              "autoGenerateQueries": true
            }
          }
        }
        ```

    === "YAML"

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
            generateAllFieldsFragments: true
            autoGenerateQueries: true
        ```

=== "TypeScript"

    === "JSON"

        ```json
        {
          "schemaPaths": ["schema/*.graphql"],
          "mode": "client",
          "typeMappings": { "ID": "string", "Float": "number", "Int": "number", "Boolean": "boolean" },
          "outputDir": "src/generated",
          "clientConfig": {
            "typescript": {
              "generateAllFieldsFragments": true,
              "autoGenerateQueries": true,
              "httpAdapter": "fetch"
            }
          }
        }
        ```

    === "YAML"

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
            generateAllFieldsFragments: true
            autoGenerateQueries: true
            httpAdapter: fetch
        ```

=== "Spring Boot server"

    === "JSON"

        ```json
        {
          "schemaPaths": ["src/main/resources/graphql/*.graphqls"],
          "mode": "server",
          "typeMappings": { "ID": "String", "Float": "Double", "Int": "Integer", "Boolean": "Boolean" },
          "outputDir": "src/main/java/com/example/generated",
          "serverConfig": {
            "spring": {
              "basePackage": "com.example.generated",
              "generateControllers": true,
              "generateInputs": true,
              "generateTypes": true
            }
          }
        }
        ```

    === "YAML"

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
            generateControllers: true
            generateInputs: true
            generateTypes: true
        ```

### 3. Generate

```bash
glink                   # auto-discovers glink.json / glink.yaml / glink.yml
glink -c glink.json     # explicit config path
glink -w                # watch mode — regenerate on every save
```

---

## Documentation

<div class="grid cards" markdown>

- **[Philosophy](philosophy.md)** — Why pure code generation? Why no runtime abstractions?
- **[Getting Started](getting-started.md)** — Zero to generated code in 5 minutes.
- **[Dart / Flutter Client](dart-client.md)** — Typed queries, mutations, subscriptions. Adapter pattern.
- **[Java Client](java-client.md)** — No generics. No casting. Builder pattern on all inputs.
- **[TypeScript Client](typescript-client.md)** — Typed client for Angular, React, Vue, and Node.
- **[Spring Boot](spring-server.md)** — Generated controllers, service interfaces, types, inputs.
- **[Caching](caching.md)** — `@glCache` and `@glCacheInvalidate`. Tag-based invalidation.
- **[Directives](directives.md)** — Complete reference for all GraphLink directives.
- **[Configuration](configuration.md)** — Every `glink.json` / `glink.yaml` option explained.
- **[AI Agents](ai-agents.md)** — Ready-to-copy instructions for Claude Code, Gemini CLI, and others.

</div>

---

## FAQ

??? "Does the generated code have a runtime dependency on GraphLink?"

    No. If you stop using GraphLink tomorrow, every generated file continues to compile
    and work exactly as before. The output is ordinary Dart, Java, or TypeScript code —
    you own it completely.

??? "Does the Java client use generics at the call site?"

    Never. GraphLink generates fully-resolved return types for every query and mutation.
    The call site is just `client.queries.getUser(id).getUser()` — no `TypeReference`,
    no casting, no generic parameters.

??? "What happens when I add a field to the schema?"

    Run `glink` again (or `glink -c glink.json`) (or let watch mode pick it up automatically).
    All affected files are regenerated and the new field is immediately available as a
    typed property. One file to edit — GraphLink handles the rest.

??? "How does the built-in caching work?"

    Cache behaviour is declared in the schema using two directives.
    `@glCache(ttl: 300, tags: ["cars"])` caches a query result for 300 seconds under the
    tag `"cars"`. `@glCacheInvalidate(tags: ["cars"])` on a mutation evicts all entries
    tagged `"cars"` when the mutation succeeds. Individual fields inside a compound query
    can each carry their own TTL — if one tag is invalidated, the others stay warm.

??? "Is GraphLink production-ready?"

    Yes. In one production deployment (multi-tenant SaaS, dialysis clinic management),
    72% of Spring Boot files and 64% of lines are generated — only 135 files (~11.8k lines)
    were written by hand across the entire backend. On the Flutter side, 21.5% of the
    codebase is generated, covering all DTOs, input classes, enums, and GraphQL client wiring.

??? "Can I use GraphLink with an existing project?"

    Yes. Point `schemaPaths` at your existing `.graphql` files and set `outputDir` to
    wherever you want the generated files. GraphLink does not modify any of your existing
    source files.

??? "What languages and frameworks are supported?"

    Dart and Flutter (client), Java (client), TypeScript (client), and Spring Boot (server).
    Express/Node.js server generation and Go/Kotlin targets are planned based on community demand.

---

Issues and contributions welcome at [github.com/Oualitsen/graphlink](https://github.com/Oualitsen/graphlink).
