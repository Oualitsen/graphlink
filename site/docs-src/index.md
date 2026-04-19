---
title: Documentation — GraphLink
description: Complete GraphLink documentation — from installation and first schema to Dart/Flutter, Java, and TypeScript clients, Spring Boot server generation, and built-in caching.
---

# Documentation

Everything you need to know about GraphLink — from first schema to production deployment.

<div class="grid cards" markdown>

- **[Philosophy](philosophy.md)** — Why pure code generation? Why no runtime abstractions?
- **[Getting Started](getting-started.md)** — Zero to generated code in 5 minutes.
- **[Dart / Flutter Client](dart-client.md)** — Typed queries, mutations, subscriptions. Adapter pattern.
- **[Java Client](java-client.md)** — No generics. No casting. Builder pattern on all inputs.
- **[TypeScript Client](typescript-client.md)** — Typed client for Angular, React, Vue, and Node.
- **[Spring Boot](spring-server.md)** — Generated controllers, service interfaces, types, inputs.
- **[Caching](caching.md)** — `@glCache` and `@glCacheInvalidate`. Tag-based invalidation.
- **[Directives](directives.md)** — Complete reference for all GraphLink directives.
- **[Configuration](configuration.md)** — Every `config.json` option explained.

</div>

## The schema used throughout these docs

All examples in this documentation use the following schema. It covers every major GraphLink feature: types, enums, inputs, queries, mutations, subscriptions, and cache directives.

```graphql title="schema.graphql"
enum FuelType {
  GASOLINE
  DIESEL
  ELECTRIC
  HYBRID
}

type Person {
  id: ID!
  name: String!
  email: String!
  vehicles: [Vehicle!]!
}

type Vehicle {
  id: ID!
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
  ownerId: ID
}

input AddPersonInput {
  name: String!
  email: String!
}

input AddVehicleInput {
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
  ownerId: ID
}

type Query {
  getPerson(id: ID!): Person
  getVehicle(id: ID!): Vehicle!  @glCache(ttl: 120, tags: ["vehicles"])
  listVehicles: [Vehicle!]!      @glCache(ttl: 60,  tags: ["vehicles"])
}

type Mutation {
  addPerson(input: AddPersonInput!): Person!
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}

type Subscription {
  vehicleAdded: Vehicle!
}
```

!!! info "What this schema exercises"
    `FuelType` is an enum — GraphLink generates serialization in both directions. `Person` and `Vehicle` are types with nullable/non-nullable fields. `AddPersonInput` and `AddVehicleInput` are input types. `getVehicle` and `listVehicles` use `@glCache` with tags. `addVehicle` uses `@glCacheInvalidate` — when it runs, all entries tagged `"vehicles"` are evicted. `vehicleAdded` is a subscription backed by a WebSocket connection.
