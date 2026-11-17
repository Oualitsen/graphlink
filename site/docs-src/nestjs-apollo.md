---
title: "NestJS & Apollo GraphQL Server Generator"
description: "Generate a NestJS + Apollo GraphQL server in TypeScript: injectable service contracts, @Resolver and @Controller classes, DataLoader batching, graphql-ws subscriptions, REST and file uploads."
---

# NestJS / Apollo Server

GraphLink generates a NestJS server from your schema, written the way you would write it by hand:
`@Resolver` classes for GraphQL, `@Controller` classes for `@glRest*` operations, and a dynamic
`GraphLinkModule` you import. Every collaborator is constructor-injected. You implement the services;
GraphLink owns the wiring. The service model is the same as in the [Express / Apollo](express-apollo.md) target.

## Server mode config

```json title="glink.json"
{
  "schemaPaths": ["schema/*.graphql"],
  "mode": "server",
  "typeMappings": { "ID": "string", "String": "string", "Float": "number", "Int": "number", "Boolean": "boolean", "Null": "null" },
  "outputDir": "src/generated",
  "serverConfig": {
    "nestApollo": {
      "port": 3000,
      "graphqlPath": "/graphql",
      "generateEntryPoint": true,
      "injectContext": false,
      "useResolveInfo": false
    }
  }
}
```

| Option | Default | Description |
|---|---|---|
| `port` | `3000` | Informational; your `main.ts` decides the port. |
| `graphqlPath` | `/graphql` | Path the Apollo endpoint, the query depth limit and the WebSocket server are bound to. |
| `generateEntryPoint` | `true` | Generate `graphlink.module.ts` and `index.ts`. Set to `false` to wire the generated resolvers and controllers yourself. |
| `injectContext` | `false` | Pass `GraphLinkContext` to every service method. Use `@glInjectContext` to opt in per field. |
| `useResolveInfo` | `false` | Pass `GraphQLResolveInfo` to every service method. |

Your `tsconfig.json` needs the standard Nest decorator options:

```json
{ "compilerOptions": { "experimentalDecorators": true, "emitDecoratorMetadata": true } }
```

## What gets generated

```
src/generated/
  graphlink.module.ts        ← GraphLinkModule.forRoot(...)
  graphlink.options.ts       ← GraphLinkModuleOptions, GRAPHLINK_OPTIONS
  graphlink-exception.filter.ts
  index.ts                   ← exports the module, services, guards, interceptor
  services/                  ← abstract classes: implement these
  guards/                    ← abstract classes for @glValidate
  resolvers/
    article-service.resolver.ts   ← @Resolver(): queries, mutations, subscriptions
    author-fields.resolver.ts     ← @Resolver('Author'): @glMapsTo fields, batch loaders
  rest/
    rest-item-service.controller.ts   ← @Controller(): @glRest operations
  types/ inputs/ enums/
```

## Services are abstract classes

A generated service is an abstract class, so it is its own injection token:

```typescript title="generated/services/article-service.ts"
export abstract class ArticleService {
   abstract getArticle(id: string): Promise<Article>;
   abstract createArticle(input: CreateArticleInput): Promise<Article>;
   abstract articleCreated(): AsyncIterable<Article>;
}
```

Implement it as an ordinary provider, with whatever dependencies it needs:

```typescript title="src/articles/article.service.ts — your code"
@Injectable()
export class ArticleServiceImpl implements ArticleService {
  constructor(private readonly articles: ArticleRepository) {}

  async getArticle(id: string): Promise<Article> {
    return this.articles.findById(id);
  }
  // ...
}
```

## Wiring

Provide the implementations in a module and pass that module to `GraphLinkModule.forRoot`:

```typescript title="src/app.module.ts"
@Module({
  providers: [{ provide: ArticleService, useClass: ArticleServiceImpl }],
  exports: [ArticleService],
})
class ServicesModule {}

@Module({ imports: [GraphLinkModule.forRoot({ imports: [ServicesModule] })] })
export class AppModule {}
```

```typescript title="src/main.ts"
const app = await NestFactory.create(AppModule, { rawBody: true });
app.enableCors();
await app.listen(3000);
```

`rawBody: true` is only needed when the schema has form-encoded `@glRest*` operations.

`forRoot` takes:

| Option | Description |
|---|---|
| `imports` | Modules that provide and export every service, guard and the interceptor. |
| `contextFactory` | `(req, res) => GraphLinkContext`, called for every HTTP request. |
| `maxQueryDepth` | Query depth limit for HTTP and WebSocket operations. Default `32`. |

## What follows the schema

- **Resolvers.** Queries, mutations and subscriptions are `@Query`, `@Mutation` and `@Subscription` methods. A
  `@glValidate` guard runs before the service call and a `@glIntercept` interceptor runs before the guard.
- **Mapped fields.** `@glMapsTo` fields are `@ResolveField` methods; batch mappings are served from per-request
  `DataLoader`s.
- **REST.** Each service with `@glRest*` operations gets a `@Controller`. Argument reading, validation and error
  bodies are the same as in the Express target, and unknown or wrong-method requests under the REST prefix answer
  404 and 405 as JSON.
- **Uploads.** GraphQL multipart uploads need `graphql-upload` (`^17.1.0`) in your `package.json`; REST uploads need `busboy`.
- **Errors.** Malformed or oversized request bodies are answered by the generated exception filter: GraphQL errors on
  the GraphQL path, `{ status, error }` JSON on REST paths.

## Dependencies

```json
"@apollo/server": "^5", "@as-integrations/express5": "^1", "@nestjs/apollo": "^13", "@nestjs/common": "^11",
"@nestjs/core": "^11", "@nestjs/graphql": "^13", "@nestjs/platform-express": "^11", "dataloader": "^2",
"graphql": "^16", "graphql-ws": "^6", "reflect-metadata": "^0.2", "rxjs": "^7"
```

The generated code is tested against every GraphLink client (Dart, TypeScript, Java, Kotlin, Python, Go) with the same
fault, REST and GraphQL suites as the Express server.
