---
title: "Supported Languages and Features of GraphLink"
description: "Every GraphLink target at a glance: Dart, Java, TypeScript, Kotlin, Swift, Python, Go clients, Spring Boot and Express servers, with the features each supports."
---

# Supported Languages and Features

GraphLink generates typed **clients** for seven languages and **servers** for Spring Boot (Java or Kotlin) and Express/Apollo (TypeScript), all from one `.graphql` schema. Every client speaks both **GraphQL** and **REST** (`@glRest` operations), and none of the generated code depends on GraphLink at run time.

## Clients

| Language | Config key | Models | Async model | HTTP (default) | WebSocket (default) | Requires |
|---|---|---|---|---|---|---|
| [Dart / Flutter](dart-client.md) | `clientConfig.dart` | classes with `toJson` / `fromJson` | `Future` / `Stream` | `package:http` or Dio | generated, auto-reconnect | Dart SDK |
| [Java](java-client.md) | `clientConfig.java` | POJOs with builders, or records | blocking, or Reactor / RxJava 3 / Mutiny (`asyncStyle`) | JDK `HttpClient`, OkHttp or Spring `WebClient` | JDK or OkHttp, auto-reconnect | Java 11+ (records: 16+) |
| [TypeScript](typescript-client.md) | `clientConfig.typescript` | interfaces and enums | `Promise`, or RxJS observables | `fetch` or axios | generated, auto-reconnect | Node, browsers, Bun |
| [Kotlin](kotlin-client.md) | `clientConfig.kotlin` | data classes | coroutines and `Flow` | OkHttp | OkHttp, auto-reconnect | kotlinx.serialization |
| [Swift](swift-client.md) | `clientConfig.swift` | `Sendable` structs | `async` / `await`, `AsyncThrowingStream` | `URLSession` | `URLSessionWebSocketTask`, auto-reconnect | Apple platforms or Linux |
| [Python](python-client.md) | `clientConfig.python` | pydantic v2 models | `asyncio`, `AsyncIterator` | `httpx` | `websockets`, auto-reconnect | pydantic >= 2.10 |
| [Go](go-client.md) | `clientConfig.go` | structs with `json` tags | `context`, `(value, error)`, channels | `net/http` | `coder/websocket`, auto-reconnect | Go 1.22+ |

## Features per client

All seven clients support the same schema-driven features:

| Feature | Dart | Java | TypeScript | Kotlin | Swift | Python | Go |
|---|---|---|---|---|---|---|---|
| Typed queries and mutations | yes | yes | yes | yes | yes | yes | yes |
| Subscriptions (graphql-ws) with auto-reconnect | yes | yes | yes | yes | yes | yes | yes |
| [REST operations](rest-client.md) (`@glRest`) | yes | yes | yes | yes | yes | yes | yes |
| [Caching](caching.md) (`@glCache`, tags, `staleIfOffline`) | yes | yes | yes | yes | yes | yes | yes |
| [Persisted queries](persisted-queries.md) (APQ, optional GET) | yes | yes | yes | yes | yes | yes | yes |
| File uploads with streaming and progress | yes | yes | yes | yes | yes | yes | yes |
| `@glCaptureErrors` (data and errors together) | yes | yes | yes | yes | yes | yes | yes |
| [Custom scalar codecs](configuration.md) (`typeMappings` objects, `jsonType`) | yes | yes | yes | yes | yes | yes | yes |
| [Custom queries and mutations](custom-queries.md) | yes | yes | yes | yes | yes | yes | yes |

Some features belong to one target:

| Feature | Target |
|---|---|
| Reactive client (Reactor, RxJava 3, Mutiny) | Java (`asyncStyle`) |
| RxJS observables | TypeScript (`observables: true`) |
| Flutter display widgets and input forms | Dart (`flutter` config block) |
| Barrel / index file | Dart and TypeScript |

## Servers

| Server | Language | Generates |
|---|---|---|
| [Spring Boot](spring-server.md) | Java or Kotlin, MVC or WebFlux | controllers, service interfaces, repository stubs, types and inputs |
| [Express / Apollo](express-apollo.md) | TypeScript | service interfaces, Apollo resolvers, DataLoader batch mappings, `graphql-ws` subscriptions, optional `createServer(services)` |

Server-only directives such as `@glSkipOnServer`, `@glSkipOnClient`, `@glIntercept` and `@glServerLenient` are described in [Directives](directives.md) and [Skip directives](skip-directives.md).

## One schema, every target

```yaml title="glink.yaml"
schemaPaths:
  - schema/*.graphql
mode: client
outputDir: src/generated
clientConfig:
  typescript:
    httpAdapter: fetch
```

Run `glink` once per config file (or one config per target) and every language regenerates from the same schema in milliseconds. See [Getting Started](getting-started.md) for a config per target and the [configuration reference](configuration.md) for every option.
