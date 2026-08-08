---
title: Getting Started — GraphLink Docs
description: Install the GraphLink CLI, write your first GraphQL schema, configure the generator, and produce type-safe Dart, Java, TypeScript, Kotlin, and Swift code in under 5 minutes.
---

# Getting Started

From zero to generated code in under 5 minutes.

## Step 1 — Download the CLI

The GraphLink CLI is distributed as a single self-contained binary called `glink`. No runtime, no package manager, no JVM required.

=== "Linux / macOS"

    ```bash
    # Download the latest release
    curl -fsSL https://github.com/Oualitsen/graphlink/releases/latest/download/glink-linux-x64 -o glink

    # Make it executable
    chmod +x glink

    # Move to your PATH
    sudo mv glink /usr/local/bin/glink

    # Verify
    glink --version
    ```

=== "Windows"

    ```powershell
    # Download via PowerShell
    Invoke-WebRequest `
      -Uri "https://github.com/Oualitsen/graphlink/releases/latest/download/glink-windows-x64.exe" `
      -OutFile "glink.exe"

    # Add to PATH or run from current directory
    .\glink.exe --version
    ```

=== "Docker"

    A multi-arch (`linux/amd64` + `linux/arm64`) image is published to Docker Hub as
    [`oualitsen/graphlink`](https://hub.docker.com/r/oualitsen/graphlink) — no local
    binary, no PATH setup:

    ```bash
    # Mount your project directory and run glink against it
    docker run --rm -v "$PWD":/workspace -w /workspace \
      oualitsen/graphlink:latest -c glink.json

    # Pin to a specific version instead of "latest"
    docker run --rm -v "$PWD":/workspace -w /workspace \
      oualitsen/graphlink:5.0.0 --version
    ```

    The container's entrypoint is `glink` itself — everything after the image name is
    passed straight through as CLI arguments (`-c`, `-w`, `--version`, `--help`, ...).
    Useful for CI pipelines that shouldn't depend on a language runtime just to run the
    generator.

=== "Manual"

    ```
    Visit: https://github.com/Oualitsen/graphlink/releases/latest

    Download the binary for your platform:
      glink-linux-x64       — Linux (x86_64)
      glink-linux-arm64     — Linux (ARM64 / Raspberry Pi)
      glink-macos-x64       — macOS (Intel)
      glink-macos-arm64     — macOS (Apple Silicon)
      glink-windows-x64.exe — Windows (x86_64)

    Place the binary somewhere on your PATH and make it executable.
    ```

## Step 2 — Write your schema

Create a `schema/` directory and save your GraphQL schema as one or more `.graphql` or `.gql` files. Here is the schema used throughout this documentation:

```graphql title="schema/schema.graphql"
# An enum — GraphLink generates serialization in both directions
enum FuelType {
  GASOLINE
  DIESEL
  ELECTRIC
  HYBRID
}

# A type — generates a model class with fromJson/toJson (Dart) or builder + getters (Java)
type Person {
  id: ID!        # ID maps to String in both Dart and Java
  name: String!
  email: String!
  vehicles: [Vehicle!]!  # nested list — fully typed
}

type Vehicle {
  id: ID!
  brand: String!
  model: String!
  year: Int!
  fuelType: FuelType!
  ownerId: ID    # nullable — String? in Dart, @Nullable String in Java
}

# Input types — generate immutable input classes with builders
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

# Queries — @glCache caches the result; ttl as duration string; tags for group invalidation
type Query {
  getPerson(id: ID!): Person
  getVehicle(id: ID!): Vehicle!  @glCache(ttl: "2m", tags: ["vehicles"])
  listVehicles: [Vehicle!]!      @glCache(ttl: "1m", tags: ["vehicles"])
}

# Mutations — @glCacheInvalidate evicts all entries with matching tags on success
type Mutation {
  addPerson(input: AddPersonInput!): Person!
  addVehicle(input: AddVehicleInput!): Vehicle! @glCacheInvalidate(tags: ["vehicles"])
}

# Subscriptions — backed by a WebSocket connection
type Subscription {
  vehicleAdded: Vehicle!
}
```

!!! info "Splitting a type's body across files (v5.0.0+)"
    A `type`, `interface`, or `input` can now be declared with no body at all (`type Query { }`) as long as a later `extend` block somewhere in `schemaPaths` supplies its fields. GraphLink raises a validation error if a bodyless definition is never extended. This is useful for schemas split across multiple files where the root type is declared in one file and extended per-feature in others.

## Step 3 — Configure the generator

Create a config file in your project root. GraphLink accepts **JSON** (`.json`), **YAML** (`.yaml`), or **YML** (`.yml`). Name it `glink.json` / `glink.yaml` / `glink.yml` and the `-c` flag becomes optional — `glink` finds it automatically.

=== "Dart / Flutter"

    === "JSON"

        ```json title="glink.json"
        {
          "schemaPaths": ["schema/*.graphql"],
          "mode": "client",
          "typeMappings": {
            "ID":      "String",
            "String":  "String",
            "Float":   "double",
            "Int":     "int",
            "Boolean": "bool",
            "Null":    "null"
          },
          "outputDir": "lib/generated",
          "clientConfig": {
            "dart": {
              "packageName": "my_app",
              "generateAllFieldsFragments": true,
              "autoGenerateQueries": true,
              "nullableFieldsRequired": false,
              "immutableInputFields": true,
              "immutableTypeFields": true
            }
          }
        }
        ```

    === "YAML"

        ```yaml title="glink.yaml"
        schemaPaths:
          - schema/*.graphql
        mode: client
        typeMappings:
          ID: String
          String: String
          Float: double
          Int: int
          Boolean: bool
          Null: null
        outputDir: lib/generated
        clientConfig:
          dart:
            packageName: my_app
            generateAllFieldsFragments: true
            autoGenerateQueries: true
            nullableFieldsRequired: false
            immutableInputFields: true
            immutableTypeFields: true
        ```

=== "Java client"

    === "JSON"

        ```json title="glink.json"
        {
          "schemaPaths": ["schema/*.graphql"],
          "mode": "client",
          "typeMappings": {
            "ID":      "String",
            "String":  "String",
            "Float":   "Double",
            "Int":     "Integer",
            "Boolean": "Boolean",
            "Null":    "null"
          },
          "outputDir": "src/main/java/com/example/generated",
          "clientConfig": {
            "java": {
              "packageName": "com.example.generated",
              "generateAllFieldsFragments": true,
              "autoGenerateQueries": true,
              "nullableFieldsRequired": false,
              "immutableInputFields": true,
              "immutableTypeFields": true
            }
          }
        }
        ```

    === "YAML"

        ```yaml title="glink.yaml"
        schemaPaths:
          - schema/*.graphql
        mode: client
        typeMappings:
          ID: String
          String: String
          Float: Double
          Int: Integer
          Boolean: Boolean
          Null: null
        outputDir: src/main/java/com/example/generated
        clientConfig:
          java:
            packageName: com.example.generated
            generateAllFieldsFragments: true
            autoGenerateQueries: true
            nullableFieldsRequired: false
            immutableInputFields: true
            immutableTypeFields: true
        ```

=== "Spring Boot"

    === "JSON"

        ```json title="glink.json"
        {
          "schemaPaths": ["schema/*.graphql"],
          "mode": "server",
          "typeMappings": {
            "ID":      "String",
            "String":  "String",
            "Float":   "Double",
            "Int":     "Integer",
            "Boolean": "Boolean",
            "Null":    "null"
          },
          "outputDir": "src/main/java/com/example/generated",
          "serverConfig": {
            "spring": {
              "basePackage": "com.example.generated",
              "generateControllers": true,
              "generateRepositories": false,
              "immutableInputFields": true,
              "immutableTypeFields": false
            }
          }
        }
        ```

    === "YAML"

        ```yaml title="glink.yaml"
        schemaPaths:
          - schema/*.graphql
        mode: server
        typeMappings:
          ID: String
          String: String
          Float: Double
          Int: Integer
          Boolean: Boolean
          Null: null
        outputDir: src/main/java/com/example/generated
        serverConfig:
          spring:
            basePackage: com.example.generated
            generateControllers: true
            generateRepositories: false
            immutableInputFields: true
            immutableTypeFields: false
        ```

### Key configuration options explained

| Key | Description |
|---|---|
| `schemaPaths` | Glob patterns for schema files. You can split the schema across multiple files. |
| `mode` | `"client"` generates client code; `"server"` generates Spring Boot scaffolding. |
| `typeMappings` | Maps GraphQL scalar types to language types. Add entries for custom scalars. |
| `outputDir` | Where to write generated files. Existing files are overwritten. |
| `generateAllFieldsFragments` | Generates a `_all_fields_TypeName` fragment per type, used by `autoGenerateQueries`. |
| `autoGenerateQueries` | Generates query strings for every Query/Mutation/Subscription field automatically. |
| `immutableInputFields` | Input class fields are `final` (Dart) or `final` (Java). Inputs become builder-only. |
| `immutableTypeFields` | Response type fields are final. For Spring server, set to `false` so Spring can set fields. |
| `generateControllers` | Spring only. Generates `@Controller` classes wired with `@QueryMapping` etc. |
| `generateRepositories` | Spring only. Generates JpaRepository interfaces for types annotated with `@glRepository`. |

## Step 4 — Run the generator

If your config is named `glink.json`, `glink.yaml`, or `glink.yml`, just run:

```bash title="Terminal"
glink
```

`glink` searches for those filenames from the current directory upward. To use a custom path, pass it explicitly:

```bash title="Terminal"
glink -c my-config.json
```

For the Dart client config, the generator produces 21 files. For the Java client, 38 files. For Spring Boot, 9 files. Here is the Dart output tree:

```
lib/generated/
  client/
    graph_link_client.dart
  enums/
    fuel_type.dart
  inputs/
    add_person_input.dart
    add_vehicle_input.dart
  types/
    vehicle.dart
    person.dart
    get_vehicle_response.dart
    list_vehicles_response.dart
    get_person_response.dart
    add_vehicle_response.dart
    add_person_response.dart
    vehicle_added_response.dart
    graph_link_error.dart
    graph_link_payload.dart
    ... + 6 internal support files
```

And the Spring Boot output:

```
src/main/java/com/example/generated/
  controllers/
    PersonServiceController.java  ← generated, never touch
    VehicleServiceController.java ← generated, never touch
  services/
    PersonService.java  ← implement this
    VehicleService.java ← implement this
  types/
    Person.java
    Vehicle.java
  inputs/
    AddPersonInput.java
    AddVehicleInput.java
  enums/
    FuelType.java
```

!!! info
    The `services/` files are the ones you implement. Controllers are generated and never touched by hand. Types, inputs, and enums are plain data classes.

## Step 5 — What just happened?

The generator processed each section of your schema and produced a corresponding set of files:

### Types → model classes

`type Vehicle` became `vehicle.dart` (Dart) and `Vehicle.java` (Java). Each has all fields, a constructor, and JSON serialization. In Dart, fields are final and the constructor uses named parameters with `required`. In Java, an inner `Builder` class is generated.

### Enums → enum classes with serialization

`enum FuelType` became `fuel_type.dart` and `FuelType.java`, each with `toJson()` and `fromJson()` methods that map to and from the GraphQL string representation.

### Inputs → immutable input classes

`input AddVehicleInput` became `add_vehicle_input.dart` and `AddVehicleInput.java`. Required fields are enforced at construction time. The Java version uses a builder with `Objects.requireNonNull` for required fields.

### Queries/Mutations/Subscriptions → response types + client

Each operation generates a response wrapper (e.g. `GetVehicleResponse`) that holds the typed result. The `GraphLinkClient` class exposes `client.queries`, `client.mutations`, and `client.subscriptions` with one method per operation.

### Cache directives → wired into the client automatically

The `@glCache` and `@glCacheInvalidate` directives you wrote in the schema are reflected in the generated client code. No application-level code is needed to enable caching.

## Watch mode

During development, add `-w` to watch your schema files and regenerate automatically on every save:

```bash title="Terminal"
glink -w

# Output:
# Watching schema/*.graphql for changes...
# [14:32:01] Change detected in schema/schema.graphql
# [14:32:01] Regenerating... done (21 files, 312ms)
```

This integrates naturally with Flutter's hot reload workflow — schema change, save, and your Dart types are updated before you switch back to the emulator.

## Next steps

You now have generated code. The next step depends on your target:

- [Dart / Flutter client](dart-client.md) — set up the adapter, initialize the client, make queries
- [Java client](java-client.md) — wire up Jackson or Gson, make type-safe calls
- [Spring Boot server](spring-server.md) — implement the generated service interfaces, run your app
- [Caching](caching.md) — understand TTL, tags, and partial query caching in depth
