---
title: Philosophy — GraphLink Docs
description: The GraphLink philosophy — pure code generation, no runtime abstractions, schema as single source of truth, keyword-safe identifiers, and only the fields the server actually needs.
---

# The GraphLink Philosophy

Pure code generation. No runtime abstractions. Only what the server needs.

## What pure code generation means

GraphLink is a code generator, not a runtime library. When you run `glink`, it reads your schema and writes ordinary Dart or Java source files. Those files have zero dependency on GraphLink itself — no base classes to extend, no interfaces to implement, no runtime to ship.

Every generated class is plain Dart or plain Java. A generated `Vehicle` class in Dart is just a Dart class with fields, a constructor, `fromJson`, and `toJson`. A generated `Vehicle.java` is just a POJO with a builder. You could hand-write these classes yourself; GraphLink simply writes them faster and keeps them in sync with your schema.

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

This means you can use `http`, `dio`, `OkHttp`, Spring's `WebClient`, a mock, or anything else. The generated client does not import any HTTP library. You swap the transport at construction time. This makes testing trivial — pass a function that returns a hardcoded JSON string and you have a complete mock client.

## How it compares

GraphLink occupies a distinct position in the GraphQL tooling landscape. Here is a direct comparison with popular alternatives:

| Feature | GraphLink | ferry (Dart) | Apollo (JS/Kotlin) | Manual code |
|---|---|---|---|---|
| Runtime dependency in app | **None** | Yes (ferry, gql) | Yes (Apollo runtime) | None |
| Sends whole schema on request | **No** | Yes | Partial | No |
| Generics at Java call site | **No** | N/A | Yes | Yes |
| Server-side generation | **Yes** | No | Partial | Manual |
| Java client support | **Yes** | No | Kotlin only | Manual |
| Caching directives in schema | **Yes** | No | No | No |
| Partial query caching | **Yes** | No | No | No |
| Spring Boot controller gen | **Yes** | No | No | Manual |
