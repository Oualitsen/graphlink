---
title: Java Client — GraphLink Docs
description: Use the generated GraphLink Java client for type-safe GraphQL queries. No generics, injectable HttpClient/OkHttpClient, builder pattern inputs, file uploads — new GraphLinkClient(url) is all you need.
---

# Java Client

Type-safe. No generics. No casting. Works with any JSON library.

## Generated adapters

GraphLink generates concrete adapter classes into your `client/` folder — no external GraphLink runtime, no boilerplate. Two config options control what is generated:

```json title="config.json — adapter options"
{
  "clientConfig": {
    "java": {
      "packageName": "com.example.generated",
      "wsAdapter": "java11",
      "jsonCodec": "jackson"
    }
  }
}
```

**`wsAdapter`** — controls which WebSocket adapter is generated:

- `"java11"` (default) — generates `DefaultGraphLinkWebSocketAdapter` using Java 11's built-in `java.net.http.WebSocket`. Zero external dependencies. Supports exponential-backoff auto-reconnect, an optional `Supplier<Map<String,String>>` for auth headers, and automatically forwards those headers as the `connection_init` payload so your server can authenticate the WebSocket handshake.
- `"okhttp"` — generates the same interface implemented with OkHttp's WebSocket client instead.
- `"none"` — no WebSocket adapter is generated. Use this if you do not need subscriptions.

**`jsonCodec`** — controls which JSON codec is generated:

- `"jackson"` (default) — generates `JacksonGraphLinkJsonCodec` implementing both `GraphLinkJsonEncoder` and `GraphLinkJsonDecoder`.
- `"gson"` — generates `GsonGraphLinkJsonCodec` instead.
- `"none"` — no codec class is generated; supply your own lambdas.

`DefaultGraphLinkClientAdapter` is always generated (when `wsAdapter` is not `"none"`). It uses Java 11's `HttpClient` for HTTP requests and accepts the same optional headers provider as the WebSocket adapter.

### Injectable HTTP client

Both `DefaultGraphLinkClientAdapter` and `DefaultGraphLinkWebSocketAdapter` accept a pre-configured `HttpClient` (Java 11) or `OkHttpClient` as an optional constructor argument:

=== "Java 11 HttpClient"

    ```java
    HttpClient httpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10))
        .sslContext(mySslContext)
        .proxy(ProxySelector.of(new InetSocketAddress("proxy.corp", 8080)))
        .build();

    // Pass it to the adapter — all HTTP and WebSocket traffic uses this client
    DefaultGraphLinkClientAdapter adapter = new DefaultGraphLinkClientAdapter(
        "http://api.example.com/graphql",
        httpClient
    );
    DefaultGraphLinkWebSocketAdapter wsAdapter = new DefaultGraphLinkWebSocketAdapter(
        "ws://api.example.com/graphql",
        httpClient
    );
    ```

=== "OkHttpClient"

    ```java
    OkHttpClient okHttpClient = new OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .addInterceptor(loggingInterceptor)
        .build();

    DefaultGraphLinkClientAdapter adapter = new DefaultGraphLinkClientAdapter(
        "http://api.example.com/graphql",
        okHttpClient
    );
    DefaultGraphLinkWebSocketAdapter wsAdapter = new DefaultGraphLinkWebSocketAdapter(
        "ws://api.example.com/graphql",
        okHttpClient
    );
    ```

The no-arg and headers-only constructors still work unchanged — the injected client is an opt-in.

## Initializing the client

The generated `GraphLinkClient` ships with several constructors that progressively add control:

=== "one-liner"

    ```java
    import com.example.generated.client.GraphLinkClient;

    // Simplest setup — Jackson + Java 11 HttpClient + auto-derives wsUrl.
    // wsUrl is derived by replacing "http" with "ws" in the provided URL.
    GraphLinkClient client = new GraphLinkClient("http://localhost:8080/graphql");
    ```

=== "with auth headers"

    ```java
    // Dynamic auth headers on every request — token is fetched fresh each time.
    Supplier<Map<String, String>> headers = () -> Map.of(
        "Authorization", "Bearer " + tokenService.getToken()
    );

    // wsUrl auto-derived; both HTTP and WebSocket adapters receive the headers.
    GraphLinkClient client = new GraphLinkClient(
        "http://localhost:8080/graphql",
        headers,
        new JacksonGraphLinkJsonCodec(),
        new JacksonGraphLinkJsonCodec()
    );
    ```

=== "custom codec"

    ```java
    // Use a different JSON library — e.g. Gson.
    GraphLinkJsonEncoder encoder = obj -> gson.toJson(obj);
    GraphLinkJsonDecoder decoder = json -> gson.fromJson(json, Map.class);

    GraphLinkClient client = new GraphLinkClient(
        "http://localhost:8080/graphql",
        "ws://localhost:8080/graphql",
        encoder,
        decoder
    );
    ```

=== "full control"

    ```java
    // Full manual wiring — bring your own adapter, encoder, decoder, and cache store.
    GraphLinkClientAdapter adapter = payload -> { /* custom HTTP logic */ };
    GraphLinkJsonEncoder encoder = obj -> mapper.writeValueAsString(obj);
    GraphLinkJsonDecoder decoder = json -> mapper.readValue(json, Map.class);
    GraphLinkWebSocketAdapter wsAdapter = new DefaultGraphLinkWebSocketAdapter(
        "ws://localhost:8080/graphql"
    );

    GraphLinkClient client = new GraphLinkClient(
        adapter, encoder, decoder, myCacheStore, wsAdapter
    );
    ```

!!! info "Any JSON library works"
    The three generated interfaces (`GraphLinkClientAdapter`, `GraphLinkJsonEncoder`, `GraphLinkJsonDecoder`) are all `@FunctionalInterface` — assign them from lambdas using Gson, Moshi, or any other library. Jackson is only the default for the convenience constructors.

Pass a custom `GraphLinkCacheStore` in the full constructor if you need a persistent or shared cache (e.g. Redis-backed). See the [Caching](caching.md) page for details.

## Queries — no generics

This is the core difference from every other Java GraphQL client. There are no `TypeReference` anonymous classes, no unchecked casts, no raw `Map` navigation:

```java title="Fetching a vehicle — GraphLink style"
// Clean, typed, no generics
GetVehicleResponse res = client.queries.getVehicle("42");
System.out.println(res.getGetVehicle().getBrand());   // Toyota
System.out.println(res.getGetVehicle().getYear());    // 2023
System.out.println(res.getGetVehicle().getFuelType()); // GASOLINE
```

Compare this to the boilerplate required by most other clients:

```java title="The same query — typical other client"
// What you're forced to write with most Java GraphQL clients
GraphQLResponse<Map<String, Object>> response =
    client.query(new SimpleGraphQLRequest<>(
        "query getVehicle($id: ID!) { getVehicle(id: $id) { id brand model year fuelType } }",
        Map.of("id", "42"),
        new TypeReference<GraphQLResponse<Map<String, Object>>>() {}
    ));
@SuppressWarnings("unchecked")
Map<String, Object> vehicleMap =
    (Map<String, Object>) response.getData().get("getVehicle");
String brand = (String) vehicleMap.get("brand");
Integer year = ((Number) vehicleMap.get("year")).intValue();
```

## Nullable queries

When the schema declares a nullable return type (no `!`), the corresponding getter on the response class returns a nullable type:

```java title="getPerson — nullable result"
// Schema: getPerson(id: ID!): Person   <-- nullable return
GetPersonResponse res = client.queries.getPerson("99");

Person p = res.getGetPerson(); // can be null — check before use
if (p != null) {
    System.out.println(p.getName());
    System.out.println(p.getEmail());
} else {
    System.out.println("Person not found");
}
```

## Mutations — builder pattern

All input types are generated with an inner `Builder` class. Required fields (non-nullable in the schema) are validated with `Objects.requireNonNull` when `build()` is called:

```java title="Adding a vehicle"
import com.example.generated.inputs.AddVehicleInput;
import com.example.generated.enums.FuelType;

AddVehicleResponse added = client.mutations.addVehicle(
    AddVehicleInput.builder()
        .brand("Toyota")
        .model("Camry")
        .year(2023)
        .fuelType(FuelType.GASOLINE)
        // ownerId is nullable — omit for null
        .build()
);

System.out.println(added.getAddVehicle().getId());    // server-assigned ID
System.out.println(added.getAddVehicle().getBrand()); // Toyota
```

The generated `AddVehicleInput` class:

```java title="generated/inputs/AddVehicleInput.java"
public class AddVehicleInput {
   private final String brand; private final String model;
   private final Integer year; private final FuelType fuelType; private final String ownerId;

   public AddVehicleInput(String brand, String model, Integer year, FuelType fuelType, String ownerId) {
      Objects.requireNonNull(brand); Objects.requireNonNull(model);
      Objects.requireNonNull(year); Objects.requireNonNull(fuelType);
      this.brand = brand; this.model = model; this.year = year;
      this.fuelType = fuelType; this.ownerId = ownerId;
   }
   public static Builder builder() { return new Builder(); }
   public static class Builder {
      private String brand; private String model; private Integer year;
      private FuelType fuelType; private String ownerId;
      public Builder brand(String brand) { this.brand = brand; return this; }
      public Builder model(String model) { this.model = model; return this; }
      public Builder year(Integer year) { this.year = year; return this; }
      public Builder fuelType(FuelType fuelType) { this.fuelType = fuelType; return this; }
      public Builder ownerId(String ownerId) { this.ownerId = ownerId; return this; }
      public AddVehicleInput build() { return new AddVehicleInput(brand, model, year, fuelType, ownerId); }
   }
}
```

## Lists

List queries return a typed `List<T>` — no casting required:

```java title="List query"
ListVehiclesResponse res = client.queries.listVehicles();
List<Vehicle> vehicles = res.getListVehicles(); // List<Vehicle> — no raw types

for (Vehicle v : vehicles) {
    System.out.printf("%s %s (%d) — %s%n",
        v.getBrand(), v.getModel(), v.getYear(), v.getFuelType());
}

// Or with streams
vehicles.stream()
    .filter(v -> v.getFuelType() == FuelType.ELECTRIC)
    .map(Vehicle::getBrand)
    .forEach(System.out::println);
```

## The response wrapper pattern

Every query, mutation, and subscription operation generates a dedicated response class named `{OperationName}Response`. For example, `getVehicle` generates `GetVehicleResponse`.

This pattern mirrors the GraphQL JSON response structure, which always wraps results in a `data` field:

```json title="GraphQL HTTP response JSON"
{
  "data": {
    "getVehicle": {
      "id": "42",
      "brand": "Toyota",
      "model": "Camry",
      "year": 2023,
      "fuelType": "GASOLINE",
      "ownerId": null
    }
  }
}
```

The generated `GetVehicleResponse.fromJson()` navigates into the `data` object and deserializes `getVehicle` as a `Vehicle`. From your code's perspective, you simply call `res.getGetVehicle()` — the JSON unwrapping is invisible.

Notice the double "get" in `getGetVehicle()` — the first is the Java getter prefix, the second is the operation name. This is consistent and predictable: the method name is always `get` + the operation name with a capital first letter.

## Subscriptions

Subscriptions are available via `client.subscriptions` and use the `GraphLinkWebSocketAdapter` interface. The generated `DefaultGraphLinkWebSocketAdapter` implements this interface out of the box:

```java title="Subscribing to new vehicles"
client.subscriptions.vehicleAdded(event -> {
    VehicleAddedResponse res = event;
    System.out.println("New vehicle: " + res.getVehicleAdded().getBrand());
});
```

The generated WebSocket adapter handles the [graphql-ws subprotocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md) automatically — connection init, ping/pong, and exponential-backoff reconnect on disconnect.

!!! info "Deriving the WebSocket URL"
    The convenience constructors that take only an HTTP URL automatically derive the WebSocket URL by replacing `http` with `ws` (and `https` with `wss`). Pass an explicit `wsUrl` if your WebSocket endpoint differs from the HTTP endpoint.

## File uploads

When your schema uses the built-in `Upload` scalar, GraphLink generates a `GLUpload` class and handles multipart encoding in the generated adapter:

```java title="Using GLUpload in Java"
import com.example.generated.types.GLUpload;
import java.io.FileInputStream;
import java.io.File;

File file = new File("/path/to/document.pdf");
GLUpload upload = new GLUpload(
    new FileInputStream(file),
    file.length(),
    "document.pdf",
    "application/pdf"
);

UploadDocumentResponse result = client.mutations.uploadDocument(upload);
System.out.println(result.getUploadDocument()); // URL or ID returned by server
```

The generated `DefaultGraphLinkClientAdapter` automatically encodes mutations containing `GLUpload` as multipart/form-data following the [GraphQL multipart request spec](https://github.com/jaydenseric/graphql-multipart-request-spec). No extra configuration needed.
