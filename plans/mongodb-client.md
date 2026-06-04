# MongoDB Direct Client — Design Plan

## Goal

Generate a fully type-safe Java client that talks directly to MongoDB using the MongoDB
Java driver. No HTTP. No GraphQL server. No Spring. The GraphQL schema is the single
source of truth for types, collections, queries, and mutations.

```
GraphQL schema + (optional) operation files
              ↓ glink
Generated Java client (POJOs + projections + filters + pipeline constants)
              ↓ at runtime
MongoDB Java driver → MongoDB
```

Usage:
```java
var client = new GraphLinkClient("mongodb://localhost:27017");
User user = client.queries.getUser("abc123");
User user = client.queries.getUser("abc123",
    new UserProjection().id().name().posts(new PostProjection().title())
);
List<User> users = client.queries.getUsers(
    new UserFilter().name("John"),
    new UserProjection().id().name()
);
client.mutations.createUser(new CreateUserInput("John", "john@example.com"));
```

---

## Core design decisions (settled)

### 1. Static pipeline strings — match only, no projection baked in

Like GraphQL query strings, GraphLink generates a static MongoDB aggregation pipeline
constant per query. The constant contains only the stages that are always present
(typically `$match`). Projection and `$lookup` stages are added dynamically at runtime.

```java
// Generated constant
static final String GET_USER_PIPELINE =
  "[{\"$match\":{\"_id\":{\"$glParam\":\"id\"}}}]";
```

Rationale: the caller (server code) decides which fields it needs. Baking projections
into the generated string would require per-operation response classes (like HTTP client
mode does), which is inappropriate here.

### 2. All fields nullable — one class per type

Unlike HTTP client mode which generates projection-specific response classes
(`User_id_name`, `UserWithPostsResponse`, etc.), the MongoDB client generates a single
`User` class with all fields nullable. If a field was excluded from the projection,
it is `null` in the returned object.

```java
public class User {
    public String id;        // null if not projected
    public String name;      // null if not projected
    public String email;     // null if not projected
    public List<Post> posts; // null if not projected or @glRef not joined
    public Address address;  // null if not projected (embedded)
}
```

### 3. Dynamic projection — `UserProjection` fluent builder

Each type gets a generated `Projection` class with a fluent API. Requesting a
`@glRef` field in the projection automatically adds the corresponding `$lookup` stage
to the pipeline at runtime. No directive needed to toggle joins — it's projection-driven.

```java
public class UserProjection {
    final Document fields = new Document();

    public UserProjection id()    { fields.put("_id", 1);  return this; }
    public UserProjection name()  { fields.put("name", 1); return this; }
    public UserProjection email() { fields.put("email", 1); return this; }

    // requesting posts → adds $lookup at runtime
    public UserProjection posts(PostProjection proj) {
        fields.put("posts", proj.fields);
        return this;
    }
    // embedded types — no $lookup, just nested projection
    public UserProjection address(AddressProjection proj) {
        fields.put("address", proj.fields);
        return this;
    }
}
```

### 4. Parameter substitution — sentinel pattern

Pipeline templates use `{"$glParam": "argName"}` sentinel objects. A generated
`GlPipeline` utility (emitted into the output package, not a runtime dep) walks the
parsed document tree and replaces sentinels with properly-typed BSON values.

```java
List<Bson> pipeline = GlPipeline.build(
    GET_USER_PIPELINE,
    GlParam.objectId("id", id),   // replaces {"$glParam":"id"} → new ObjectId(id)
    GlParam.string("name", name)  // etc.
);
```

This ensures parameters are never string-concatenated into JSON (avoids injection).

### 5. Collection naming — convention + override

`type User` → `users` collection (lowercase + pluralize).
`type Category` → `categories`.
Override with `@glCollection(name: "my_users")` on the type.

### 6. Auto-generated filter types

GraphLink generates a `UserFilter` class automatically from the `User` type. The
developer does not define it. The generated filter supports at minimum equality on
every scalar field. Extended operators (range, `$in`, regex) are discussed in open
questions below.

### 7. Subscriptions — deferred

MongoDB Change Streams will not be in v1. Deferred to a later plan.

### 8. Operation files — optional

The API surface (query/mutation method names and signatures) is derived directly from
the `Query` and `Mutation` types in the schema. Operation `.graphql` files are not
required. They may be used in a future iteration for custom aggregation pipelines
(`$group`, `$unwind`, `$facet`) that cannot be expressed through schema Query fields
alone.

---

## Schema directives

### Type-level

| Directive | Arguments | Meaning |
|---|---|---|
| `@glCollection(name)` | `name: String` | Override collection name (default: pluralized lowercase type name) |
| `@glEmbed` | — | This type is always embedded; never gets its own collection |

### Field-level

| Directive | Arguments | Meaning |
|---|---|---|
| `@glRef` | — | This field is a reference to another collection (default for object/list fields whose type has `@glCollection` or follows naming convention) |
| `@glEmbed` | — | Force embedding this field's type inside the parent document |
| `@glField(name)` | `name: String` | Override the MongoDB field name for this GraphQL field |
| `@glId` | — | Mark this field as the MongoDB `_id` field (default: the `id: ID` field) |

### Query/Mutation field-level

| Directive | Arguments | Meaning |
|---|---|---|
| `@glFindOne(by)` | `by: String` | Find one document matching the named field (for non-ID single lookups) |
| `@glFind(by, sort, limitArg, skipArg)` | various | Custom find with field match, sort, and pagination args |
| `@glMatch(field, arg)` | strings | Map a specific query arg to a specific document field |

> Most common patterns are inferred without directives (see section below).

---

## Query/Mutation → MongoDB operation inference

The generator infers the MongoDB operation from the Query/Mutation field signature.
Explicit directives override inference for edge cases.

### Inferred patterns (no directive needed)

| Signature pattern | Inferred operation |
|---|---|
| `(id: ID!): T` | `findById` — match on `_id` |
| `(): [T!]!` | `findAll` — no filter |
| `(filter: TFilter): [T!]!` | `find(filter)` |
| `(filter: TFilter!): [T!]!` | `find(filter)` |
| Mutation `(input: CreateTInput!): T!` | `insertOne` |
| Mutation `(id: ID!, input: UpdateTInput!): T!` | `findOneAndUpdate` |
| Mutation `(id: ID!): Boolean!` | `deleteOne` |
| Mutation `(inputs: [CreateTInput!]!): [T!]!` | `insertMany` |

### Directive-required cases

```graphql
type Query {
  # non-ID single lookup — generator can't infer which field
  userByEmail(email: String!): User   @glFindOne(by: "email")

  # custom field name differs from arg name
  usersByCity(city: String!): [User!]!  @glFind(by: "address.city")

  # pagination args
  users(filter: UserFilter, limit: Int, skip: Int): [User!]!
    @glFind(limitArg: "limit", skipArg: "skip")
}
```

---

## Generated files per type

For `type User { id: ID!, name: String!, email: String!, posts: [Post!]! @glRef }`:

| File | Contents |
|---|---|
| `User.java` | POJO, all fields nullable, `fromDocument(Document)`, `toDocument()` |
| `UserProjection.java` | Fluent projection builder; controls `$project` and `$lookup` presence |
| `UserFilter.java` | Auto-generated filter input; `toFilter()` returns a `Bson` |

For the schema as a whole:

| File | Contents |
|---|---|
| `GraphLinkClient.java` | Entry point; holds `queries` and `mutations` instances; owns `MongoClient` lifecycle |
| `GraphLinkQueries.java` | One typed method per `Query` field |
| `GraphLinkMutations.java` | One typed method per `Mutation` field |
| `GlPipeline.java` | Emitted utility — param substitution (`build`, `GlParam.*`) |

---

## Pipeline construction at runtime

For a query with a `@glRef` field:

```java
// Generated inside GraphLinkQueries
public User getUser(String id, UserProjection projection) {
    List<Bson> pipeline = GlPipeline.build(
        GetUserPipelines.FIND_BY_ID,
        GlParam.objectId("id", id)
    );
    // $lookup added only if posts was included in projection
    if (projection != null && projection.fields.containsKey("posts")) {
        pipeline.add(buildPostsLookup(projection));
    }
    if (projection != null) {
        pipeline.add(new Document("$project", projection.fields));
    }
    Document doc = db.getCollection("users").aggregate(pipeline).first();
    return doc != null ? User.fromDocument(doc) : null;
}

private Bson buildPostsLookup(UserProjection projection) {
    // Generated $lookup for the posts @glRef field
    Document lookupDoc = new Document("from", "posts")
        .append("localField", "_id")
        .append("foreignField", "userId")
        .append("as", "posts");
    Object postProj = projection.fields.get("posts");
    if (postProj instanceof Document) {
        lookupDoc.append("pipeline", List.of(
            new Document("$project", postProj)
        ));
    }
    return new Document("$lookup", lookupDoc);
}
```

---

## Auto-generated `UserFilter`

```java
public class UserFilter {
    private final List<Bson> conditions = new ArrayList<>();

    public UserFilter id(String value)    { conditions.add(eq("_id", new ObjectId(value))); return this; }
    public UserFilter name(String value)  { conditions.add(eq("name", value)); return this; }
    public UserFilter email(String value) { conditions.add(eq("email", value)); return this; }

    public Bson toFilter() {
        return conditions.isEmpty() ? new Document() : and(conditions);
    }
}
```

> Open question: extended operators — see below.

---

## Type mappings

| GraphQL scalar | Java type | MongoDB BSON type |
|---|---|---|
| `ID` | `String` | `ObjectId` (auto-converted) |
| `String` | `String` | String |
| `Int` | `Integer` | Int32 |
| `Float` | `Double` | Double |
| `Boolean` | `Boolean` | Boolean |
| `DateTime` (custom) | `java.time.Instant` | Date |
| Custom scalars | configurable via `typeMappings` | — |

`ID` fields are always stored as `ObjectId` in MongoDB and exposed as `String` in Java.
The generated `fromDocument` / `toDocument` handles the conversion transparently.

---

## Config shape

```json
{
  "schemaPaths": ["schema/*.gql"],
  "mode": "client",
  "clientConfig": {
    "java": {
      "packageName": "com.example.generated",
      "mongodb": {
        "database": "mydb"
      }
    }
  }
}
```

The database name is baked into the generated `GraphLinkClient` so the caller only
provides the connection string:

```java
var client = new GraphLinkClient("mongodb://localhost:27017");
// or
var client = new GraphLinkClient(mongoClientSettings);
```

---

## Generator / serializer architecture

Following the existing pattern:

| New file | Responsibility |
|---|---|
| `generators/java_mongodb_generator.dart` | Entry point; decides which files to emit, orchestrates serializers |
| `serializers/java_mongodb_serializer.dart` | Emits `User.java`, `UserProjection.java`, `UserFilter.java` per type |
| `serializers/java_mongodb_client_serializer.dart` | Emits `GraphLinkClient.java`, `GraphLinkQueries.java`, `GraphLinkMutations.java` |
| `serializers/java_mongodb_pipeline_serializer.dart` | Emits pipeline constant strings per query |
| `serializers/java_mongodb_utils_serializer.dart` | Emits `GlPipeline.java` (utility, not a runtime dep) |

New config type in `config.dart`:
```dart
class JavaMongoDbConfig {
  final String database;
  JavaMongoDbConfig.fromJson(Map<String, dynamic> json)
      : database = json['database'] as String;
}
```

Wire into `main.dart` dispatch: when `clientConfig.java.mongodb` is present, run
`JavaMongoDbGenerator` in addition to (or instead of) the regular Java HTTP generator.

---

## Build order

1. `config.dart` — add `JavaMongoDbConfig`
2. `model/built_in_directive_definitions.dart` — register `@glCollection`, `@glRef`,
   `@glEmbed`, `@glField`, `@glId`, `@glFindOne`, `@glFind`, `@glMatch`
3. `gl_grammar_extension.dart` — add getters: `isMongoCollection`, `mongoCollectionName`,
   `mongoRefFields`, `mongoEmbedFields`, `mongoIdField`
4. `generators/java_mongodb_generator.dart`
5. `serializers/java_mongodb_serializer.dart` — POJOs + projections + filters
6. `serializers/java_mongodb_pipeline_serializer.dart` — pipeline constants
7. `serializers/java_mongodb_client_serializer.dart` — client + queries + mutations
8. `serializers/java_mongodb_utils_serializer.dart` — `GlPipeline.java`
9. `main.dart` — wire new generator
10. Tests under `test/mongodb/`

---

## Open questions

**OQ1 — Filter operators scope**
Should `UserFilter` support only equality (`eq`), or also:
- Range: `nameGt`, `nameLt`, `nameGte`, `nameLte`
- Set membership: `nameIn(List<String>)`
- Null check: `nameIsNull()`
- Regex: `nameMatches(String pattern)`

Options:
- A: equality only for v1, extended operators in v2
- B: generate the full operator set upfront (more generated code, more useful immediately)
- C: a `@glFilterable(operators: [EQ, IN, RANGE])` directive per field to opt into specific operators

**OQ2 — Relationship foreign key convention**
For `posts: [Post!]! @glRef`, the generator needs to know:
- That the join is `users._id → posts.userId`
- `userId` is the convention (parent type name + "Id", camelCase)

Is this convention acceptable, or do we need `@glRef(foreignField: "userId")`?
What about `@glRef` on the `Post` side pointing back to `User`?

**OQ3 — Pagination on list queries**
For `getUsers(filter?)`, should the generated method support pagination out of the box?
Options:
- A: no pagination in v1, caller adds `skip`/`limit` via directive if needed
- B: always generate `getUsers(filter?, skip?, limit?, sort?)` with optional pagination params
- C: generate a `UserPage` result type with `items` and `totalCount`

**OQ4 — Mutation return strategy**
For `createUser(input): User!`:
- A: return the inserted document as-is (no re-fetch, projection not applied)
- B: re-fetch after insert using the generated `id` (applies projection, one extra round trip)
- C: return only the generated `id` and let the caller fetch if they need more fields

**OQ5 — Error handling**
When `getUser(id)` finds no document:
- A: return `null`
- B: throw a generated `GlNotFoundException`
- C: return `Optional<User>` (Java idiomatic)

**OQ6 — Config mode**
Should MongoDB mode be a completely separate `mode` value (`"mode": "mongodb-client"`)
or a sub-config under the existing `"mode": "client"` (as shown above)?
Separate mode is cleaner but requires more dispatch changes in `main.dart`.

**OQ7 — Multi-language sharing**
Kotlin and Dart are future MongoDB targets. The pipeline constant strings (JSON) are
identical across languages — only deserialization and param-building are language-specific.
Should the pipeline constants be emitted into a shared `.json` file that all language
generators read, or kept as string literals in each language's generated code?

**OQ8 — `@glEmbed` default behavior**
If a field's type has no `@glCollection` and is not a scalar/enum, should the generator
default to embedding it (no `@glRef`)? This would mean `Address` (no `@glCollection`)
is always embedded, while `Post` (has `@glCollection` / follows naming convention) is
always a reference. Does this convention hold?
