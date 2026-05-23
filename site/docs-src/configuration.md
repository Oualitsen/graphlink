---
title: Configuration Reference — GraphLink Docs
description: Complete reference for all GraphLink glink.json / glink.yaml options — schemaPaths, typeMappings, outputDir, clientConfig (Dart, Java, TypeScript), serverConfig (Spring Boot), and CLI flags.
---

# Configuration Reference

Full reference for every option in `glink.json` / `glink.yaml`.

## Top-level options

=== "JSON"

    ```json title="glink.json — top-level structure"
    {
      "schemaPaths": ["schema/*.graphql"],
      "mode": "client",
      "typeMappings": { "ID": "String", "Float": "double" },
      "outputDir": "lib/generated",
      "identityFields": ["id"],
      "disableCache": false,
      "clientConfig": { },
      "serverConfig": { }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — top-level structure"
    schemaPaths:
      - schema/*.graphql
    mode: client
    typeMappings:
      ID: String
      Float: double
    outputDir: lib/generated
    identityFields:
      - id
    disableCache: false
    clientConfig: # see sections below
    serverConfig: # see sections below
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `schemaPaths` | `string[]` | — | **Required.** Glob patterns for schema files. Multiple patterns are supported — all matched files are merged into one schema. |
| `mode` | `"client"` \| `"server"` | `"server"` | Controls which generator runs. `"client"` generates a typed client (Dart, Java, or TypeScript). `"server"` generates Spring Boot scaffolding. |
| `typeMappings` | `Record<string, string>` | `{}` | Maps GraphQL scalar names to target-language types. Entries here override the defaults. Add entries for custom scalars. |
| `outputDir` | `string` | `"src/main/java"` | Directory where generated files are written. Existing files are overwritten on every run. |
| `identityFields` | `string[]` | `[]` | Field names treated as identity fields when generating `==` / `hashCode` methods (Dart and Java). Fields listed here are always included in equality regardless of `@glEqualsHashcode`. |
| `disableCache` | `boolean` | `false` | When `true`, strips all `@glCache` and `@glCacheInvalidate` directives from the generated client — useful for debugging or environments where caching is handled externally. |

---

## `clientConfig.dart`

Used when `mode` is `"client"` and you want Dart/Flutter output.

=== "JSON"

    ```json title="glink.json — clientConfig.dart"
    {
      "clientConfig": {
        "dart": {
          "packageName": "my_app",
          "httpAdapter": "dio",
          "generateAdapters": true,
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "autoGenerateQueriesDefaultAlias": null,
          "defaultAlias": null,
          "operationNameAsParameter": false,
          "nullableFieldsRequired": false,
          "immutableInputFields": true,
          "immutableTypeFields": true,
          "generateUiTypes": false,
          "generateUiInputs": false,
          "appLocalizationsImport": null,
          "captureErrors": false
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — clientConfig.dart"
    clientConfig:
      dart:
        packageName: my_app
        httpAdapter: dio
        generateAdapters: true
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        autoGenerateQueriesDefaultAlias: null
        defaultAlias: null
        operationNameAsParameter: false
        nullableFieldsRequired: false
        immutableInputFields: true
        immutableTypeFields: true
        generateUiTypes: false
        generateUiInputs: false
        appLocalizationsImport: null
        captureErrors: false
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** The Dart package name used for import paths in generated files (e.g. `"my_app"` produces `import 'package:my_app/...'`). |
| `httpAdapter` | `"http"` \| `"dio"` \| `"none"` | `"http"` | Which HTTP adapter file to generate. `"http"` uses `package:http`. `"dio"` uses Dio (supports interceptors, custom `BaseOptions`). `"none"` skips adapter generation — supply your own `Future<String> Function(String)`. |
| `generateAdapters` | `boolean` | `true` | When `false`, skips generating the HTTP and WebSocket adapter files. Use this if you maintain your own adapter implementations and don't want them overwritten. |
| `generateAllFieldsFragments` | `boolean` | `false` | Generates a `_all_fields_TypeName` named fragment for every type in the schema. Required for `autoGenerateQueries` to work. |
| `autoGenerateQueries` | `boolean` | `false` | Automatically builds query strings for every operation using `_all_fields` fragments. When `true`, you do not need to write any query strings by hand. |
| `autoGenerateQueriesDefaultAlias` | `string` \| `null` | `null` | Default alias prefix to use for auto-generated query fields when `autoGenerateQueries` is `true`. Useful when multiple operations select the same root field. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally when no field-level alias is declared. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the generated HTTP adapter function signature includes a second `operationName` parameter: `Future<String> Function(String payload, String operationName)`. The operation name is appended to the URL as a query parameter, which is useful for server-side logging and APM tracing. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, nullable fields in generated constructors are emitted as `required this.fieldName` instead of optional `this.fieldName`. Use this to enforce that all fields are always explicitly passed at construction sites. |
| `immutableInputFields` | `boolean` | `true` | Input class fields are `final`. Recommended. |
| `immutableTypeFields` | `boolean` | `true` | Response type class fields are `final`. Recommended for client-side code. |
| `generateUiTypes` | `boolean` | `false` | Generates Flutter widget classes for every `type` in the schema — useful for rapid prototyping. Requires Flutter. |
| `generateUiInputs` | `boolean` | `false` | Generates Flutter form widgets for every `input` type — renders a form with one field per schema field. |
| `appLocalizationsImport` | `string` \| `null` | `null` | Import path for an `AppLocalizations` class injected into generated Flutter UI widgets. Only relevant when `generateUiTypes` or `generateUiInputs` is `true`. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` behaviour to every query and mutation. Each method returns a `{OperationName}FullResponse` holding nullable `data` and nullable `errors` instead of throwing on GraphQL errors. Equivalent to annotating every query and mutation field with `@glCaptureErrors` in the schema. |

---

## `clientConfig.java`

Used when `mode` is `"client"` and you want a Java client.

=== "JSON"

    ```json title="glink.json — clientConfig.java"
    {
      "clientConfig": {
        "java": {
          "packageName": "com.example.generated",
          "wsAdapter": "java11",
          "jsonCodec": "jackson",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "autoGenerateQueriesDefaultAlias": null,
          "defaultAlias": null,
          "operationNameAsParameter": false,
          "nullableFieldsRequired": false,
          "immutableInputFields": true,
          "immutableTypeFields": true,
          "inputAsRecord": false,
          "typeAsRecord": false,
          "captureErrors": false
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — clientConfig.java"
    clientConfig:
      java:
        packageName: com.example.generated
        wsAdapter: java11
        jsonCodec: jackson
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        autoGenerateQueriesDefaultAlias: null
        defaultAlias: null
        operationNameAsParameter: false
        nullableFieldsRequired: false
        immutableInputFields: true
        immutableTypeFields: true
        inputAsRecord: false
        typeAsRecord: false
        captureErrors: false
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** Java package name for generated files (e.g. `"com.example.generated"`). |
| `wsAdapter` | `"java11"` \| `"okhttp"` \| `"none"` | `"java11"` | Which WebSocket adapter to generate. `"java11"` uses `java.net.http.WebSocket` (zero extra dependencies). `"okhttp"` uses OkHttp's WebSocket client. `"none"` skips WebSocket adapter generation. |
| `jsonCodec` | `"jackson"` \| `"gson"` \| `"none"` | `"jackson"` | Which JSON codec helper to generate. `"jackson"` generates `JacksonGraphLinkJsonCodec`. `"gson"` generates `GsonGraphLinkJsonCodec`. `"none"` skips codec generation — supply your own lambdas. |
| `generateAllFieldsFragments` | `boolean` | `false` | Generates `_all_fields_TypeName` fragments for every type. Required for `autoGenerateQueries`. |
| `autoGenerateQueries` | `boolean` | `false` | Automatically builds query strings for every operation. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the adapter interface includes an `operationName` parameter and the generated client appends it to the request URL as a query parameter. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, the generated input constructors do not accept `null` for nullable fields — `Objects.requireNonNull` is emitted for all fields. |
| `immutableInputFields` | `boolean` | `true` | Input class fields are `private final`. Inputs use builder pattern. |
| `immutableTypeFields` | `boolean` | `true` | Response type fields are `private final` with only getters. Recommended for client-side. |
| `inputAsRecord` | `boolean` | `false` | Generates input types as Java records instead of classes with builders. Records use component accessor syntax (`field()`) instead of getters (`getField()`). Requires Java 16+. |
| `typeAsRecord` | `boolean` | `false` | Generates response types as Java records. Affects how `fromJson` and mapping methods access fields. Requires Java 16+. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` behaviour to every query and mutation. Each method returns a `{OperationName}FullResponse` holding nullable `data` and nullable `errors` instead of throwing on GraphQL errors. Equivalent to annotating every query and mutation field with `@glCaptureErrors` in the schema. |

---

## `clientConfig.typescript`

Used when `mode` is `"client"` and you want TypeScript output.

=== "JSON"

    ```json title="glink.json — clientConfig.typescript"
    {
      "clientConfig": {
        "typescript": {
          "httpAdapter": "fetch",
          "generateDefaultWsAdapter": true,
          "observables": false,
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "defaultAlias": null,
          "operationNameAsParameter": false,
          "optionalNullableInputFields": true,
          "immutableTypeFields": true,
          "captureErrors": false
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — clientConfig.typescript"
    clientConfig:
      typescript:
        httpAdapter: fetch
        generateDefaultWsAdapter: true
        observables: false
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        defaultAlias: null
        operationNameAsParameter: false
        optionalNullableInputFields: true
        immutableTypeFields: true
        captureErrors: false
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `httpAdapter` | `"fetch"` \| `"axios"` \| `"none"` | `"fetch"` | Which HTTP adapter to generate. `"fetch"` uses the native Fetch API (works in Angular, React, Vue, Svelte, Node 18+). `"axios"` uses Axios. `"none"` skips adapter generation. |
| `generateDefaultWsAdapter` | `boolean` | `true` | When `true`, generates `DefaultGraphLinkWebSocketAdapter` implementing the graphql-ws protocol with exponential-backoff reconnect. Set to `false` if you have no subscriptions or supply your own adapter. |
| `observables` | `boolean` | `false` | When `true`, query and mutation methods return `Observable<T>` (RxJS) instead of `Promise<T>`. Subscription methods also return `Observable<T>`. Recommended for Angular projects. |
| `generateAllFieldsFragments` | `boolean` | `false` | Generates `_all_fields_TypeName` fragments for every type. Required for `autoGenerateQueries`. |
| `autoGenerateQueries` | `boolean` | `false` | Automatically builds query strings for every operation using `_all_fields` fragments. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the adapter function signature includes an `operationName` parameter and the client appends it to the request URL. |
| `optionalNullableInputFields` | `boolean` | `true` | When `true`, nullable fields in generated input interfaces use `field?: T \| null` (TypeScript optional property). When `false`, they use `field: T \| null` (required but nullable). |
| `immutableTypeFields` | `boolean` | `true` | When `true`, generated type interfaces use `readonly` on all fields. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` behaviour to every query and mutation. Each method returns a `{OperationName}FullResponse` holding optional `data` and optional `errors` instead of throwing on GraphQL errors. Equivalent to annotating every query and mutation field with `@glCaptureErrors` in the schema. |

---

## `serverConfig.spring`

Used when `mode` is `"server"`.

=== "JSON"

    ```json title="glink.json — serverConfig.spring"
    {
      "serverConfig": {
        "spring": {
          "basePackage": "com.example.generated",
          "generateControllers": true,
          "generateInputs": true,
          "generateTypes": true,
          "generateRepositories": false,
          "immutableInputFields": true,
          "immutableTypeFields": false,
          "inputAsRecord": false,
          "typeAsRecord": false,
          "reactive": false,
          "useSpringSecurity": false,
          "injectDataFetching": false,
          "generateSchema": false,
          "schemaTargetPath": null
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — serverConfig.spring"
    serverConfig:
      spring:
        basePackage: com.example.generated
        generateControllers: true
        generateInputs: true
        generateTypes: true
        generateRepositories: false
        immutableInputFields: true
        immutableTypeFields: false
        inputAsRecord: false
        typeAsRecord: false
        reactive: false
        useSpringSecurity: false
        injectDataFetching: false
        generateSchema: false
        schemaTargetPath: null
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `basePackage` | `string` | — | **Required.** Java package name for all generated classes (e.g. `"com.example.generated"`). |
| `generateControllers` | `boolean` | `true` | Generates `@Controller` classes with `@QueryMapping`, `@MutationMapping`, `@SubscriptionMapping`, and `@Argument` on parameters. |
| `generateInputs` | `boolean` | `true` | Generates input data classes from `input` type definitions. |
| `generateTypes` | `boolean` | `true` | Generates type data classes from `type` definitions. |
| `generateRepositories` | `boolean` | `false` | Generates JPA `Repository` interfaces for types annotated with `@glRepository`. |
| `immutableInputFields` | `boolean` | `true` | Input class fields are `private final`. Recommended. |
| `immutableTypeFields` | `boolean` | `false` | Type class fields are `private final`. Set to `false` for Spring Boot — Spring's runtime sets fields via setters or reflection. |
| `inputAsRecord` | `boolean` | `false` | Generates input types as Java records. Requires Java 16+. |
| `typeAsRecord` | `boolean` | `false` | Generates type classes as Java records. Requires Java 16+. |
| `reactive` | `boolean` | `false` | When `true`, generates Spring WebFlux-style controllers. Queries and mutations return `Mono<T>`. File upload fields use `FilePart`. |
| `useSpringSecurity` | `boolean` | `false` | MVC mode only. Captures the `SecurityContext` before entering `CompletableFuture` lambdas and restores it on the worker thread. Requires `spring-security` on the classpath. Has no effect in reactive mode. |
| `injectDataFetching` | `boolean` | `false` | When `true`, generates data-fetching injection code in controllers for field-level resolution. |
| `generateSchema` | `boolean` | `false` | When `true`, writes a copy of the processed schema to disk alongside the generated Java. Requires `schemaTargetPath`. |
| `schemaTargetPath` | `string` \| `null` | `null` | Path where the schema file is written when `generateSchema` is `true`. Must end in `.graphql` or `.graphqls`. Example: `"src/main/resources/schema.graphqls"`. |

---

## Config file format

GraphLink accepts **JSON** (`.json`), **YAML** (`.yaml`), and **YML** (`.yml`) config files. The structure and keys are identical across all three formats.

```yaml title="glink.yaml — equivalent to the JSON example above"
schemaPaths:
  - schema/*.graphql
mode: client
typeMappings:
  ID: String
  Float: double
outputDir: lib/generated
clientConfig:
  dart:
    packageName: my_app
    generateAllFieldsFragments: true
    autoGenerateQueries: true
```

---

## CLI flags

```bash
glink                   # auto-discover config (see below)
glink -c glink.json     # explicit config path
glink -w                # watch mode — regenerate on schema change
glink --version         # print version and exit
glink --help            # print usage
```

| Flag | Description |
|---|---|
| `-c <path>` | Path to the config file. Accepts `.json`, `.yaml`, or `.yml`. If omitted, `glink` searches for `glink.json`, `glink.yaml`, or `glink.yml` starting from the current directory and walking up to the filesystem root. |
| `-w` | Watch mode. GraphLink monitors the files matched by `schemaPaths` and regenerates on every save. |
| `--version` | Prints the GraphLink version and exits. |
| `--help` | Prints usage information and exits. |
