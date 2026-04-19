# TypeScript Express + Apollo Server Generation

## Philosophy

Same architecture as Spring Boot server mode: one `.graphql` schema → fully typed service interfaces,
resolver wiring, validation guards, and DataLoader batching — zero runtime dependency on GraphLink.

The developer implements business logic only. All HTTP wiring, resolver routing, schema mapping,
and batching infrastructure is generated.

---

## What Gets Generated

| Artifact | Description |
|---|---|
| `typeDefs.ts` | Clean SDL string for Apollo — all `@gl*` directives stripped |
| `types/` | TypeScript interfaces for all GraphQL object types |
| `inputs/` | TypeScript interfaces for all GraphQL input types |
| `enums/` | TypeScript string enums |
| `services/` | Service interfaces — one per domain |
| `guards/` | Validation guard interfaces — one per domain |
| `resolvers/` | Resolver wiring (`buildResolvers`) with schema/batch mappings |
| `loaders/` | DataLoader factories for batch mappings |
| `index.ts` | Entry point — Express + Apollo server wired up |

---

## 1. Clean `typeDefs`

GraphLink reads all `.graphql` files, merges them, then:
- Removes all `@gl*` directive definitions and usages (`@glCache`, `@glCacheInvalidate`, `@glSkipOnServer`, `@glBatchMapping`, etc.)
- Removes fields annotated with `@glSkipOnServer` entirely
- Removes types that become empty after field removal
- Outputs a valid SDL string

```typescript
// GENERATED — typeDefs.ts
export const typeDefs = `
  type Vehicle {
    id: ID!
    brand: String!
    year: Int!
    owner: Owner!
  }

  type Query {
    getVehicle(id: ID!): Vehicle!
    listVehicles: [Vehicle!]!
  }

  type Mutation {
    addVehicle(input: AddVehicleInput!): Vehicle!
  }
`;
```

---

## 2. Types, Inputs, Enums

Same mapping rules as the TypeScript client plan. Reuses the same serializer.

| GraphQL | TypeScript |
|---|---|
| `type Foo` | `export interface Foo { ... }` |
| `input FooInput` | `export interface FooInput { ... }` |
| `enum FooEnum` | `export enum FooEnum { A = 'A', ... }` |
| `String!` | `string` |
| `String` | `string \| null` |

---

## 3. Service Interfaces

One interface per domain, derived from Query/Mutation/Subscription root fields grouped by type prefix,
same logic as Spring Boot.

```typescript
// GENERATED — services/VehicleService.ts
export interface VehicleService {
  getVehicle(id: string): Promise<Vehicle>;
  listVehicles(): Promise<Vehicle[]>;
  addVehicle(input: AddVehicleInput): Promise<Vehicle>;
}
```

**Schema mapping methods** (non-batch) are added to the owning service:
```typescript
export interface VehicleService {
  // ...root fields above...
  // schema mapping — Vehicle.owner
  getVehicleOwner(vehicle: Vehicle): Promise<Owner>;
}
```

**Batch mapping methods** use the list signature, matching Spring Boot's `@BatchMapping` pattern:
```typescript
export interface VehicleService {
  // batch mapping — Vehicle.owner
  getVehicleOwners(vehicles: Vehicle[]): Promise<Map<Vehicle, Owner>>;
}
```

---

## 4. Validation Guards

One guard interface per domain. Each resolver has a corresponding `validate*` method.
Throwing inside a validate method aborts the resolver and returns a GraphQL error.

```typescript
// GENERATED — guards/VehicleGuard.ts
export interface VehicleGuard {
  validateGetVehicle(id: string): Promise<void>;
  validateListVehicles(): Promise<void>;
  validateAddVehicle(input: AddVehicleInput): Promise<void>;
}
```

Guards are optional — `buildResolvers` accepts them as an optional second argument.
If not provided, validation is skipped.

---

## 5. DataLoaders (Batch Mappings)

For every `isBatch = true` schema mapping, a DataLoader factory is generated.

```typescript
// GENERATED — loaders/VehicleLoaders.ts
import DataLoader from 'dataloader';

export function createVehicleOwnerLoader(service: VehicleService) {
  return new DataLoader<Vehicle, Owner>(async (vehicles) => {
    const map = await service.getVehicleOwners([...vehicles]);
    return vehicles.map(v => map.get(v) ?? new Error(`Owner not found for vehicle ${v.id}`));
  });
}
```

Loaders are instantiated per-request inside `buildResolvers` to prevent cross-request cache leaks.

---

## 6. Resolver Wiring

`buildResolvers` wires everything together — root resolvers, schema mappings, batch mappings,
and guard calls.

```typescript
// GENERATED — resolvers/buildResolvers.ts
import { IResolvers } from '@graphql-tools/utils';
import { createVehicleOwnerLoader } from '../loaders/VehicleLoaders';

export function buildResolvers(
  vehicleService: VehicleService,
  vehicleGuard?: VehicleGuard,
): IResolvers {
  // per-request DataLoaders
  const vehicleOwnerLoader = createVehicleOwnerLoader(vehicleService);

  return {
    Query: {
      getVehicle: async (_, { id }) => {
        await vehicleGuard?.validateGetVehicle(id);
        return vehicleService.getVehicle(id);
      },
      listVehicles: async () => {
        await vehicleGuard?.validateListVehicles();
        return vehicleService.listVehicles();
      },
    },
    Mutation: {
      addVehicle: async (_, { input }) => {
        await vehicleGuard?.validateAddVehicle(input);
        return vehicleService.addVehicle(input);
      },
    },
    Vehicle: {
      // batch mapping — uses DataLoader
      owner: (vehicle) => vehicleOwnerLoader.load(vehicle),
    },
  };
}
```

**Forbid mapping** — field that must not be resolved (throws `ForbiddenError`):
```typescript
Vehicle: {
  secretField: () => { throw new GraphQLError('Forbidden', { extensions: { code: 'FORBIDDEN' } }); },
}
```

**Identity mapping** — field returned directly from parent, no service call needed:
```typescript
Vehicle: {
  brand: (vehicle) => vehicle.brand,
}
```

**Forwarded mapping** — field forwarded to getter on the mapped server type, no service method:
```typescript
Vehicle: {
  displayName: (vehicle) => vehicle.displayName,
}
```

---

## 7. Entry Point

```typescript
// GENERATED — index.ts
import express from 'express';
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { typeDefs } from './typeDefs';
import { buildResolvers } from './resolvers/buildResolvers';

// TODO: replace with your implementations
import { MyVehicleService } from './impl/MyVehicleService';

async function main() {
  const app = express();
  app.use(express.json());

  const server = new ApolloServer({
    typeDefs,
    resolvers: buildResolvers(new MyVehicleService()),
  });

  await server.start();
  app.use('/graphql', expressMiddleware(server));

  app.listen(4000, () => console.log('GraphQL ready at http://localhost:4000/graphql'));
}

main();
```

---

## Output Structure

```
generated/
  typeDefs.ts
  types/            ← one file per GraphQL object type
  inputs/           ← one file per GraphQL input type
  enums/            ← one file per GraphQL enum
  services/         ← service interfaces
  guards/           ← validation guard interfaces
  loaders/          ← DataLoader factories (only when batch mappings exist)
  resolvers/
    buildResolvers.ts
  index.ts          ← Express + Apollo entry point
```

---

## Config

```json
{
  "mode": "server",
  "serverConfig": {
    "typescript": {
      "expressApollo": {
        "port": 4000,
        "graphqlPath": "/graphql",
        "generateEntryPoint": true
      }
    }
  }
}
```

| Key | Default | Description |
|---|---|---|
| `port` | `4000` | Port in generated `index.ts` |
| `graphqlPath` | `/graphql` | Apollo middleware mount path |
| `generateEntryPoint` | `true` | Whether to emit `index.ts` |

---

## What is NOT in v1

| Feature | Notes |
|---|---|
| Subscriptions | v2 — requires WebSocket transport setup |
| Authentication middleware | User adds to Express; out of scope |
| NestJS target | v2 — wraps same service interfaces in NestJS modules |
| File upload | v2 |
| Context typing | v2 — typed GraphQL context passed to resolvers |

---

## New Files

| File | Role |
|---|---|
| `lib/src/serializers/server_serializers/typescript_server_serializer.dart` | Orchestrates all server output generation |
| `lib/src/serializers/server_serializers/typescript_typedefs_serializer.dart` | Produces clean `typeDefs.ts` — strips `@gl*` directives |
| `lib/src/serializers/server_serializers/typescript_service_serializer.dart` | Generates service interfaces with schema/batch mapping methods |
| `lib/src/serializers/server_serializers/typescript_guard_serializer.dart` | Generates validation guard interfaces |
| `lib/src/serializers/server_serializers/typescript_loader_serializer.dart` | Generates DataLoader factories for batch mappings |
| `lib/src/serializers/server_serializers/typescript_resolver_serializer.dart` | Generates `buildResolvers` with full wiring |
| `lib/src/serializers/server_serializers/typescript_entry_point_serializer.dart` | Generates `index.ts` Express + Apollo entry point |
| `lib/src/config.dart` | Add `TypeScriptServerConfig` + `expressApollo` field on `ServerConfig` |
| `lib/src/main.dart` | Dispatch when `serverConfig.typescript != null` |

---

## Build Order

| Step | What |
|---|---|
| 1 | `TypeScriptServerConfig` + `ExpressApolloConfig` in `config.dart` |
| 2 | `TypeScriptTypeDefsSerializer` — merge schema, strip `@gl*`, emit `typeDefs.ts` |
| 3 | Reuse `TypeScriptSerializer` from client plan for types, inputs, enums |
| 4 | `TypeScriptServiceSerializer` — service interfaces with schema/batch mapping methods |
| 5 | `TypeScriptGuardSerializer` — validation guard interfaces |
| 6 | `TypeScriptLoaderSerializer` — DataLoader factories for `isBatch` mappings |
| 7 | `TypeScriptResolverSerializer` — `buildResolvers` with full resolver wiring |
| 8 | `TypeScriptEntryPointSerializer` — `index.ts` Express + Apollo wiring |
| 9 | `TypeScriptServerSerializer` — orchestrate all above, write output files |
| 10 | Wire dispatch in `main.dart` |
| 11 | Integration test: sample schema → generate → `tsc --noEmit` passes |
