---
title: Spring Boot Server — GraphLink Docs
description: GraphLink generates Spring Boot GraphQL scaffolding from your schema — controllers, service interfaces, inputs, enums, for both Java and Kotlin. Strict-by-default server generation with Map-boundary controllers, MVC and reactive WebFlux modes, file uploads, Spring Security context propagation, and forward mappings.
---

# Spring Boot Server

GraphLink generates the entire Spring Boot scaffolding from your schema — controllers, service interfaces, types, inputs, and enums.

## Server mode config

Set `"mode": "server"` and provide a `"spring"` section under `serverConfig`. The key options:

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
          "basePackage":          "com.example.generated",
          "generateControllers":  true,
          "generateRepositories": false,
          "immutableInputFields": true,
          "immutableTypeFields":  false
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

| Option | Description |
|---|---|
| `generateControllers` | Generates `@Controller` classes with `@QueryMapping`, `@MutationMapping`, `@SubscriptionMapping`, and `@Argument` on parameters. |
| `generateRepositories` | When `true`, generates JPA `Repository` interfaces for types annotated with `@glRepository`. |
| `immutableInputFields` | Input class fields are `final`. Recommended: `true`. |
| `immutableTypeFields` | Type class fields are `final`. Set to `false` for Spring Boot — Spring's GraphQL runtime sets fields via setters. |

## Java records

Set `"inputAsRecord": true` and/or `"typeAsRecord": true` to generate inputs and types as Java records instead of mutable classes with setters. Records are more concise and enforce immutability at the language level:

=== "JSON"

    ```json title="glink.json — records"
    {
      "serverConfig": {
        "spring": {
          "basePackage": "com.example.generated",
          "inputAsRecord": true,
          "typeAsRecord": false
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — records"
    serverConfig:
      spring:
        basePackage: com.example.generated
        inputAsRecord: true
        typeAsRecord: false
    ```


## Schema generation

Set `"generateSchema": true` to write the processed schema file to disk alongside the generated Java. This is useful when your Spring Boot app needs to serve the schema file at a specific path:

=== "JSON"

    ```json title="glink.json — schema generation"
    {
      "serverConfig": {
        "spring": {
          "basePackage": "com.example.generated",
          "generateSchema": true,
          "schemaTargetPath": "src/main/resources/graphql/schema.graphqls"
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — schema generation"
    serverConfig:
      spring:
        basePackage: com.example.generated
        generateSchema: true
        schemaTargetPath: src/main/resources/graphql/schema.graphqls
    ```

`schemaTargetPath` must end in `.graphql` or `.graphqls`. The generated schema reflects all directive processing — internal directives like `@glSkipOnServer` are not emitted.

## Strict server generation

Since v5.0.0, server generation is **strict by default**. Every generated type and interface enforces the schema's real nullability on its getters, constructors, and setters — a `title: String!` field is generated as non-null, not the always-nullable model used before v5.0.0.

Generated controllers serialize their responses via `toJson()` to a `Map` at the controller boundary, so a resolver that can only return a partially-fetched object (for example, a repository query that selects just the columns present in the GraphQL selection set) doesn't need every non-null field populated.

**Opting a type into partial/lenient population** — annotate it with `@glServerLenient`. All of its own fields are generated as nullable, so a resolver can construct it with un-fetched fields left `null`:

```graphql
type LegacyReport @glServerLenient {
  id: ID!
  total: Float!
}
```

!!! danger "Migration from pre-5.0.0"
    If your existing resolvers relied on server-generated types being fully nullable (e.g. constructing a partially-populated `Vehicle` with some fields left `null`), annotate those types with `@glServerLenient` before upgrading.

## What gets generated

For the example schema, the generator produces 9 files:

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

Controllers are generated and never touched by hand. Service interfaces are what you implement. Types, inputs, and enums are data classes.

## Types and inputs

Server-side types are mutable — they have getters and setters, not final fields. This is required because Spring's GraphQL runtime deserializes JSON into these classes using reflection.

```java title="generated/types/Vehicle.java — server version (mutable)"
public class Vehicle {
   private String id;
   private String brand;
   private String model;
   private Integer year;
   private FuelType fuelType;
   private String ownerId;

   public Vehicle() {}

   public String getId() { return id; }
   public void setId(String id) { this.id = id; }

   public String getBrand() { return brand; }
   public void setBrand(String brand) { this.brand = brand; }

   public String getModel() { return model; }
   public void setModel(String model) { this.model = model; }

   public Integer getYear() { return year; }
   public void setYear(Integer year) { this.year = year; }

   public FuelType getFuelType() { return fuelType; }
   public void setFuelType(FuelType fuelType) { this.fuelType = fuelType; }

   public String getOwnerId() { return ownerId; }
   public void setOwnerId(String ownerId) { this.ownerId = ownerId; }
}
```

Input classes can be immutable since Spring maps query arguments into them at the framework level using constructors or builders. Note that `immutableTypeFields: false` applies to `type` definitions only; input classes follow `immutableInputFields`.

## Service interfaces

For each group of operations sharing a root type, GraphLink generates one service interface:

```java title="generated/services/VehicleService.java"
public interface VehicleService {
   Vehicle getVehicle(String id);
   List<Vehicle> listVehicles();
   Vehicle addVehicle(AddVehicleInput input);
   Flux<Vehicle> vehicleAdded();
}
```

Observe the return types:

- Queries return the domain type directly — `Vehicle`, not `Optional<Vehicle>` or `Mono<Vehicle>`
- Subscriptions return `Flux<T>` — a Project Reactor reactive stream
- The method signatures exactly mirror the schema declarations

You implement this interface and annotate your implementation with `@Service`. You do not touch the generated controller.

## Controllers

The generated controller is the glue between Spring's GraphQL runtime and your service. It is fully annotated and delegates every call to the service interface. You never need to modify it.

!!! warning "v5.0.0: controllers return `Map` / `List<Map>`, not typed objects"
    Since v5.0.0, generated Java Spring, Kotlin Spring, and Express/Apollo controllers serialize the service's result via the type's generated `toJson()` at the controller boundary, and return `Map<String, Object>` / `List<Map<String, Object>>` instead of the typed domain object. **Service interfaces are unaffected** — you still implement them with typed parameters and typed return values. Only the controller's own return type (and therefore anything that inspects a controller method's return type directly, e.g. custom AOP or tests that call the controller method in isolation) needs to account for the change after regenerating. Identifier normalization and reserved-keyword renaming mean a field's generated identifier can differ from its wire name, so serializing through `toJson()` at the boundary keeps the wire payload correct even when the Java/Kotlin field name doesn't match.

    Java Spring controller methods also now bind input arguments as `Map<String, Object>` and convert them via the input's generated `fromJson()`, instead of receiving a Spring-bound typed input object directly — again to keep renamed/normalized fields correct on the wire. Any custom Jackson/Spring binding configuration relying on the previous direct-typed argument binding needs to be revisited.

```java title="generated/controllers/VehicleServiceController.java — v5.0.0+"
@Controller()
public class VehicleServiceController {
   private final VehicleService vehicleService;

   public VehicleServiceController(VehicleService vehicleService) {
      this.vehicleService = vehicleService;
   }

   @QueryMapping()
   public Map<String, Object> getVehicle(@Argument() String id) {
      return vehicleService.getVehicle(id).toJson();
   }

   @QueryMapping()
   public List<Map<String, Object>> listVehicles() {
      return vehicleService.listVehicles().stream().map(Vehicle::toJson).toList();
   }

   @MutationMapping()
   public Map<String, Object> addVehicle(@Argument() Map<String, Object> input) {
      return vehicleService.addVehicle(AddVehicleInput.fromJson(input)).toJson();
   }

   @SubscriptionMapping()
   public Flux<Map<String, Object>> vehicleAdded() {
      return vehicleService.vehicleAdded().map(Vehicle::toJson);
   }
}
```

Spring's `@QueryMapping`, `@MutationMapping`, and `@SubscriptionMapping` use the method name to map to the schema field by convention. `@Argument` on method parameters maps GraphQL arguments to Java parameters by name.

## Implementing the service

Create a `@Service` class in your own package (not in the `generated` package) that implements the generated interface:

```java title="com/example/service/VehicleServiceImpl.java — your code"
package com.example.service;

import com.example.generated.services.VehicleService;
import com.example.generated.types.Vehicle;
import com.example.generated.inputs.AddVehicleInput;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;
import java.util.List;

@Service
public class VehicleServiceImpl implements VehicleService {

    private final VehicleRepository vehicleRepository;
    private final Sinks.Many<Vehicle> vehicleSink =
        Sinks.many().multicast().onBackpressureBuffer();

    public VehicleServiceImpl(VehicleRepository vehicleRepository) {
        this.vehicleRepository = vehicleRepository;
    }

    @Override
    public Vehicle getVehicle(String id) {
        return vehicleRepository.findById(id).orElse(null);
    }

    @Override
    public List<Vehicle> listVehicles() {
        return vehicleRepository.findAll();
    }

    @Override
    public Vehicle addVehicle(AddVehicleInput input) {
        Vehicle v = new Vehicle();
        v.setBrand(input.getBrand());
        v.setModel(input.getModel());
        v.setYear(input.getYear());
        v.setFuelType(input.getFuelType());
        v.setOwnerId(input.getOwnerId());
        Vehicle saved = vehicleRepository.save(v);
        vehicleSink.tryEmitNext(saved);
        return saved;
    }

    @Override
    public Flux<Vehicle> vehicleAdded() {
        return vehicleSink.asFlux();
    }
}
```

!!! info "Keep generated code separate"
    Put your implementations in a separate package from the generated code (e.g. `com.example.service` vs `com.example.generated`). This way, re-running the generator never overwrites your business logic.

## Subscriptions with Reactor

Spring Boot GraphQL uses Project Reactor for subscriptions. The service interface returns `Flux<T>` — a reactive stream that emits items over time.

The recommended approach is `Sinks.Many`: a thread-safe construct that lets you push items from anywhere in your application:

```java title="Push-based subscription with Sinks"
// Declare a multicast sink — supports multiple concurrent subscribers
private final Sinks.Many<Vehicle> vehicleSink =
    Sinks.many().multicast().onBackpressureBuffer();

// In vehicleAdded() — return the flux backed by the sink
@Override
public Flux<Vehicle> vehicleAdded() {
    return vehicleSink.asFlux();
}

// When a new vehicle is saved, push it to all subscribers
vehicleSink.tryEmitNext(savedVehicle);

// When the application shuts down (optional)
vehicleSink.tryEmitComplete();
```

`Sinks.many().multicast()` allows multiple GraphQL subscribers to receive the same events simultaneously.

## Reactive mode (Spring WebFlux)

Set `"reactive": true` in `serverConfig.spring` to generate Spring WebFlux-style controllers. Queries and mutations return `Mono<T>` instead of `T` directly, and subscriptions return `Flux<T>` as usual. File upload fields use `FilePart` instead of `MultipartFile`.

=== "JSON"

    ```json title="glink.json — reactive mode"
    {
      "serverConfig": {
        "spring": {
          "basePackage": "com.example.generated",
          "reactive": true
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — reactive mode"
    serverConfig:
      spring:
        basePackage: com.example.generated
        reactive: true
    ```

With `reactive: true`, the generated service interface returns reactive types:

```java title="Generated VehicleService.java — reactive mode"
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface VehicleService {
   Mono<Vehicle> getVehicle(String id);
   Flux<Vehicle> listVehicles();
   Mono<Vehicle> addVehicle(AddVehicleInput input);
   Flux<Vehicle> vehicleAdded();
}
```

The generated controllers delegate to these reactive methods directly. Spring WebFlux handles back-pressure and non-blocking I/O automatically.

## Security context propagation (MVC)

In MVC (non-reactive) mode, Spring Security's `SecurityContextHolder` is thread-local. When a controller delegates to an async `CompletableFuture`, the security context is not automatically carried to the worker thread. Enable `"useSpringSecurity": true` to have GraphLink capture the context before entering the future and restore it on the worker thread:

=== "JSON"

    ```json title="glink.json — security context propagation"
    {
      "serverConfig": {
        "spring": {
          "useSpringSecurity": true
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — security context propagation"
    serverConfig:
      spring:
        useSpringSecurity: true
    ```

When enabled, the generated controller looks like this:

```java title="Generated controller — with useSpringSecurity: true"
@QueryMapping()
public CompletableFuture<Vehicle> getVehicle(@Argument() String id) {
    SecurityContext ctx = SecurityContextHolder.getContext();
    return CompletableFuture.supplyAsync(() -> {
        SecurityContextHolder.setContext(ctx);
        try {
            return vehicleService.getVehicle(id);
        } finally {
            SecurityContextHolder.clearContext();
        }
    });
}
```

This option has no effect in reactive mode — Spring Security provides dedicated reactive support via `ReactiveSecurityContextHolder`.

## Forward mappings

When a type is annotated with `@glSkipOnServer(mapTo: "SomeServerType")`, GraphLink automatically forwards fields that exist verbatim on the server type — fields with the same name and compatible type — without generating a service method or `@SchemaMapping` for them. Only fields absent from the server type still get full delegation.

```graphql title="Forward mapping example"
# Map our schema Pageable to Spring Data's Pageable — don't generate a class
type Pageable @glSkipOnServer(mapTo: "org.springframework.data.domain.Pageable") {
  pageNumber: Int   # exists verbatim on Spring's Pageable → auto-forwarded
  pageSize: Int     # exists verbatim on Spring's Pageable → auto-forwarded
  offset: Long      # exists verbatim on Spring's Pageable → auto-forwarded
}
```

Fields that match are resolved directly by Spring without any service delegation. This removes the boilerplate of manually writing `@SchemaMapping` methods for fields that already exist on the mapped type.

## File uploads

When your schema uses the `Upload` scalar, Spring Boot controllers accept `MultipartFile` (MVC mode) or `FilePart` (reactive mode):

```graphql title="Schema with Upload scalar"
scalar Upload

type Mutation {
  uploadDocument(file: Upload!): String!
}
```

=== "MVC controller"

    ```java
    @MutationMapping()
    public String uploadDocument(@Argument() MultipartFile file) {
        return documentService.uploadDocument(file);
    }
    ```

=== "Reactive controller"

    ```java
    @MutationMapping()
    public Mono<String> uploadDocument(@Argument() FilePart file) {
        return documentService.uploadDocument(file);
    }
    ```

The service interface method receives the same type as the controller, so you implement it directly without any conversion.

## Validation with @glValidate

Add `@glValidate` to a mutation in your schema to instruct GraphLink to generate a `validateX()` method in the service interface. The controller calls this method before the main method, giving you a place to throw validation exceptions before any business logic runs.

```graphql title="Schema with @glValidate"
type Mutation {
  addVehicle(input: AddVehicleInput!): Vehicle! @glValidate
}
```

With `@glValidate` on `addVehicle`, the generated service interface gains an extra method:

```java title="Generated VehicleService.java — with @glValidate"
public interface VehicleService {
   // Called first by the controller — throw here to abort the mutation
   void validateAddVehicle(AddVehicleInput input);

   Vehicle addVehicle(AddVehicleInput input);
   List<Vehicle> listVehicles();
   Vehicle getVehicle(String id);
   Flux<Vehicle> vehicleAdded();
}
```

The generated controller calls `validateAddVehicle` before `addVehicle`. In your implementation, throw any exception to abort:

```java title="Implementing the validation method"
@Override
public void validateAddVehicle(AddVehicleInput input) {
    if (input.getBrand() == null || input.getBrand().isBlank()) {
        throw new IllegalArgumentException("Brand must not be blank");
    }
    if (input.getYear() < 1886 || input.getYear() > 2100) {
        throw new IllegalArgumentException("Year out of valid range");
    }
}

@Override
public Vehicle addVehicle(AddVehicleInput input) {
    // Only reached if validateAddVehicle did not throw
    // ...
}
```

!!! note "@glValidate vs @glIntercept"
    `@glValidate` generates a dedicated `validateX(...)` method per mutation, typed to that mutation's own arguments — use it for mutation-specific input validation. `@glIntercept` generates one schema-wide `runBefore(tag, operation, args, context)` hook shared by every annotated field (queries, mutations, subscriptions, and schema/batch mappings alike) — use it for cross-cutting checks like auth. When both are present on the same field, `runBefore` fires first. → **[Full @glIntercept reference](directives.md#glintercept)**

## Kotlin Spring Boot server

New in v5.0.0: set `"mode": "server"` and use a `"kotlinSpring"` section instead of `"spring"` under `serverConfig` to generate a Kotlin server target — data-class types/inputs/enums, services, controllers, and repositories, mirroring the Java Spring target above (including strict-by-default generation and `Map`-boundary controller serialization).

=== "JSON"

    ```json title="glink.json — Kotlin Spring server"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "server",
      "outputDir": "src/main/kotlin/com/example/generated",
      "serverConfig": {
        "kotlinSpring": {
          "basePackage": "com.example.generated",
          "typeAsDataClass": true,
          "inputAsDataClass": true,
          "blockingServices": true,
          "generateControllers": true,
          "generateRepositories": false
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — Kotlin Spring server"
    schemaPaths:
      - schema/*.graphql
    mode: server
    outputDir: src/main/kotlin/com/example/generated
    serverConfig:
      kotlinSpring:
        basePackage: com.example.generated
        typeAsDataClass: true
        inputAsDataClass: true
        blockingServices: true
        generateControllers: true
        generateRepositories: false
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `typeAsDataClass` | `boolean` | `false` | Emit output types as `data class`. When `false`, uses `open class`. |
| `inputAsDataClass` | `boolean` | `false` | Emit input types as `data class`. When `false`, uses `open class`. |
| `blockingServices` | `boolean` | `true` | When `true`, controller methods wrap each service call in `withContext(Dispatchers.IO + SecurityCoroutineContext()) { ... }`, offloading blocking (e.g. JPA/JDBC) work off the coroutine dispatcher and propagating `SecurityContextHolder` across the switch. Set to `false` when your service layer is coroutine-native/non-blocking — methods are then emitted with no wrapping. |

The remaining options (`generateControllers`, `generateRepositories`, `immutableInputFields`, `immutableTypeFields`, `generateSchema`, `schemaTargetPath`, `injectDataFetching`) behave the same as their Java Spring equivalents documented above.
