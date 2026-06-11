# `@glAuth` Directive for the TypeScript/Express+Apollo Server

## Goal

Let schema authors declare role-based authorization directly on queries, mutations,
subscriptions, and (non-batch) field mappings:

```graphql
type Query {
  listAuthors: [Author!]! @glAuth(roles: ["ADMIN"])
  getAuthor(id: ID!): Author @glAuth
}
```

- `@glAuth` (no args) → require any authenticated request (`context.auth` present).
- `@glAuth(roles: ["ADMIN"])` → require `context.auth.roles` to intersect with the
  given list.

The generator wires this into the executable schema automatically — the developer
only has to (a) implement an `AuthService` to turn an incoming request/connection into
an `AuthContext`, and (b) annotate schema fields. No per-field resolver code to write.

## Background / prior art

This came out of a discussion about how to make auth "effortless" the way the Spring
Boot annotation-based approach is. For Apollo Server, the standard mechanism is a
**schema directive transformer**: `mapSchema` + `getDirective` from
`@graphql-tools/utils` walk the executable schema once and wrap any field whose config
carries the directive — no codegen per field required, and it composes correctly with
batch (DataLoader) mappings since auth is per-request, not per-item (the field-argument
forwarding limitation from `relatedArticles` does not apply here).

## Design

### 1. Directive registration (parser)

Add to `lib/src/model/built_in_dirctive_definitions.dart`:

```dart
const glAuth = "@glAuth";
const glAuthRolesArg = "roles";
```

Register in `GLParser.directives` (`lib/src/model/new_parser/gl_parser.dart`, near
`glCaptureErrors`):

```dart
glAuth: GLDirectiveDefinition(
  glAuth.toToken(),
  [
    GLArgumentDefinition(glAuthRolesArg.toToken(),
        GLType("[String!]".toToken(), false), []),
  ],
  {
    GLDirectiveScope.QUERY,
    GLDirectiveScope.MUTATION,
    GLDirectiveScope.SUBSCRIPTION,
    GLDirectiveScope.FIELD_DEFINITION,
  },
  false,
),
```

`roles` is optional (defaults to "authenticated, any role") — confirm
`GLArgumentDefinition` supports optional list args without a default value; if not,
make the arg type nullable (`[String!]`) and treat "directive present, `roles` absent
or empty" as "authenticated only".

**Do not** add `@glAuth` to `_skippedDirectives` in `gl_graphql_serializer.dart` —
unlike `@glCache`/`@glSkipOnServer`, this directive needs to survive into the emitted
SDL (`typeDefs.ts`) so the transformer can read it at runtime via `getDirective`.

### 2. Validation

New checks (likely in a new `gl_grammar_auth_extension.dart`, following the convention
in CLAUDE.md):

- `@glAuth` is server-only — error if present in a `client` mode build, or simply
  ignore it client-side (it'll be skipped from client SDL generation the same way
  other server-only directives are, since `@glSkipOnServer`-marked elements never
  reach the client schema, but `@glAuth` itself isn't `@glSkipOnServer` — needs a
  decision: either (a) `@glAuth` only emitted into the **server** typeDefs, stripped
  from client typeDefs, or (b) allowed in both but meaningless on the client). Lean
  towards (a) for a smaller diff blast radius — gate `@glAuth` serialization on
  `mode == server` in `gl_graphql_serializer.dart`.
- `roles`, if present, must be a non-empty list of strings (mirror the
  `glCacheTagList` validation pattern in `gl_grammar_cache_extension.dart`).
- Allowed only on `Query`/`Mutation`/`Subscription` root fields and on
  `@glSkipOnServer` type-mapping fields (batch or non-batch — both fine, see
  Background). Not allowed on plain object/input fields that aren't resolvers.

### 3. Express+Apollo serializer changes

`lib/src/serializers/express_apollo_server_serializer.dart`:

- `serializeTypeDefs()` already calls `GLGraphqlSerializer(grammar).generateSchema()`
  — once `@glAuth` is registered and not skipped, the directive declaration
  (`directive @glAuth(roles: [String!]) on ...`) and per-field usages
  (`@glAuth(roles: ["ADMIN"])`) appear in `typeDefs.ts` automatically. No changes
  needed here beyond the directive registration above.

- New generated file `src/generated/auth/auth-directive.ts` — a fixed template
  constant (like `defaultWebSocketAdapter` is for the WS adapter), generated only if
  `@glAuth` appears anywhere in the schema:

  ```ts
  import { getDirective, MapperKind, mapSchema } from '@graphql-tools/utils';
  import { defaultFieldResolver, GraphQLError, GraphQLSchema } from 'graphql';
  import { GraphLinkContext } from '../context.js';

  export function applyAuthDirective(schema: GraphQLSchema): GraphQLSchema {
    return mapSchema(schema, {
      [MapperKind.OBJECT_FIELD]: (fieldConfig) => {
        const directive = getDirective(schema, fieldConfig, 'glAuth')?.[0];
        if (!directive) return fieldConfig;

        const roles: string[] = directive.roles ?? [];
        const { resolve = defaultFieldResolver } = fieldConfig;

        fieldConfig.resolve = async (source, args, context: GraphLinkContext, info) => {
          if (!context.auth) {
            throw new GraphQLError('Not authenticated', { extensions: { code: 'UNAUTHENTICATED' } });
          }
          if (roles.length > 0 && !roles.some((r) => context.auth!.roles.includes(r))) {
            throw new GraphQLError('Forbidden', { extensions: { code: 'FORBIDDEN' } });
          }
          return resolve(source, args, context, info);
        };
        return fieldConfig;
      },
    });
  }
  ```

- `index.ts` (`createServer`) — apply the transformer right after
  `makeExecutableSchema`, conditionally emitted:

  ```ts
  let schema = makeExecutableSchema({ typeDefs, resolvers: buildResolvers(...) });
  schema = applyAuthDirective(schema);
  ```

- `context.ts` — when `@glAuth` is used anywhere, generate:

  ```ts
  export interface AuthContext {
    roles: string[];
    [key: string]: unknown;
  }

  export interface GraphLinkContext {
    auth?: AuthContext;
  }
  ```

  (extending the existing declaration-merging pattern already used by
  `my-context.ts`/`GraphLinkContext`).

- New generated service interface `src/generated/services/auth-service.ts`:

  ```ts
  import { Request, Response } from 'express';
  import { AuthContext } from '../context.js';

  export interface AuthService {
    authenticateHttp(req: Request, res: Response): Promise<AuthContext | undefined>;
    authenticateWs(connectionParams: Record<string, unknown> | undefined): Promise<AuthContext | undefined>;
  }
  ```

  Handwritten implementation (`src/impl/auth-service.ts`) verifies JWTs/sessions and
  returns `{ roles: [...] }` (or `undefined` for anonymous). `createServer()`'s
  `GraphLinkServices` gains an optional `authService?: AuthService`; if provided:
  - `contextFactory` default becomes `async (req, res) => ({ auth: await authService.authenticateHttp(req, res) })`
    (still overridable via the existing `contextFactory` option).
  - `useServer({ schema, context: async (ctx) => ({ auth: await authService.authenticateWs(ctx.connectionParams) }) }, wsServer)`.

### 4. Open questions

- **Optional `roles` arg syntax**: confirm the parser/lexer support a directive
  argument with no value supplied at all (`@glAuth` with zero args) vs. requiring
  `@glAuth(roles: [])`. If bare `@glAuth` isn't supported cleanly, fall back to
  requiring `roles: []` for "any authenticated user".
- **Client-side schema**: decide whether `@glAuth` should be stripped entirely from
  client-generated SDL/queries (recommended) or left in (harmless but noisy).
- **Batch mappings**: confirm `getDirective`/`mapSchema` correctly targets the
  resolver installed for `Author.articles` (the DataLoader-backed field) — should work
  since `mapSchema` operates on the final schema's field map regardless of how the
  resolver was constructed, but worth a dedicated test.
- **`@graphql-tools/utils`**: already a transitive dependency via
  `@graphql-tools/schema` (`makeExecutableSchema`); confirm `getDirective`/`mapSchema`
  are exported from the version pinned in the generated `package.json`.

## Test plan (in `server_integration_tests/`)

Extend the existing Author/Article schema:

- Add `@glAuth(roles: ["ADMIN"])` to `listAuthors` (or `deleteArticle`).
- Add `@glAuth` (any authenticated user) to `getAuthor`.
- Leave `getArticle`/`listArticles`/mutations/subscriptions unauthenticated as a
  control group.
- Implement `AuthServiceImpl` in `typescript_server/src/impl/`: a trivial
  "Bearer admin-token" → `{ roles: ['ADMIN'] }`, "Bearer user-token" → `{ roles: [] }`,
  no header → `undefined`.
- Dart client tests (`dart_client/test/auth_test.dart`):
  - No auth header → `listAuthors` returns a `GraphLinkError` with
    `extensions.code == 'UNAUTHENTICATED'`.
  - `Bearer user-token` → `getAuthor` succeeds, `listAuthors` returns `FORBIDDEN`.
  - `Bearer admin-token` → both succeed.
  - WS subscription with `connectionParams: { authorization: 'Bearer admin-token' }`
    if any subscription gets `@glAuth` in the test schema.

## Task list

- [ ] Register `@glAuth` directive (parser + built-in directive definitions)
- [ ] Validation extension (`gl_grammar_auth_extension.dart`): scopes, `roles` type,
      server-only gating
- [ ] Decide & implement client-SDL stripping for `@glAuth`
- [ ] Generate `auth/auth-directive.ts` (`applyAuthDirective`) when `@glAuth` is used
- [ ] Generate `AuthContext`/`GraphLinkContext.auth` extension in `context.ts`
- [ ] Generate `services/auth-service.ts` interface + wire into `createServer()`
      (`contextFactory` default, `useServer` context/`onConnect`)
- [ ] Extend `server_integration_tests` schema + handwritten `AuthServiceImpl` +
      Dart `auth_test.dart`
- [ ] Run full suite (`make ci` in `server_integration_tests/`)
