---
title: Using GraphLink with AI Agents
description: Ready-to-copy agent instruction files for Claude Code, Gemini CLI, and other AI coding assistants in GraphLink projects.
---

# Using GraphLink with AI Agents

AI coding assistants work best when they understand how your project is structured.
Without instructions, an agent seeing a `generated/` directory full of Dart or Java files
will waste time reading, editing, or recreating code that GraphLink owns.

This page provides ready-to-use instruction files for common setups.
**Copy the one that matches your project and paste it into your agent's instruction file.**

| Agent | Instruction file |
|---|---|
| Claude Code | `CLAUDE.md` at project root |
| Gemini CLI | `GEMINI.md` or `.gemini/instructions.md` |
| GitHub Copilot | `.github/copilot-instructions.md` |
| Cursor | `.cursor/rules` |
| Any agent | `AGENTS.md` at project root (read by most tools) |

---

## Dart / Flutter project

=== "AGENTS.md / CLAUDE.md"

    ```markdown
    ## Code generation — GraphLink

    This project uses [GraphLink](https://graphlink.dev) (`glink`) to generate
    Dart/Flutter code from a GraphQL schema.

    - **Schema**: `lib/**/*.graphql` (or wherever your .graphql files are)
    - **Config**: `glink.json` (or `glink.yaml`) at the project root
    - **Generated files**: `lib/generated/` — DO NOT edit these manually

    To regenerate after any schema change:
    ```bash
    glink -c glink.json
    # or with watch mode:
    glink -c glink.json -w
    ```

    ### Rules
    - To add a field, type, query, or mutation: edit the `.graphql` schema file, then run `glink`.
    - Never edit files inside `lib/generated/` — they will be overwritten.
    - The generated `GraphLinkClient` is the entry point for all queries, mutations, and subscriptions.
    - Input classes live in `lib/generated/inputs/`. Type classes live in `lib/generated/types/`.
    - Enums are in `lib/generated/enums/` and are already serialized — use them directly.

    ### Caching
    Cache behaviour is declared in the schema via `@glCache` and `@glCacheInvalidate` directives.
    Do not implement caching in application code — add or modify the directive in the schema instead.
    ```

---

## Java client project

=== "AGENTS.md / CLAUDE.md"

    ```markdown
    ## Code generation — GraphLink

    This project uses [GraphLink](https://graphlink.dev) (`glink`) to generate
    Java client code from a GraphQL schema.

    - **Schema**: `schema/*.graphql` (or wherever your .graphql files are)
    - **Config**: `glink.json` at the project root
    - **Generated files**: `src/main/java/com/example/generated/` — DO NOT edit these manually

    To regenerate after any schema change:
    ```bash
    glink -c glink.json
    ```

    ### Rules
    - To add a field, type, query, or mutation: edit the `.graphql` schema file, then run `glink`.
    - Never edit files inside the `generated/` package.
    - `GraphLinkClient` is the entry point. Queries are on `client.queries`, mutations on `client.mutations`.
    - Return types are fully resolved — no `TypeReference`, no casting needed at the call site.
    - Input classes use a builder pattern: `AddVehicleInput.builder().brand("Toyota").build()`.
    ```

---

## TypeScript project

=== "AGENTS.md / CLAUDE.md"

    ```markdown
    ## Code generation — GraphLink

    This project uses [GraphLink](https://graphlink.dev) (`glink`) to generate
    TypeScript client code from a GraphQL schema.

    - **Schema**: `schema/*.graphql` (or wherever your .graphql files are)
    - **Config**: `glink.json` at the project root
    - **Generated files**: `src/generated/` — DO NOT edit these manually

    To regenerate after any schema change:
    ```bash
    glink -c glink.json
    ```

    ### Rules
    - To add a field, type, query, or mutation: edit the `.graphql` schema file, then run `glink`.
    - Never edit files inside `src/generated/`.
    - Import `GraphLinkClient` from `src/generated/client/graph-link-client`.
    - All queries and mutations are typed methods — no manual type assertions needed.
    - Subscriptions are available as callback-based methods on `client.subscriptions`.
    ```

---

## Spring Boot server project

=== "AGENTS.md / CLAUDE.md"

    ```markdown
    ## Code generation — GraphLink

    This project uses [GraphLink](https://graphlink.dev) (`glink`) to generate
    Spring Boot server code from a GraphQL schema.

    - **Schema**: `src/main/resources/graphql/*.graphqls`
    - **Config**: `glink.json` at the project root
    - **Generated files**: `src/main/java/com/example/generated/` — DO NOT edit these manually

    To regenerate after any schema change:
    ```bash
    glink -c glink.json
    ```

    ### Rules
    - To add a field, type, query, or mutation: edit the `.graphqls` schema file, then run `glink`.
    - Never edit files inside the `generated/` package — controllers, inputs, and types are all generated.
    - Implement the generated service interfaces (e.g. `VehicleService`) — do not modify the controllers.
    - Subscription resolvers must return `reactor.core.publisher.Flux<T>`.
    - Generated repositories are stubs — fill in the persistence logic, but do not change the interface signature.
    ```

---

## Full-stack project (Flutter + Spring Boot)

=== "AGENTS.md / CLAUDE.md"

    ```markdown
    ## Code generation — GraphLink

    This project uses [GraphLink](https://graphlink.dev) (`glink`) to generate code
    from a single GraphQL schema for both the Flutter client and the Spring Boot backend.

    ### Schema
    One schema file drives both ends: `schema/schema.graphql`

    ### Client (Flutter)
    - **Config**: `client/glink.json`
    - **Generated files**: `client/lib/generated/` — DO NOT edit

    ### Server (Spring Boot)
    - **Config**: `server/glink.json`
    - **Generated files**: `server/src/main/java/com/example/generated/` — DO NOT edit

    To regenerate both after a schema change:
    ```bash
    glink -c client/glink.json
    glink -c server/glink.json
    ```

    ### Rules
    - All data model changes go in `schema/schema.graphql` first — then regenerate.
    - On the server, implement the generated service interfaces. Never edit generated controllers.
    - On the client, use `GraphLinkClient` — never write raw HTTP or WebSocket calls for GraphQL.
    - Cache behaviour is declared in the schema via `@glCache` / `@glCacheInvalidate`. Do not implement
      caching in application code.
    ```

---

!!! tip "Watch mode during development"
    Run `glink -c glink.json -w` in a terminal while your AI agent edits the schema.
    Every schema save triggers instant regeneration — the agent's next read of the
    generated files will already reflect the change.

!!! info "The generated code is yours"
    GraphLink has zero runtime dependency. If you stop using it, every generated file
    continues to compile and work. Commit the generated files to version control —
    they are source of truth for what your schema produces.
