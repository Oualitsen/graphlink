---
title: Dart / Flutter Client — GraphLink Docs
description: Use the generated GraphLink Dart client in Flutter or Dart apps. Generated Dio and http adapters, named-parameter constructors, typed queries, mutations, subscriptions, file uploads, and built-in caching.
---

# Dart / Flutter Client

A fully typed GraphQL client generated directly from your schema.

## Generated adapters

GraphLink generates adapter files alongside the client. Which HTTP adapter is generated is controlled by the `httpAdapter` option in `config.json`. The WebSocket adapter is always generated when your schema has subscriptions.

```json title="config.json — adapter options"
{
  "clientConfig": {
    "dart": {
      "packageName": "com.example.generated",
      "httpAdapter": "dio"
    }
  }
}
```

**`httpAdapter`** — controls which HTTP adapter file is generated:

- `"dio"` (default) — generates `graph_link_dio_adapter.dart` containing `GraphLinkDioAdapter`. Supports an optional `tokenProvider` for Bearer auth, custom Dio `interceptors`, and `BaseOptions`. Used automatically by `GraphLinkClient.withHttp`.
- `"http"` — generates `graph_link_http_adapter.dart` containing `GraphLinkHttpAdapter`. Uses `package:http` with an optional async `headersProvider` for custom headers.
- `"none"` — no HTTP adapter file is generated. Supply your own `Future<String> Function(String)`.

=== "Dio adapter"

    ```dart
    // generated/client/graph_link_dio_adapter.dart
    class GraphLinkDioAdapter {
      final String url;
      final Dio dio;

      GraphLinkDioAdapter({
        required this.url,
        Dio? dio,
        Future<String?> Function()? tokenProvider, // adds Authorization: Bearer <token>
        List<Interceptor> interceptors = const [],
        BaseOptions? options,
      });

      Future<String> call(String payload) async { /* ... */ }
    }
    ```

=== "http adapter"

    ```dart
    // generated/client/graph_link_http_adapter.dart
    class GraphLinkHttpAdapter {
      final String url;
      final Future<Map<String, String>?>? Function()? headersProvider;

      GraphLinkHttpAdapter({
        required this.url,
        this.headersProvider, // merged into request headers on every call
      });

      Future<String> call(String payload) async { /* ... */ }
    }
    ```

=== "WebSocket adapter"

    ```dart
    // generated/client/graph_link_websocket_adapter.dart
    // Always generated when your schema has subscriptions.
    class DefaultGraphLinkWebSocketAdapter extends GraphLinkWebSocketAdapter {
      DefaultGraphLinkWebSocketAdapter({
        required String url,
        Future<Map<String, String>?>? Function()? headersProvider,
        Duration initialReconnectDelay = const Duration(seconds: 1),
        Duration maxReconnectDelay = const Duration(seconds: 30),
      });
      // Handles graphql-ws protocol, exponential-backoff reconnect,
      // and forwards headersProvider result as connection_init payload.
    }
    ```

All adapter files are generated into your output directory. They carry no external GraphLink dependency and you can edit them freely.

## Initializing the client

The `GraphLinkClient` uses **named parameters**. Three constructors cover every scenario:

=== "withHttp (simplest)"

    ```dart
    import 'generated/client/graph_link_client.dart';

    // Uses the generated Dio adapter for HTTP and the generated
    // WebSocket adapter for subscriptions.
    final client = GraphLinkClient.withHttp(
      url: 'http://localhost:8080/graphql',
      wsUrl: 'ws://localhost:8080/graphql',
      // Optional — adds Authorization: Bearer <token> on every request
      tokenProvider: () async => await getAuthToken(),
      // Optional — forwarded as connection_init payload for WS auth
      wsTokenProvider: () async => await getAuthToken(),
      // Optional — defaults to InMemoryGraphLinkCacheStore
      // store: MyPersistentCacheStore(),
    );
    ```

=== "fromUrl (custom HTTP)"

    ```dart
    import 'generated/client/graph_link_client.dart';
    import 'generated/client/graph_link_http_adapter.dart';

    // Bring your own HTTP adapter (or use GraphLinkHttpAdapter).
    // The generated WebSocket adapter handles subscriptions.
    final client = GraphLinkClient.fromUrl(
      adapter: GraphLinkHttpAdapter(
        url: 'http://localhost:8080/graphql',
        headersProvider: () async => {'Authorization': 'Bearer ${await getToken()}'},
      ).call,
      wsUrl: 'ws://localhost:8080/graphql',
    );
    ```

=== "full control"

    ```dart
    import 'generated/client/graph_link_client.dart';
    import 'generated/client/graph_link_websocket_adapter.dart';

    // Full control — any adapter function, any WebSocket adapter.
    final client = GraphLinkClient(
      adapter: myHttpAdapterFn,   // Future<String> Function(String payload)
      wsAdapter: DefaultGraphLinkWebSocketAdapter(
        url: 'ws://localhost:8080/graphql',
        headersProvider: () async => {'Authorization': 'Bearer ${await getToken()}'},
        initialReconnectDelay: const Duration(seconds: 2),
        maxReconnectDelay: const Duration(seconds: 60),
      ),
      store: myPersistentCacheStore, // optional
    );
    ```

!!! info "Testing made easy"
    Because the adapter is just a named function parameter, passing a mock in tests requires no HTTP mocking library: `adapter: (payload) async => '{"data":{"getCar":{"id":"1","make":"Toyota"}}}'`

## Queries

All queries are accessible via `client.queries`. Each operation becomes a method with typed parameters and a typed return value.

```dart title="Fetching a vehicle by ID"
// getVehicle returns GetVehicleResponse — never null (Vehicle! in schema)
final res = await client.queries.getVehicle(id: '42');

// res.getVehicle is a typed Vehicle object
print(res.getVehicle.brand);    // Toyota
print(res.getVehicle.model);    // Camry
print(res.getVehicle.year);     // 2023
print(res.getVehicle.fuelType); // FuelType.GASOLINE
```

The generated `GetVehicleResponse` type looks like this:

```dart title="generated/types/get_vehicle_response.dart"
class GetVehicleResponse {
   final Vehicle getVehicle;
   GetVehicleResponse({required this.getVehicle});
   static GetVehicleResponse fromJson(Map<String, dynamic> json) {
      return GetVehicleResponse(
         getVehicle: Vehicle.fromJson(json['getVehicle'] as Map<String, dynamic>),
      );
   }
}
```

### List queries

```dart title="Fetching all vehicles"
final res = await client.queries.listVehicles();

// res.listVehicles is List<Vehicle> — fully typed
for (final vehicle in res.listVehicles) {
  print('${vehicle.brand} ${vehicle.model} (${vehicle.year})');
}
```

## Nullable queries

When the schema declares a query with a nullable return type (no `!`), the response wrapper field is also nullable:

```dart title="getPerson — nullable result"
// Schema: getPerson(id: ID!): Person   <-- no ! on Person
final res = await client.queries.getPerson(id: '99');

// res.getPerson is Person? — use null-aware access
if (res.getPerson != null) {
  print(res.getPerson!.name);
}

// Or with null-safe chaining
print(res.getPerson?.email ?? 'Not found');
```

## Mutations

Mutations live under `client.mutations` and follow the same pattern. Input types are passed as named parameters:

```dart title="Adding a vehicle"
import 'generated/inputs/add_vehicle_input.dart';
import 'generated/enums/fuel_type.dart';

final added = await client.mutations.addVehicle(
  input: AddVehicleInput(
    brand: 'Toyota',
    model: 'Camry',
    year: 2023,
    fuelType: FuelType.GASOLINE,
    // ownerId is nullable — omit it or pass null
  ),
);

print(added.addVehicle.id);    // server-assigned ID
print(added.addVehicle.brand); // Toyota
```

The generated `AddVehicleInput` class enforces required fields at construction time through Dart's named required parameters:

```dart title="generated/inputs/add_vehicle_input.dart"
class AddVehicleInput {
   final String brand;
   final String model;
   final int year;
   final FuelType fuelType;
   final String? ownerId;
   AddVehicleInput({
      required this.brand, required this.model,
      required this.year, required this.fuelType, this.ownerId
   });
   Map<String, dynamic> toJson() {
      return { 'brand': brand, 'model': model, 'year': year,
               'fuelType': fuelType.toJson(), 'ownerId': ownerId };
   }
}
```

## Subscriptions

Subscriptions are available via `client.subscriptions` and return a `Stream`. The generated `DefaultGraphLinkWebSocketAdapter` implements the [graphql-ws subprotocol](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md) and handles connection init, ping/pong, and reconnect automatically.

```dart title="Subscribing to new vehicles"
final subscription = client.subscriptions.vehicleAdded().listen((event) {
  print('New vehicle: ${event.vehicleAdded.brand} ${event.vehicleAdded.model}');
});

// Cancel when done (e.g. in Flutter widget dispose)
await subscription.cancel();
```

If you supply a `headersProvider` on the WebSocket adapter, its result is returned from `connectionInitPayload()` and sent in the `connection_init` message — your server can use it to authenticate the WebSocket session without needing HTTP headers on the upgrade request.

## Error handling

If the server returns a GraphQL error, the generated client throws a `GraphLinkException` containing the list of errors from the response. Wrap calls in a try/catch:

```dart title="Error handling"
import 'generated/types/graph_link_error.dart';

try {
  final res = await client.queries.getVehicle(id: 'bad-id');
  print(res.getVehicle.brand);
} on GraphLinkException catch (e) {
  for (final error in e.errors) {
    print('GraphQL error: ${error.message}');
    if (error.locations != null) {
      for (final loc in error.locations!) {
        print('  at line ${loc.line}, column ${loc.column}');
      }
    }
  }
} catch (e) {
  // Network error, timeout, etc.
  print('Request failed: $e');
}
```

## The _all_fields fragment

When `generateAllFieldsFragments: true` is set in the config, GraphLink generates a named fragment for every type in the schema. The `autoGenerateQueries: true` option uses these fragments to automatically build the query strings for every operation. Instead of writing query strings by hand, GraphLink inlines the fields from the fragment. This means you never have to maintain query strings manually — when you add a field to a type in the schema, the generated client automatically fetches that field.

You can also reference `_all_fields_Vehicle` by name in any hand-written queries. Use the shorthand `... _all_fields` and GraphLink resolves it to the appropriate type-specific fragment based on the field's return type.

```graphql title="Using _all_fields in a custom query"
type Query {
  # GraphLink resolves _all_fields to _all_fields_Vehicle for this field
  getVehicle(id: ID!): Vehicle! @glCache(ttl: 120, tags: ["vehicles"])
}
```

## File uploads

When your schema uses the built-in `Upload` scalar, GraphLink generates a `GLUpload` type and produces multipart-aware upload logic in the HTTP adapter:

```graphql title="Schema — Upload scalar"
scalar Upload

type Mutation {
  uploadDocument(file: Upload!): String!
}
```

```dart title="Using GLUpload in Dart"
import 'generated/types/gl_upload.dart';
import 'dart:io';

final file = File('/path/to/document.pdf');
final upload = GLUpload(
  stream: file.openRead(),
  length: await file.length(),
  filename: 'document.pdf',
  mimeType: 'application/pdf',
);

final result = await client.mutations.uploadDocument(file: upload);
print(result.uploadDocument); // e.g. "https://cdn.example.com/document.pdf"
```

The Dio and http adapters both handle multipart encoding automatically when a mutation argument contains a `GLUpload`. No extra configuration is needed.
