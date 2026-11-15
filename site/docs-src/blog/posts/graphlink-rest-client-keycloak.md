---
date: 2026-11-15
slug: graphlink-rest-client-keycloak
categories:
  - REST
description: "How a Spring Boot backend replaced a hand-written Keycloak RestClient with a GraphLink-generated client, and what did and didn't improve."
id: R-62
demo_repo_path: ""
docs_page: "rest-client.md"
---

# Moving our Keycloak REST calls to a GraphLink-generated client

**TL;DR**

- A 95-line GraphQL schema with REST directives replaced the hand-built paths, headers and forms of our Keycloak client.
- The same schema can generate the client in other languages. We only ran Java.
- Our code size barely changed, because server mode already generated our response types.

<!-- more -->

## The problem with a REST client

Calling a REST API from your own code means building three things by hand: the requests (URLs, headers, form and JSON bodies), the response classes, and the decoding that connects the two. It also means doing that again in every language that needs the API.

The backend behind [optidialysis.com](https://optidialysis.com) calls Keycloak's admin and token endpoints. The old Spring `RestClient` code kept the whole contract in string literals spread through one service: path templates, `Authorization` headers and form assembly. A typo in a path only showed up at runtime.

## What we did

We described the endpoints we use in a GraphQL schema with GraphLink's REST directives:

```graphql
extend type Query @glRestPrefix(path: "/admin/realms/{realm}") {
  kcUserById(realm: String!, id: String!): KcUser @glRest(path: "/users/{id}")
}

extend type Mutation @glRestPrefix(path: "/admin/realms/{realm}") {
  kcResetPassword(realm: String!, id: String!, credentials: KcCredentialsInput! @glRestBody): Void
    @glRest(path: "/users/{id}/reset-password", method: PUT)
}
```

GraphLink generated the client, the request and response types and the JSON decoding. The call site became:

```java
adminApi.mutations.kcResetPassword(realm, userId, credentials);
```

The whole schema is 95 lines. We gitignore the generated client and generate it in the build, so pull requests contain only the schema and the service.

## What improved

- **One reviewable file for the contract.** Adding an endpoint is a few lines in a pull request. The path, header and form plumbing is gone from the service.
- **Contract drift is a compile error.** Rename a field in the schema, regenerate, and every caller that no longer fits fails to compile.
- **No response classes to write.** If your response types are hand-written, this is the main saving. When Keycloak adds a field you need, you add one line to the schema and regenerate.
- **Easy to test on the wire.** The transport is a small adapter (we used the JDK's `HttpClient`, so no new HTTP library). We tested against a local fake Keycloak and asserted real paths, headers and bodies.
- **Other languages.** GraphLink can generate the same client for Dart, Kotlin, TypeScript, Python and Go. We haven't run those targets.

## What didn't change

Our GraphLink server mode already generated the Keycloak response types, so we weren't removing hand-written DTOs. `KeycloakService` went from 359 to 362 lines. We also added a client-side set of types and a small mapping layer between them and the server-side ones.

For a project like ours, the migration is mostly about moving HTTP plumbing into a schema. The bigger win is for a project that hand-writes its response classes, or needs the same API from more than one language.

## Rough edges

- **`DELETE` with a body isn't supported by the generator.** Keycloak's "remove realm roles" needs one, so that single request is hand-built and sent through the same generated adapter.
- **Some wire names can't be expressed in GraphQL.** Keycloak's snake_case names such as `access_token` are converted to `accessToken` automatically, but a name like `not-before-policy` can't be a GraphQL field name, so we left it out.
- **A generator is now part of your build.** Pin its version and watch the first CI run.

## How we verified it

Login, token refresh, a wrong-password rejection and an admin password reset ran against a real Keycloak through the running app. User creation, update, deletion and role assignment are covered by the fake-server tests, but we haven't run them live yet.

## Should you do this?

Absolutely. Generate more code and maintain less of it.

Paths, headers, form bodies, response classes and JSON decoding are mechanical. An AI agent can write them for you, but you would still review them, keep them in sync with the API and fix them when they drift. With a schema, the contract is a short file you review, and the rest is generated on every build, so there is no hand-written client left to maintain, whether a person or an agent wrote it.

## Try it

- REST operations: <https://graphlink.dev/rest-client.html>
- Install: <https://graphlink.dev/getting-started.html>
- YouTube: <https://www.youtube.com/@Graphlinkdev>
- Reddit: <https://www.reddit.com/r/graphlinkdotdev/>
- X: <https://x.com/graphlinkdev>
