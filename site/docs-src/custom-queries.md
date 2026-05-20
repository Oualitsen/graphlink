---
title: Custom Queries & Mutations — GraphLink Docs
description: Write your own GraphQL operation documents alongside the schema. Custom queries, mutations, aliases, fragments, multi-resolver queries, and specific field projections — all generate fully typed client methods.
---

# Custom Queries & Mutations

GraphLink has supported hand-written GraphQL operation documents since day one. Write a query or mutation directly in your schema file (or in a separate `.graphql` file) and the generator produces a fully typed client method for it — same as auto-generated ones, with the same caching support.

## Where to write them

Custom operations live in any file matched by `schemaPaths`. You can put them in the same file as the schema or split them into separate files:

```
schema/
  schema.graphql      ← types, queries, mutations, subscriptions
  operations.graphql  ← your custom operation documents
  fragments.graphql   ← shared fragments
```

```json title="glink.json — picking up all files"
{
  "schemaPaths": ["schema/*.graphql"]
}
```

All files are merged before generation. GraphLink treats every `query`, `mutation`, and `subscription` block it finds as an operation to generate a client method for.

---

## Basic custom query

Write a standard GraphQL operation document. Variable names, field selections, and nesting are all yours to define:

```graphql title="schema/operations.graphql"
query fetchUserProfile($id: ID!) {
  getUser(id: $id) {
    id
    firstName
    lastName
    email
  }
}
```

Generated Dart method:

```dart
final res = await client.queries.fetchUserProfile(id: '42');
print(res.getUser.firstName);
print(res.getUser.email);
```

The method name is derived from the operation name (`fetchUserProfile`). The response type is `FetchUserProfileResponse` with a typed `.getUser` field containing only the fields you projected.

---

## Using `_all_fields`

Instead of listing every field manually, use `... _all_fields` to select all fields of the return type. GraphLink resolves it to the correct type-specific fragment automatically:

```graphql
query fetchUser($id: ID!) {
  getUser(id: $id) {
    ... _all_fields
  }
}
```

Or use the explicit form if you prefer:

```graphql
query fetchUser($id: ID!) {
  getUser(id: $id) {
    ... _all_fields_User
  }
}
```

Both are equivalent. `_all_fields` is resolved based on the return type of the field.

---

## Aliases and projections

Any valid GraphQL field selection — with or without aliases — always generates a correctly named and typed response object. The generated field names match your aliases exactly. There is no constraint on what you can project or how you name it.

```graphql
query fetchCarAndOwner($carId: ID!, $ownerId: ID!) {
  vehicle: getCar(id: $carId) {
    ... _all_fields
  }
  owner: getUser(id: $ownerId) {
    firstName
    lastName
  }
}
```

The generated response type has fields named after the aliases:

```dart
final res = await client.queries.fetchCarAndOwner(carId: '1', ownerId: '2');
print(res.vehicle.make);      // alias "vehicle" → getCar result
print(res.owner.firstName);   // alias "owner"   → getUser result
```

Without an alias the field name matches the resolver name. With an alias it matches the alias — always:

```graphql
query fetchSummary($id: ID!) {
  latestCar:    getCar(id: $id)  { make model }
  primaryOwner: getUser(id: $id) { firstName }
  count:        getCarsCount
}
```

```dart
final res = await client.queries.fetchSummary(id: '1');
res.latestCar.make;       // named "latestCar"
res.primaryOwner.firstName; // named "primaryOwner"
res.count;                // named "count", typed int
```

The projected type for each field is generated from the field selection you wrote. If you project `{ make model }` on a `Car`, GraphLink generates a projected type with exactly those two fields. If you project all fields (via `... _all_fields` or explicitly), it reuses the base type.

---

## Multiple resolvers in one query

This is one of the most powerful features. A single custom query can call multiple resolvers and get back one unified, typed response:

```graphql title="Dashboard query — one round trip for everything"
query fetchDashboard($userId: ID!) {
  profile: getUser(id: $userId) {
    ... _all_fields
  }
  cars: getCarsByUser(userId: $userId) {
    ... _all_fields
  }
  count: getNotificationsCount(userId: $userId)
}
```

```dart title="One call, everything typed"
final res = await client.queries.fetchDashboard(userId: session.userId);

print(res.profile.firstName);
print(res.cars.length);
print(res.count);
```

The server receives a single GraphQL request. The response type `FetchDashboardResponse` has a typed field for each resolver in the query.

---

## Custom field projection

You control exactly which fields come back. GraphLink generates a dedicated projected type matching your selection — not the full schema type:

```graphql title="Lean projection — only what the screen needs"
query fetchCarList($page: PageInput!) {
  getCars(page: $page) {
    id
    make
    model
    year
  }
}
```

The response contains only `id`, `make`, `model`, and `year`. GraphLink generates a projected type (e.g. `Car_IdMakeModelYear`) that holds exactly those fields. Nullability from the schema is preserved on each field.

When a projection selects **all** fields of a type, GraphLink is smart enough to reuse the base type directly — no duplicate class is generated.

---

## Custom mutations

Custom mutations follow the same pattern. Select exactly which fields you want from the response:

```graphql title="Custom mutation — specific response fields"
mutation registerCar($input: CreateCarInput!) {
  createCar(input: $input) {
    id
    make
    model
  }
}
```

```dart
final res = await client.mutations.registerCar(
  input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2024),
);
print(res.createCar.id);
```

---

## Shared fragments

Define a fragment once and reuse it across multiple operations:

```graphql title="schema/fragments.graphql"
fragment CarSummary on Car {
  id
  make
  model
  year
}
```

```graphql title="schema/operations.graphql"
query fetchCar($id: ID!) {
  getCar(id: $id) {
    ... CarSummary
  }
}

query fetchCarsAndOwner($ownerId: ID!) {
  getCars(ownerId: $ownerId) {
    ... CarSummary
  }
  getUser(id: $ownerId) {
    firstName
    lastName
  }
}
```

GraphLink resolves fragment spreads and inlines the selected fields into the generated query strings. Your fragments do not need to be in the same file as the operations that use them — any file in `schemaPaths` is visible to all others.

---

## Caching on custom queries

`@glCache` and `@glCacheInvalidate` work exactly the same on custom operations. Apply them at the operation level or per resolver field:

```graphql title="Custom query with caching"
query fetchDashboard($userId: ID!, $page: PageInput!) @glCache(ttl: "5m", tags: ["dashboard"]) {
  profile: getUser(id: $userId) @glCache(ttl: "10m", tags: ["users"]) {
    ... _all_fields
  }
  cars: getCarsByUser(userId: $userId) @glCache(ttl: "2m", tags: ["cars"]) {
    ... _all_fields
  }
}
```

Each resolver is cached independently. If `"cars"` is invalidated, only that resolver is re-fetched on the next call — `profile` stays warm. See [Caching](caching.md) for the full caching reference.

---

## What gets generated

For every custom operation, GraphLink generates:

| Item | Naming convention | Example |
|---|---|---|
| Client method | camelCase of operation name | `fetchDashboard(...)` |
| Response type | `{OperationName}Response` | `FetchDashboardResponse` |
| Method parameters | one per `$variable` | `userId`, `page` |
| Response fields | one per resolver / alias | `.profile`, `.cars`, `.count` |

The method lives under `client.queries`, `client.mutations`, or `client.subscriptions` depending on the operation type. Everything is fully typed — no casting, no dynamic maps.

---

## What most tools get wrong

Most GraphQL code generators fall apart on three things: **interfaces**, **unions**, and **subscriptions**. GraphLink handles all three, including when they are combined.

### Interfaces and inline fragments

Given this schema:

```graphql
interface Animal {
  id: ID!
  name: String!
}

type Dog implements Animal {
  id: ID!
  name: String!
  breed: String!
}

type Cat implements Animal {
  id: ID!
  name: String!
  indoor: Boolean!
}

type Query {
  getAnimal: Animal!
}
```

Write an inline fragment query projecting different fields per concrete type:

```graphql
query fetchAnimal {
  getAnimal {
    ... on Dog { id name breed }
    ... on Cat { id name indoor }
  }
}
```

GraphLink generates:

- An **abstract base class** `Animal_` with a `fromJson` factory that dispatches on `__typename`
- Concrete classes `Dog_IdNameBreed` and `Cat_IdNameIndoor`, each implementing `Animal_`
- `FetchAnimalResponse` with `getAnimal` typed as `Animal_`

```dart title="Usage — fully typed, no casting"
final res = await client.queries.fetchAnimal();
final animal = res.getAnimal;

switch (animal) {
  case Dog_IdNameBreed dog:
    print('Dog: ${dog.breed}');
  case Cat_IdNameIndoor cat:
    print('Cat, indoor: ${cat.indoor}');
}
```

The compiler knows every possible concrete type. No `Map<String, dynamic>`. No manual `__typename` checks. No casting.

---

### Unions

Unions work the same way. Each member type gets a concrete class implementing the generated abstract union base:

```graphql
union SearchResult = Car | Owner | Driver

type Query {
  search(term: String!): [SearchResult!]!
}

query runSearch($term: String!) {
  search(term: $term) {
    ... on Car   { id make model }
    ... on Owner { id name email }
    ... on Driver { id name licenseNumber }
  }
}
```

Generated abstract class `SearchResult_` with concrete `Car_IdMakeModel`, `Owner_IdNameEmail`, `Driver_IdNameLicenseNumber` — all dispatched from `fromJson` based on `__typename`. The `search` field on the response is `List<SearchResult_>` — fully typed, no generics needed at the call site.

---

### Subscriptions

Subscriptions generate a `Stream` of the typed response — not `Stream<dynamic>`, not `Stream<Map<String, dynamic>>`:

```graphql
type Subscription {
  newNotification(userId: ID!): Notification!
}

subscription watchNotifications($userId: ID!) {
  newNotification(userId: $userId) {
    id
    message
    createdAt
  }
}
```

```dart title="Typed subscription stream"
client.subscriptions.watchNotifications(userId: session.userId).listen((event) {
  // event is WatchNotificationsResponse — fully typed
  print(event.newNotification.message);
  print(event.newNotification.createdAt);
});
```

The generated WebSocket adapter handles the `graphql-ws` protocol, connection init, ping/pong, and exponential-backoff reconnect automatically.

---

### All three together

The real test: a subscription that returns a **union type**, requiring inline fragments to distinguish the concrete type at runtime. Most tools give up here. GraphLink generates it correctly:

```graphql
union FeedEvent = NewMessage | UserJoined | UserLeft

type Subscription {
  feedEvents(roomId: ID!): FeedEvent!
}

subscription watchFeed($roomId: ID!) {
  feedEvents(roomId: $roomId) {
    ... on NewMessage { authorName text sentAt }
    ... on UserJoined { username joinedAt }
    ... on UserLeft   { username leftAt reason }
  }
}
```

```dart title="Typed stream of a union — no boilerplate"
client.subscriptions.watchFeed(roomId: room.id).listen((event) {
  final feed = event.feedEvents; // typed as FeedEvent_

  switch (feed) {
    case NewMessage_AuthorNameTextSentAt msg:
      chatLog.add('[${msg.authorName}] ${msg.text}');
    case UserJoined_UsernameJoinedAt join:
      chatLog.add('${join.username} joined');
    case UserLeft_UsernameLeftAtReason left:
      chatLog.add('${left.username} left: ${left.reason}');
  }
});
```

Every event is dispatched by `__typename`, every concrete type is fully typed, and the stream reconnects automatically on disconnect. This is what most GraphQL tools describe as "coming soon."
