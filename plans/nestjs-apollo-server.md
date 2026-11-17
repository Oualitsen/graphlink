# NestJS / Apollo server

`serverConfig.nestApollo` generates a NestJS server from a schema. This document records what the target does,
how it was verified, and what it deliberately does not do yet.

## What is generated

| Output | Notes |
|---|---|
| `services/*.ts`, `guards/*.ts`, `interfaces/graph-link-interceptor.ts` | Abstract classes, so each is its own injection token. |
| `resolvers/<service>.resolver.ts` | `@Resolver()` with `@Query`, `@Mutation`, `@Subscription`. |
| `resolvers/<type>-fields.resolver.ts` | `@Resolver('Type')` with `@ResolveField` for `@glMapsTo`, batch and pass-through fields. |
| `rest/<service>.controller.ts`, `rest/rest-fallback.controller.ts` | `@Controller` per service with `@glRest*` operations; the fallback answers 405 and 404 as JSON. |
| `graphlink.module.ts` | `GraphLinkModule.forRoot({ imports, contextFactory, maxQueryDepth })`. |
| `graphlink-exception.filter.ts` | Global filter: GraphQL errors on the GraphQL path, `{ status, error }` on REST paths. |
| `graphlink-request-guards.ts` | Query depth guard for HTTP and WebSocket. |

Everything shared with the Express target (service and guard signatures, loaders, context, type defs, import
helpers) lives in `typescript_apollo_server_base.dart`. Express and NestJS differ only in how a contract is declared
(`declareContract`, `declareInterceptor`), in the resolvers, and in the entry point. The REST argument-reading logic is
shared through `ExpressApolloRestSerializer`, whose service, guard, interceptor and context access are overridable.

Versions: Nest 11, `@nestjs/apollo` 13 and `@nestjs/graphql` 13 on Apollo Server 5 (`@as-integrations/express5`),
`graphql-ws` 6, `graphql-upload` 17.1.

## Verification

Run from `server_integration_tests/`:

- `make ci-http-nestjs`: fault suite (49), REST suite (202 of 203 as the runner counts it), GraphQL suite (94). No known defects.
- `make ci-nestjs-client CLIENT=<dart|ts|java|kotlin|java_reactive|python|go>`.
- `make ci-upload-nestjs`: the Dart upload harness against `servers/nestjs_upload_server`.
- `test/server/nestjs/`: serializer unit tests.

Swift is not run against this server; CI runs Swift against the Java server only.

## Not implemented

### Less idiomatic than a hand-written Nest server

- **REST handlers use `@Req()` and `@Res()`.** Arguments are read with the shared helpers (`pathArg`, `queryArg`,
  `bodyArg`, ...). They are not `@Param`, `@Query`, `@Body`, `@Headers` and pipes (`ParseIntPipe`,
  `ValidationPipe`). The helpers keep argument checking identical to the Express target; replacing them with
  decorators and pipes is the largest remaining step toward idiomatic Nest.
- **`@glValidate` guards and `@glIntercept` are GraphLink abstractions.** They are injected and called from the
  resolver or controller body. They are not Nest `CanActivate` guards or `NestInterceptor`s, so `@UseGuards` is not
  generated.
- **DataLoaders are created in the Apollo `context` function**, not through request-scoped providers.

### Options and wiring

- **`port` has no effect.** The application's `main.ts` decides the port; the option exists for parity with the other
  server configs.
- **No generated `main.ts` or bootstrap.** `NestFactory.create(AppModule, { rawBody: true })` is required when the
  schema has form-encoded REST operations. Without it, form requests fail with an explanatory error at request time,
  not at startup.
- **Static module options.** `forRoot` only, no `forRootAsync`, so `contextFactory` cannot receive injected providers.
- **Express platform only.** The Fastify platform is not supported.
- **`graphql-ws` only.** The legacy `subscriptions-transport-ws` protocol is not served.

### Not verified

- **No compiled run.** The test servers run under `tsx`, which does not emit decorator metadata, so every constructor
  parameter uses an explicit `@Inject(Token)`. The generated code is typechecked with `tsc` using
  `emitDecoratorMetadata`, but a `nest build` output was never run.
- **Swift client** against this server.
- **Nest 12** (the current npm release) is untested.
- **Unit tests are shallow** beyond the basics; guards, interceptors and uploads are covered through the integration
  suites only.

### Conventions not followed

- **`TypeScriptCodeGenUtils` has no builders for decorators, constructors or `@Module` wrappers**, so those are composed
  as strings. Only `isAbstract` was added to `createClass`. Adding builders for them is the right follow-up.
- **No `examples/nestjs/` project.** `ARCHITECTURE.md` lists an end-to-end example for new targets.
- **The site build was not run**; only the sources under `site/docs-src/` and `mkdocs.yml` were edited.

## Changes outside the NestJS target

- The batch-mapping loader called `items.map(sourceOf)`, which inferred `unknown[]` and failed `tsc` on the Express
  server too. It now calls `sourceOf<Parent>(item)`.
- The Java, Java reactive and Kotlin client harnesses (`Fixtures`) did not compile: they built
  `DefaultGraphLinkClientAdapter` without the JSON decoder the generated adapter requires.
- `nestjs_server/src/impl/` is a copy of the Express test implementations. Keep the two in step.
