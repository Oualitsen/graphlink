# GraphLink

**GraphLink** is a powerful code generation tool that generates type-safe client and server code from GraphQL schemas for `Dart`, `Flutter`, `Java`, and `Spring Boot` — with more languages coming.

Define your GraphQL schema once. GraphLink wires both ends: on the front you call generated functions, on the back you implement generated interfaces.

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Code Generation](#code-generation)
4. [GraphQL Client](#graphql-client)
5. [Caching](#caching)
6. [Generate Code with Build Runner](#generate-code-with-build-runner)
7. [License](#license)

## Installation

To add **GraphLink** to your project, follow these steps:

- Using Dart's `pub` package manager:

  ```bash
        pub add --dev graphlink
  ```

- If you are working with Flutter:

  ```bash
        flutter pub add --dev graphlink
  ```

## Getting Started

1. **Define your GraphQL schema** — GraphLink reads it and generates all the boilerplate for you.
2. **Configure** how and where to generate code (see [Configuration](#configuration)).
3. **Run the generator** — you get a fully-typed client ready to use.

---

## Configuration

GraphLink supports two configuration styles.

### `config.json` (recommended for Java / CLI)

Create a `config.json` next to your schema:

```json
{
    "schemaPaths": ["schema/*.gql"],
    "mode": "client",
    "typeMappings": {
        "ID": "String",
        "Float": "Double",
        "Int": "Integer",
        "Boolean": "Boolean"
    },
    "outputDir": "src/main/java/com/example/generated",
    "clientConfig": {
        "java": {
            "packageName": "com.example.generated",
            "generateAllFieldsFragments": true,
            "autoGenerateQueries": true,
            "immutableInputFields": true,
            "immutableTypeFields": true
        }
    }
}
```

Then generate:

```bash
dart run lib/generate.dart
```

### `build.yaml` (Dart / Flutter projects)

```yaml
targets:
  $default:
    builders:
      graphlink|aggregatingBuilder:
        enabled: true
        generate_for:
          include:
            - lib/**/*.graphql
        options:
          ID: String
          generateAllFieldsFragments: true
          nullableFieldsRequired: false
          autoGenerateQueries: true
```

Then generate:

```bash
flutter pub run build_runner build -d
```

## Code Generation

The code generation process involves:

1. **Schema Parsing**:

   - The tool parses your GraphQL schema, queries, and mutations to generate Dart classes.

2. **Type Classes**:

   - Generates classes for representing data structures defined in your schema.

3. **Enums**:

   - Creates enums for enumerated types in your schema.

4. **Input Classes**:

   - Generates input classes for GraphQL input types, simplifying data interaction.

5. **JSON Serialization/Deserialization**:

   - GraphLink generates `toJson`/`fromJson` methods directly — no need for `json_serializable`.

6. **Custom Type Names**:

   - The tool recognizes the `@gqTypeName(name:"YourCustomName")` directive in your GraphQL schema, allowing you to specify custom names for response types. This feature enables you to control the naming of generated Dart classes for specific response types.

7. **Generate All Fields Fragments**:

   - By enabling the `generateAllFieldsFragments` option in your build configuration, you can automatically generate fragments for all types. These fragments simplify the retrieval of all attributes for a specific class, allowing you to access them like this: `{... _all_fields_YourClassName}` or just `{... _all_fields}`. This feature enhances the ease of working with the generated Dart classes.

## GraphQL Client


1. **Initialize the Client**:

To initialize the GraphQL client, you can use the following code. This configuration sets up the client with WebSocket and HTTP adapters:

```dart
    const wsUrl = "ws://localhost:8080/graphql";
    const url = "http://localhost:8080/graphql";

    // Create a WebSocket channel adapter for subscriptions.
    var wsAdapter = WebSocketChannelAdapter(wsUrl); // this is optional

    // Define an HTTP request function for queries and mutations.
    var httpFn = (payload) => http
        .post(Uri.parse(url),
            body: payload, headers: {"Content-Type": "application/json"})
        .asStream()
        .map((response) => response.body)
        .first;

    // Create a GQClient with the HTTP and WebSocket adapters.
    var client = GQClient(httpFn, wsAdapter);
```

2. **Execute GraphQL Operations**:

You can use the GraphQL client to send queries, mutations, and subscriptions. The following code example demonstrates how to retrieve data with a query:

```dart
     // Send a query to the server and receive the response as a Future.
    var response = await client.queries.getUserById(id: "test");

     // handle the value found in response.getUserById
     // if the request fails, an exeption will be throuwn

```

The client.queries.getUser method sends a GraphQL query to the server, and the response is processed in the stream. You can adapt this example to perform mutations and subscriptions as needed.

3. **Working with Data Payloads**:

   The client seamlessly handles data payloads using the provided adapter for JSON data transmission. It Generates `inputs` as `classes` using the same name with named parameters.

4. **Error Handling**:

   The generated client includes error handling mechanisms for GraphQL errors and exceptions.

## Caching

GraphLink has built-in client-side caching for both Dart and Java clients. You control it directly in your schema using two directives.

### `@glCache` — cache a query result

```graphql
type Query {
  getCar(id: ID!): Car! @glCache(ttl: 60, tags: ["cars"])
}
```

| argument | description |
|---|---|
| `ttl` | How long (in seconds) the result stays fresh |
| `tags` | Groups this entry belongs to — used for targeted invalidation |
| `staleIfOffline` | If `true`, return the expired entry when the network is unavailable instead of throwing |

### `@glCacheInvalidate` — bust cache entries on a mutation

```graphql
type Mutation {
  createCar(input: CreateCarInput!): Car! @glCacheInvalidate(tags: ["cars"])
}
```

After `createCar` completes, all cache entries tagged `"cars"` are evicted. The next `getCar` call will hit the network.

Use `all: true` to wipe the entire cache:

```graphql
  resetEverything: Boolean! @glCacheInvalidate(all: true)
```

### Partial query caching

You can annotate individual fields inside a compound query. GraphLink caches each field independently and only fetches the ones that are missing or expired:

```graphql
query getCarAndOwner($carId: ID!, $ownerId: ID!) @glCache(ttl: 60, tags: ["data"]) {
  car: getCar(id: $carId)   @glCache(ttl: 60, tags: ["cars"]) { ... _all_fields }
  getOwner(id: $ownerId)    @glCache(ttl: 60, tags: ["persons"]) { ... _all_fields }
}
```

If you call `createCar` (which invalidates `"cars"`), the next `getCarAndOwner` call fetches only the car from the server — the owner is still served from cache.

### Dart usage

```dart
// First call — hits the server
final result = await client.queries.getCar(id: '42');

// Second call — served from cache
final cached = await client.queries.getCar(id: '42');

// This mutation invalidates the "cars" tag
await client.mutations.createCar(input: CreateCarInput(make: 'Toyota', model: 'Camry', year: 2023));

// Next call hits the server again
final fresh = await client.queries.getCar(id: '42');
```

### Java usage

```java
GraphLinkClient client = new GraphLinkClient(adapter, encoder, decoder, null);

// First call — hits the server
GetCarResponse result = client.queries.getCar("42");

// Second call — served from cache
GetCarResponse cached = client.queries.getCar("42");

// This mutation invalidates the "cars" tag
client.mutations.createCar(CreateCarInput.builder().make("Toyota").model("Camry").year(2023).build());

// Next call hits the server again
GetCarResponse fresh = client.queries.getCar("42");
```

By default an `InMemoryGraphLinkCacheStore` is used. Pass your own `GraphLinkCacheStore` implementation to the client constructor to use a persistent or shared store.

---

## Generate Code with Build Runner:

After setting up GraphLink in your project, you need to generate code using the `build_runner` tool. To do this, execute the following command in your project's root directory:

```bash
    flutter pub run build_runner watch -d
```

This command triggers the code generation process, which creates a "generated" folder containing the following generated Dart code:

- client.gq.dart: This folder contains generated code for all your queries, mutations, and subscriptions.
- types.gq.dart: Contains code for all generated type classes.
- input.gq.dart: Includes code for generated input classes.
- enums.gq.dart: Contains code for generated enum classes.

Make sure to include these generated files in your project as they are essential for working with GraphLink. These files will be automatically updated as you modify your GraphQL schema and queries.

## License

GraphLink is open-source software released under the MIT License. Review the [LICENSE](LICENSE) file for detailed licensing terms.

For project updates, additional information, reporting issues, or making suggestions, please visit our [GitHub repository](https://github.com/Oualitsen/graphlink).

Thank you for choosing GraphLink to streamline your GraphQL development.
