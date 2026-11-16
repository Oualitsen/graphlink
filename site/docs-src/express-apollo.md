---
title: "Express & Apollo GraphQL Server Generator"
description: "Generate an Express + Apollo Server GraphQL scaffold in TypeScript: service interfaces, async resolvers, DataLoader batching and graphql-ws subscriptions."
---

# Express / Apollo Server

GraphLink generates a complete Express + Apollo Server scaffold from your schema — typed service
interfaces, resolvers, WebSocket subscriptions, and (optionally) a ready-to-run HTTP server entry
point. It mirrors the Spring Boot server model: you implement generated interfaces, GraphLink owns
the wiring.

## Server mode config

Set `"mode": "server"` and provide an `"expressApollo"` section under `serverConfig`:

=== "JSON"

    ```json title="glink.json"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "server",
      "typeMappings": {
        "ID":      "string",
        "String":  "string",
        "Float":   "number",
        "Int":     "number",
        "Boolean": "boolean",
        "Null":    "null"
      },
      "outputDir": "src/generated",
      "serverConfig": {
        "expressApollo": {
          "port": 4000,
          "graphqlPath": "/graphql",
          "generateEntryPoint": true
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
      ID: string
      String: string
      Float: number
      Int: number
      Boolean: boolean
      "Null": "null"
    outputDir: src/generated
    serverConfig:
      expressApollo:
        port: 4000
        graphqlPath: /graphql
        generateEntryPoint: true
    ```

| Option | Default | Description |
|---|---|---|
| `port` | `4000` | Port the generated entry point's HTTP server listens on. |
| `graphqlPath` | `/graphql` | Path the Apollo middleware and the WebSocket server are mounted on. |
| `generateEntryPoint` | `true` | Generate `src/generated/index.ts` with a ready-to-call `createServer(services)` function. Set to `false` if you want to wire Express/Apollo yourself and only use the generated types, resolvers, and service interfaces. |
| `useResolveInfo` | `false` | Adds a `GraphQLResolveInfo` parameter to every generated service method, so resolvers can inspect the requested selection set (e.g. for partial-fetch optimizations). |
| `injectContext` | `false` | Adds a `GraphLinkContext` parameter to every generated service method. Equivalent to putting `@glInjectContext` on every field — use that directive instead to opt in per-field. |

## What gets generated

For a schema with `Article` and `Author` types:

```
src/generated/
  index.ts                          ← generated, entry point (createServer)
  context.ts                        ← GraphLinkContext, GraphLinkLoaders
  typeDefs.ts                       ← the processed .graphql schema as a string
  resolvers/
    build-resolvers.ts              ← generated, never touch
  services/
    article-service.ts              ← implement this
    author-service.ts               ← implement this
  types/
    article.ts
    author.ts
  inputs/
    create-article-input.ts
  enums/
    article-type.ts
```

Resolvers are generated and never touched by hand. Service interfaces are what you implement —
same split as the Spring Boot target.

## Service interfaces

For each group of operations sharing a root type, GraphLink generates one service interface:

```typescript title="generated/services/article-service.ts"
export interface ArticleService {
   getArticle(id: string): Promise<Article>;
   listArticles(): Promise<Article[]>;
   createArticle(input: CreateArticleInput): Promise<Article>;
   articleCreated(): AsyncIterable<Article>;
}
```

- Queries and mutations return `Promise<T>`
- Subscriptions return `AsyncIterable<T>` — Apollo's native async-generator subscription model
- Method signatures mirror the schema declarations exactly

Implement the interface as a plain class:

```typescript title="src/impl/article-service.ts — your code"
import { ArticleService } from '../generated/services/article-service.js';
import { Article } from '../generated/types/article.js';
import { CreateArticleInput } from '../generated/inputs/create-article-input.js';

export class ArticleServiceImpl implements ArticleService {
  async getArticle(id: string): Promise<Article> {
    return db.articles.findById(id);
  }

  async listArticles(): Promise<Article[]> {
    return db.articles.findAll();
  }

  async createArticle(input: CreateArticleInput): Promise<Article> {
    return db.articles.insert(input);
  }

  async *articleCreated(): AsyncIterable<Article> {
    for await (const article of articleCreatedPubSub) {
      yield article;
    }
  }
}
```

!!! info "Keep generated code separate"
    Put implementations under your own directory (e.g. `src/impl/`) — never inside `src/generated/`.
    Re-running the generator overwrites everything under `outputDir` unconditionally.

## The entry point — `createServer`

With `generateEntryPoint: true` (the default), `index.ts` exports a `GraphLinkServices` interface
(one property per generated service) and a `createServer(services)` function that wires Express,
Apollo Server, and the `graphql-ws` WebSocket server together:

```typescript title="src/start.ts — your code"
import { createServer } from './generated/index.js';
import { ArticleServiceImpl } from './impl/article-service.js';
import { AuthorServiceImpl } from './impl/author-service.js';

const httpServer = await createServer({
  articleService: new ArticleServiceImpl(),
  authorService: new AuthorServiceImpl(),
});

httpServer.listen(4000, () => {
  console.log('Server ready at http://localhost:4000/graphql');
});
```

One class can satisfy multiple service slots — pass the same instance under several keys in the
`services` object when it makes sense to group related operations behind one implementation.

`createServer` returns a Node `http.Server` (not yet listening), so you can attach it to your own
process lifecycle, health checks, or a graceful-shutdown hook before calling `.listen()`.

## Context and `contextFactory`

`GraphLinkContext` starts as an empty extensible interface (`extends Record<string, unknown>`).
Add fields to it via TypeScript [declaration merging](https://www.typescriptlang.org/docs/handbook/declaration-merging.html)
in your own code, and populate them per-request with `contextFactory`:

```typescript title="src/impl/my-context.ts — your code"
declare module '../generated/context.js' {
  interface GraphLinkContext {
    userId?: string;
  }
}
```

```typescript title="src/start.ts — populate context per request"
const httpServer = await createServer({
  // ...services
  contextFactory: async (req, res) => ({
    userId: await getUserIdFromAuthHeader(req.headers.authorization),
  }),
});
```

`contextFactory` runs once per HTTP request (and once per WebSocket connection for subscriptions).
Fields declared with `@glInjectContext`, or every field when `injectContext: true` is set, receive
this context object as an argument.

## Concurrent execution

Every generated resolver is an `async` function that awaits your service, for example `catalog: async (_, __, context, info) => { ... }`. Apollo Server resolves the sibling fields of a query without waiting for each one in turn, so independent fields of the same request can load concurrently, and the event loop is never blocked while your service waits on I/O. For the N+1 problem inside one field, use `@glSkipOnServer(batch: true)`, which generates a per-request DataLoader (next section).

## Batch mappings and DataLoader

`@glSkipOnServer(batch: true)` fields (see [`@glSkipOnServer` & `@glSkipOnClient`](skip-directives.md))
generate a per-request [DataLoader](https://github.com/graphql/dataloader) instead of a Spring
`@BatchMapping` handler — same N+1-avoidance guarantee, idiomatic to the Node ecosystem:

```typescript title="generated/loaders/author-schema-mappings-loaders.ts"
export function createAuthorArticlesLoader(
  service: AuthorSchemaMappingsService,
  context: GraphLinkContext,
): DataLoader<Author, Article[] | null> {
  return new DataLoader(async (authors) => service.articles(authors, context));
}
```

Loaders are constructed fresh per request inside `createServer`'s `context` function and attached
to `context.loaders` — never shared across requests, avoiding the classic DataLoader cross-request
cache-leak bug.

## Subscriptions

Subscriptions use `graphql-ws` over a `WebSocketServer` mounted on the same HTTP server and path as
the query/mutation endpoint. The generated service method is an `AsyncIterable`, most naturally
implemented with an async generator backed by a pub/sub channel:

```typescript title="Push-based subscription with an async queue"
import { PubSub } from 'graphql-subscriptions';

const pubsub = new PubSub();

async createArticle(input: CreateArticleInput): Promise<Article> {
  const article = await db.articles.insert(input);
  pubsub.publish('ARTICLE_CREATED', article);
  return article;
}

async *articleCreated(): AsyncIterable<Article> {
  for await (const { article } of pubsub.asyncIterator('ARTICLE_CREATED')) {
    yield article;
  }
}
```

Any `AsyncIterable<T>` works — `graphql-subscriptions`' `PubSub`, a hand-rolled async queue, or a
message-broker-backed iterator all satisfy the generated interface.

## Responses serialize via `toJson()`

Since v5.0.0, generated resolvers serialize the service's return value through the type's generated
`toJson()` before handing it to Apollo, matching the Java/Kotlin Spring targets. This keeps the wire
payload correct even when identifier normalization or keyword-safe renaming makes a generated
TypeScript property name diverge from the GraphQL field name — you never need to think about it from
inside your service implementation, which still returns plain typed objects.

## File uploads

When your schema uses the `Upload` scalar, generated resolvers accept the
[`graphql-upload`](https://github.com/jaydenseric/graphql-upload)-style `Promise<FileUpload>` and
your service method receives an already-resolved stream:

```graphql title="Schema with Upload scalar"
scalar Upload

type Mutation {
  uploadDocument(file: Upload!): String!
}
```

```typescript title="generated/services/document-service.ts"
export interface DocumentService {
   uploadDocument(file: GLUpload): Promise<string>;
}
```

## `@glIntercept`

Add an `interceptor` service to run a shared pre-resolver check (authorization, rate limiting, ...)
before any annotated query, mutation, subscription, or batch-mapped field executes:

```typescript title="Generated interfaces/graph-link-interceptor.ts"
export interface GraphLinkInterceptor {
   runBefore(
     tag: GlInterceptorTag | null,
     operation: string,
     args: unknown[],
     context: GraphLinkContext | null,
     info: GraphQLResolveInfo | null,
   ): void;
}
```

```typescript title="src/impl/interceptor.ts — your code"
export class InterceptorImpl implements GraphLinkInterceptor {
  runBefore(tag, operation, args, context) {
    if (tag === GlInterceptorTag.Admin && context?.userId !== ADMIN_ID) {
      throw new Error('Forbidden');
    }
  }
}
```

Pass it as `interceptor` on the `services` object passed to `createServer` — if the schema uses
`@glIntercept` anywhere and no `interceptor` is provided, `createServer` throws immediately at
startup instead of failing lazily on the first request.

→ **[Full `@glIntercept` reference](directives.md#glintercept)**

## Validation with `@glValidate`

Exactly like the Spring Boot target: `@glValidate` on a mutation adds a `validateX(...)` method to
the service interface, called by the generated resolver before the main method. Throw to abort the
mutation before any business logic runs. See [Spring Boot Server → Validation with `@glValidate`](spring-server.md#validation-with-glvalidate)
for the full write-up — the contract is identical, only the language differs.

## REST operations (`@glRest*`)

The operations marked with the [REST directives](rest-client.md) are served by the same server. GraphLink generates one Express router, `rest/build-rest-router.ts`, that `createServer` mounts next to the GraphQL endpoint; every route calls the same service interface as the GraphQL resolvers. REST operations are not part of the GraphQL schema, and their service methods take no `GraphQLResolveInfo`.

```ts title="Generated rest/build-rest-router.ts (excerpt)"
router.get("/products/:id", handle(async (req, res) => {
   const id = pathArg(req, "id", S.string);
   const context = await restContext(services, req, res);
   const result = await services.productService.product(id, context);
   sendJson(res, result != null ? Product.toJson(result) : result);
}));
```

Values are read from the part of the request the directive names and validated before your code runs: `Int` must be a 32-bit integer, `Boolean` is `true`/`false`, an enum must be one of its values, a JSON body is checked field by field against the input type (`required`, types, enums, lists). Anything wrong is a `400`, a body that is not JSON a `415`, a wrong method on a known path a `405`, an unknown path under the REST prefix a `404`, and an exception thrown by a service a `500`; none of them carries a stack trace. A `null` result is an empty `200`, `Void` is `204`, `response: TEXT` is `text/plain`. `contextFactory(req, res)` supplies the `context` argument exactly as it does for GraphQL.

**Uploads.** `@glRestPart` on an `Upload` / `[Upload!]` (plus scalar and enum text parts) is read by `rest/uploads.ts` with [`busboy`](https://github.com/mscdex/busboy): each file is spooled to a temporary directory (removed when the response closes, files above 100 MB are a `413`) and reaches the service as a `FileUpload` whose `createReadStream()` can be called more than once. `@glRestBody` on an `Upload` hands the request stream itself to the service (`createReadStream()` once). Add `busboy` and `@types/busboy` to the server's `package.json` when a schema has multipart parts; raw bodies need nothing. These uploads are independent of GraphQL uploads: a schema with REST uploads only does not need `graphql-upload`.

**Forms** (`@glRestField`) are read with `express.text` for `application/x-www-form-urlencoded` and `URLSearchParams`; a body of another type is a `415`. **Input objects, lists of objects and JSON text** in the query string or a form are read from nested keys (`address.city`, `items[0][name]`) or parsed from JSON and then validated against the input's shape (`nestedArg`, `jsonArg`).

**Downloads.** A `@glDownload` scalar is the generated `GraphLinkDownload` (`rest/download.ts`): return `{ data, filename?, contentType?, length? }` where `data` is a `Readable`, a `Uint8Array` or a string. A stream is piped (a failure destroys the response), `Content-Disposition: attachment` is written with an RFC 5987 `filename*` for non-ASCII names, and `null` is `204`. `Range` requests are not served.

**`responsePath`** nests the result (`{"data":{"items":[...]}}` for `responsePath: "data.items"`).

**Interceptors.** `@glIntercept` (on the operation or on a block) calls `interceptor.runBefore(tag, operation, args, context)` with the decoded arguments before `@glValidate` and the service; pass `interceptor` in the services you give `createServer`. Throw `new RestError(403, 'Forbidden')` (exported by `rest/support`) to deny; any other error is a `500`. `contextFactory(req, res)` supplies `context`, as for GraphQL.

Rejected at generation time with a message: an input object as a multipart part, a recursive input object in a query or a form, and lists of lists. The shapes otherwise match [Spring Boot](spring-server.md#rest-operations-glrest).

## Development workflow

```bash
glink -c config.json          # regenerate src/generated/
npx tsc --noEmit               # typecheck
npx tsx src/start.ts           # run
```

Regeneration only touches files under `outputDir` (`src/generated/` above) — your `src/impl/` and
`src/start.ts` are never touched.
