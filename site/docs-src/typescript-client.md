---
title: TypeScript Client — GraphLink Docs
description: Use the generated GraphLink TypeScript client in Angular, React, Vue, Svelte, or Node. Fetch and Axios adapters, optional RxJS observables, typed queries, mutations, and subscriptions.
---

# TypeScript Client

A fully typed GraphQL client generated from your schema — works in Angular, React, Vue, Svelte, and Node/Bun.

## Configuration

Set `"mode": "client"` and add a `"typescript"` key under `clientConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "typeMappings": {
        "ID":      "string",
        "String":  "string",
        "Float":   "number",
        "Int":     "number",
        "Boolean": "boolean",
        "Null":    "null"
      },
      "outputDir": "src/generated",
      "clientConfig": {
        "typescript": {
          "packageName": "my-app",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "httpAdapter": "fetch",
          "observables": false,
          "generateDefaultWsAdapter": true,
          "optionalNullableInputFields": true
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
      ID: string
      String: string
      Float: number
      Int: number
      Boolean: boolean
      Null: null
    outputDir: src/generated
    clientConfig:
      typescript:
        packageName: my-app
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        httpAdapter: fetch
        observables: false
        generateDefaultWsAdapter: true
        optionalNullableInputFields: true
    ```

## Generated output

For the example schema, GraphLink generates the following TypeScript files:

```
src/generated/
  client/
    graph-link-client.ts        ← GraphLinkClient class
    graph-link-fetch-adapter.ts ← HTTP adapter
    graph-link-ws-adapter.ts    ← WebSocket adapter
  types/
    vehicle.ts
    person.ts
  inputs/
    add-vehicle-input.ts
    add-person-input.ts
  enums/
    fuel-type.ts
  responses/
    get-vehicle-response.ts
    list-vehicles-response.ts
    add-vehicle-response.ts
  graphlink.ts                  ← barrel file — re-exports everything above
```

## Barrel file

Alongside the per-file output, GraphLink emits a single barrel file, `graphlink.ts`, that re-exports every generated enum, input, type, and interface, plus the client files:

```typescript title="generated/graphlink.ts"
export * from './enums/fuel-type';
export * from './inputs/add-vehicle-input';
export * from './types/vehicle';
export * from './responses/get-vehicle-response';
export * from './client/graph-link-client';
// ... one export line per generated file
```

Import from it instead of reaching into individual subdirectories:

```typescript title="Using the barrel file"
import { GraphLinkClient, Vehicle, AddVehicleInput } from './generated/graphlink';
```

It's regenerated on every run — nothing to configure.

## HTTP adapters

The `httpAdapter` option controls which HTTP adapter is generated:

- `"fetch"` (default) — generates `GraphLinkFetchAdapter` using the native `fetch` API. Works in Angular, React, Vue, Svelte, Bun, and modern Node (v18+) without any extra dependencies.
- `"axios"` — generates `GraphLinkAxiosAdapter` using Axios. Choose this for Node environments where you already use Axios or need its interceptor/cancellation support.

=== "Fetch adapter"

    ```typescript
    // generated/client/graph-link-fetch-adapter.ts
    export class GraphLinkFetchAdapter {
      constructor(
        private readonly url: string,
        private readonly headersProvider?: () => Promise<Record<string, string> | undefined>
      ) {}

      async call(payload: string): Promise<string> {
        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
          ...((await this.headersProvider?.()) ?? {}),
        };
        const res = await fetch(this.url, { method: 'POST', headers, body: payload });
        return res.text();
      }
    }
    ```

=== "Axios adapter"

    ```typescript
    // generated/client/graph-link-axios-adapter.ts
    import axios, { AxiosInstance } from 'axios';

    export class GraphLinkAxiosAdapter {
      private readonly axios: AxiosInstance;

      constructor(
        private readonly url: string,
        private readonly headersProvider?: () => Promise<Record<string, string> | undefined>,
        axiosInstance?: AxiosInstance
      ) {
        this.axios = axiosInstance ?? axios.create();
      }

      async call(payload: string): Promise<string> {
        const headers = {
          'Content-Type': 'application/json',
          ...((await this.headersProvider?.()) ?? {}),
        };
        const res = await this.axios.post(this.url, payload, { headers });
        return typeof res.data === 'string' ? res.data : JSON.stringify(res.data);
      }
    }
    ```

=== "WebSocket adapter"

    ```typescript
    // generated/client/graph-link-ws-adapter.ts
    // Generated when generateDefaultWsAdapter: true
    export class DefaultGraphLinkWebSocketAdapter {
      constructor(
        private readonly url: string,
        private readonly headersProvider?: () => Promise<Record<string, string> | undefined>,
        private readonly initialReconnectDelayMs: number = 1000,
        private readonly maxReconnectDelayMs: number = 30000
      ) {}
      // Implements graphql-ws protocol with exponential-backoff reconnect.
      // headersProvider result is forwarded as connection_init payload.
    }
    ```

## Initializing the client

=== "Minimal (Fetch)"

    ```typescript
    import { GraphLinkClient } from './generated/client/graph-link-client';
    import { GraphLinkFetchAdapter } from './generated/client/graph-link-fetch-adapter';
    import { DefaultGraphLinkWebSocketAdapter } from './generated/client/graph-link-ws-adapter';

    const adapter = new GraphLinkFetchAdapter('http://localhost:8080/graphql');
    const wsAdapter = new DefaultGraphLinkWebSocketAdapter('ws://localhost:8080/graphql');

    const client = new GraphLinkClient(adapter.call.bind(adapter), wsAdapter);
    ```

=== "With auth headers"

    ```typescript
    import { GraphLinkFetchAdapter } from './generated/client/graph-link-fetch-adapter';

    const adapter = new GraphLinkFetchAdapter(
      'http://localhost:8080/graphql',
      async () => ({ Authorization: `Bearer ${await getToken()}` })
    );

    const client = new GraphLinkClient(adapter.call.bind(adapter));
    ```

=== "Axios + subscriptions"

    ```typescript
    import { GraphLinkAxiosAdapter } from './generated/client/graph-link-axios-adapter';
    import { DefaultGraphLinkWebSocketAdapter } from './generated/client/graph-link-ws-adapter';

    const adapter = new GraphLinkAxiosAdapter(
      'http://localhost:8080/graphql',
      async () => ({ Authorization: `Bearer ${await getToken()}` })
    );

    const wsAdapter = new DefaultGraphLinkWebSocketAdapter(
      'ws://localhost:8080/graphql',
      async () => ({ Authorization: `Bearer ${await getToken()}` })
    );

    const client = new GraphLinkClient(adapter.call.bind(adapter), wsAdapter);
    ```

## Queries

All queries are accessible via `client.queries`. Each method is fully typed — parameters and return types match the schema exactly:

```typescript title="Fetching a vehicle"
// getVehicle returns Promise<GetVehicleResponse>
const res = await client.queries.getVehicle({ id: '42' });

// res.getVehicle is typed as Vehicle
console.log(res.getVehicle.brand);    // Toyota
console.log(res.getVehicle.year);     // 2023
console.log(res.getVehicle.fuelType); // FuelType.GASOLINE
```

```typescript title="generated/responses/get-vehicle-response.ts"
import { Vehicle } from '../types/vehicle';

export interface GetVehicleResponse {
  getVehicle: Vehicle;
}

export function getVehicleResponseFromJson(json: Record<string, unknown>): GetVehicleResponse {
  return {
    getVehicle: vehicleFromJson(json['getVehicle'] as Record<string, unknown>),
  };
}
```

### List queries

```typescript title="Fetching all vehicles"
const res = await client.queries.listVehicles();

// res.listVehicles is Vehicle[] — fully typed
res.listVehicles.forEach(v => {
  console.log(`${v.brand} ${v.model} (${v.year})`);
});

// Filter with full type safety
const electrics = res.listVehicles.filter(v => v.fuelType === FuelType.ELECTRIC);
```

## Mutations

Mutations are available via `client.mutations`. Input types use TypeScript interfaces with optional fields for nullable schema fields (when `optionalNullableInputFields: true`):

```typescript title="Adding a vehicle"
import { FuelType } from './generated/enums/fuel-type';

const added = await client.mutations.addVehicle({
  input: {
    brand: 'Toyota',
    model: 'Camry',
    year: 2023,
    fuelType: FuelType.GASOLINE,
    // ownerId is nullable — omit entirely or pass null
  },
});

console.log(added.addVehicle.id);    // server-assigned ID
console.log(added.addVehicle.brand); // Toyota
```

```typescript title="generated/inputs/add-vehicle-input.ts"
import { FuelType } from '../enums/fuel-type';

export interface AddVehicleInput {
  brand: string;
  model: string;
  year: number;
  fuelType: FuelType;
  ownerId?: string | null;  // optional because nullable in schema
}

export function addVehicleInputToJson(input: AddVehicleInput): Record<string, unknown> {
  return {
    brand: input.brand,
    model: input.model,
    year: input.year,
    fuelType: input.fuelType,
    ownerId: input.ownerId ?? null,
  };
}
```

## Subscriptions

Subscriptions are available via `client.subscriptions`. Subscription methods return an object with an `unsubscribe()` method:

```typescript title="Subscribing to vehicle events"
const sub = client.subscriptions.vehicleAdded({
  onData: (event) => {
    console.log('New vehicle:', event.vehicleAdded.brand);
  },
  onError: (err) => console.error('Subscription error:', err),
  onComplete: () => console.log('Subscription ended'),
});

// Later — clean up
sub.unsubscribe();
```

## RxJS observables mode

Set `"observables": true` in the TypeScript config to generate Observable-returning methods instead of Promise/callback. This is the idiomatic choice for Angular projects:

```typescript title="With observables: true"
import { Observable } from 'rxjs';

// Queries and mutations return Observable<T>
client.queries.listVehicles().subscribe(res => {
  this.vehicles = res.listVehicles;
});

// Subscriptions also return Observable<T>
client.subscriptions.vehicleAdded().subscribe(event => {
  this.vehicles.push(event.vehicleAdded);
});

// In Angular templates — use the async pipe
// vehicles$ = client.queries.listVehicles().pipe(map(r => r.listVehicles));
// <li *ngFor="let v of vehicles$ | async">{{ v.brand }}</li>
```

## Operation name in URL

Set `"operationNameAsParameter": true` to append the operation name as a query parameter on every HTTP request — useful for server-side logging and APM:

=== "JSON"

    ```json title="glink.json"
    {
      "clientConfig": {
        "typescript": { "operationNameAsParameter": true }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml"
    clientConfig:
      typescript:
        operationNameAsParameter: true
    ```

The adapter function gains a second parameter and the client sends requests to `<url>?operationName=OperationName`.

## Readonly types

Set `"immutableTypeFields": true` (the default) to generate `readonly` on every field in type interfaces:

```typescript title="With immutableTypeFields: true (default)"
export interface Vehicle {
  readonly id: string;
  readonly brand: string;
  readonly model: string;
  readonly year: number;
}
```

Set to `false` if you need to mutate response objects after deserialization.

## Serialization and union discriminants (v5.0.0+)

`toJson`/`fromJson` generation is mandatory since v5.0.0 for types, inputs, enums, and interfaces — there is no config flag to suppress it. The generated client decodes every response through the generated `fromJson` functions instead of casting the raw parsed JSON, so a field's wire name (from the schema) and its generated identifier (after [identifier normalization](configuration.md#identifier-normalization)) always stay in sync.

TypeScript interfaces that implement a union or interface type also gain a `readonly __typename: 'TypeName'` discriminant field, plus a union-level `toJson()` that switches on `__typename`:

```typescript title="Generated union member and toJson dispatch"
export interface Car extends SearchResult {
  readonly __typename: 'Car';
  readonly id: string;
  readonly make: string;
}

export function searchResultToJson(value: SearchResult): Record<string, unknown> {
  switch (value.__typename) {
    case 'Car':
      return carToJson(value as Car);
    case 'Owner':
      return ownerToJson(value as Owner);
    // ...
  }
}
```

This completes proper discriminated-union (de)serialization on the TypeScript target — narrowing on `result.__typename` (or a `switch`) gives you the concrete member type with no manual casting.

## Error handling

The generated client throws a `GraphLinkException` when the server returns GraphQL errors:

```typescript title="Error handling"
import { GraphLinkException } from './generated/client/graph-link-client';

try {
  const res = await client.queries.getVehicle({ id: 'bad-id' });
  console.log(res.getVehicle.brand);
} catch (e) {
  if (e instanceof GraphLinkException) {
    for (const error of e.errors) {
      console.error('GraphQL error:', error.message);
    }
  } else {
    // Network error, timeout, etc.
    console.error('Request failed:', e);
  }
}
```

!!! info "Testing without mocking frameworks"
    The adapter is a plain function — `(payload: string) => Promise<string>`. In tests, pass a lambda that returns the JSON you want: `adapter: async () => JSON.stringify({ data: { getVehicle: { id: '1', brand: 'Toyota', ... } } })`. No HTTP mocking library needed.

## Using with Angular

In Angular, inject the `GraphLinkClient` as a singleton service and use `observables: true` for the most ergonomic integration with Angular's reactive patterns:

```typescript title="Angular service setup"
import { Injectable } from '@angular/core';
import { GraphLinkClient } from './generated/client/graph-link-client';
import { GraphLinkFetchAdapter } from './generated/client/graph-link-fetch-adapter';
import { DefaultGraphLinkWebSocketAdapter } from './generated/client/graph-link-ws-adapter';

@Injectable({ providedIn: 'root' })
export class ApiService {
  readonly client: GraphLinkClient;

  constructor(private authService: AuthService) {
    const adapter = new GraphLinkFetchAdapter(
      'https://api.example.com/graphql',
      async () => ({ Authorization: `Bearer ${this.authService.getToken()}` })
    );
    const wsAdapter = new DefaultGraphLinkWebSocketAdapter(
      'wss://api.example.com/graphql',
      async () => ({ Authorization: `Bearer ${this.authService.getToken()}` })
    );
    this.client = new GraphLinkClient(adapter.call.bind(adapter), wsAdapter);
  }
}
```

## Using with React

Create the client once (outside the component tree) and use it directly in hooks:

```typescript title="React hook usage"
// api.ts — create client once
import { GraphLinkClient } from './generated/client/graph-link-client';
import { GraphLinkFetchAdapter } from './generated/client/graph-link-fetch-adapter';

const adapter = new GraphLinkFetchAdapter('/graphql');
export const api = new GraphLinkClient(adapter.call.bind(adapter));

// VehicleList.tsx
import { useEffect, useState } from 'react';
import { api } from './api';
import { Vehicle } from './generated/types/vehicle';

export function VehicleList() {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);

  useEffect(() => {
    api.queries.listVehicles().then(res => setVehicles(res.listVehicles));
  }, []);

  return <ul>{vehicles.map(v => <li key={v.id}>{v.brand} {v.model}</li>)}</ul>;
}
```
