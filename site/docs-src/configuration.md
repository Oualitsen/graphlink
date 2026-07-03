---
title: Configuration Reference — GraphLink Docs
description: Complete reference for all GraphLink glink.json / glink.yaml options — schemaPaths, typeMappings, unknownScalarType, outputDir, clientConfig (Dart, Java reactive asyncStyle, TypeScript, Kotlin), serverConfig (Spring Boot, Kotlin Spring), identifier normalization, and CLI flags.
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
      "unknownScalarType": "String",
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
    unknownScalarType: String
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
| `unknownScalarType` | `string` \| `null` | `null` | Fallback target-language type for any custom scalar **not** covered by `typeMappings` or an `@glExternal` directive. Without it, an unmapped `scalar UserId` is emitted verbatim as `UserId`; set e.g. `"String"` (Dart), `"string"` (TypeScript), or `"Object"` (Java) to map all such scalars uniformly. Since one config targets a single language, write the value in that language's type syntax. `typeMappings` and `@glExternal` always take precedence. |
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
          "httpAdapter": "http",
          "generateAdapters": true,
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "autoGenerateQueriesDefaultAlias": null,
          "autoGenerateQueriesFor": null,
          "autoGenerateQueriesArgumentLimit": 200,
          "maxFragmentBodySize": 8192,
          "defaultAlias": null,
          "operationNameAsParameter": false,
          "nullableFieldsRequired": false,
          "immutableInputFields": true,
          "immutableTypeFields": true,
          "captureErrors": false,
          "flutter": {
            "generateTypes": true,
            "generateInputs": false,
            "typesToSkip": [],
            "inputsToSkip": [],
            "defaultGap": 16,
            "booleanWidget": "switchWidget",
            "nullableBooleanWidget": "checkbox",
            "listWidget": "chips",
            "defaultLabelPosition": "floatingLabel",
            "defaultLabelWidth": 120,
            "defaultFormLayout": "column",
            "defaultRequiredIndicator": "asterisk",
            "defaultDebounceDuration": 300,
            "defaultStepperOrientation": "vertical",
            "defaultTypeLayout": "labeledRow",
            "defaultGroupLayout": "labeledRow",
            "defaultDatePattern": "yyyy-MM-dd",
            "defaultDateFirstYear": 1900,
            "defaultDateLastYear": 2100,
            "defaultDateMode": "dialog"
          }
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — clientConfig.dart"
    clientConfig:
      dart:
        packageName: my_app
        httpAdapter: http
        generateAdapters: true
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        autoGenerateQueriesDefaultAlias: null
        autoGenerateQueriesFor: null
        autoGenerateQueriesArgumentLimit: 200
        maxFragmentBodySize: 8192
        defaultAlias: null
        operationNameAsParameter: false
        nullableFieldsRequired: false
        immutableInputFields: true
        immutableTypeFields: true
        captureErrors: false
        flutter:
          generateTypes: true
          generateInputs: false
          typesToSkip: []
          inputsToSkip: []
          defaultGap: 16
          booleanWidget: switchWidget
          nullableBooleanWidget: checkbox
          listWidget: chips
          defaultLabelPosition: floatingLabel
          defaultLabelWidth: 120
          defaultFormLayout: column
          defaultRequiredIndicator: asterisk
          defaultDebounceDuration: 300
          defaultStepperOrientation: vertical
          defaultTypeLayout: labeledRow
          defaultGroupLayout: labeledRow
          defaultDatePattern: "yyyy-MM-dd"
          defaultDateFirstYear: 1900
          defaultDateLastYear: 2100
          defaultDateMode: dialog
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** The Dart package name used for import paths in generated files (e.g. `"my_app"` produces `import 'package:my_app/...'`). |
| `httpAdapter` | `"http"` \| `"dio"` \| `"none"` | `"http"` | Which HTTP adapter file to generate. `"http"` uses `package:http`. `"dio"` uses Dio (supports interceptors, custom `BaseOptions`). `"none"` skips adapter generation — supply your own `Future<String> Function(String)`. |
| `generateAdapters` | `boolean` | `true` | When `false`, skips generating the HTTP and WebSocket adapter files. Use this if you maintain your own adapter implementations and don't want them overwritten. |
| `generateAllFieldsFragments` | `boolean` | `true` | Generates a `_all_fields_TypeName` named fragment for every type in the schema. Required for `autoGenerateQueries` to work. |
| `autoGenerateQueries` | `boolean` | `true` | Automatically builds query strings for every operation using `_all_fields` fragments. When `true`, you do not need to write any query strings by hand. |
| `autoGenerateQueriesDefaultAlias` | `string` \| `null` | `null` | Default alias prefix to use for auto-generated query fields when `autoGenerateQueries` is `true`. Useful when multiple operations select the same root field. |
| `autoGenerateQueriesFor` | `object` \| `null` | `null` | Generates client methods only for the listed operations instead of every root field. Use instead of (or alongside) `autoGenerateQueries` when you only need a subset — e.g. on large schemas. Each key (`queries`, `mutations`, `subscriptions`) takes a list of root field names. Any listed name not found in the schema causes a build error. Requires `generateAllFieldsFragments: true`. See [Selective auto-generation](custom-queries.md#selective-auto-generation-autogeneratequeriesfor). |
| `autoGenerateQueriesArgumentLimit` | `integer` \| `null` | `200` | Maximum number of propagated (nested-field) arguments allowed in the synthesized `fieldArgs` object of an auto-generated operation. When the limit is exceeded, GraphLink skips the operation and prints a `⚠` warning. Hand-written operations are never affected. Raise the value for unusually large schemas, or write a custom query with a narrower field selection instead. See [Argument limit](custom-queries.md#auto-generated-query-argument-limit). |
| `maxFragmentBodySize` | `integer` \| `null` | `8192` | Maximum number of characters allowed in the serialized body of a generated `_all_fields` fragment. Fragments whose serialized body exceeds this limit are silently omitted, and any auto-generated queries that depend on them are also skipped. Set to `null` to disable the cap and always generate all fragments. Useful when `generateAllFieldsFragments: true` is used on a very large schema (e.g. Shopify's) where individual fragment bodies can reach 60 KB+, inflating both the compiled binary and every network request. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally when no field-level alias is declared. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the generated HTTP adapter function signature includes a second `operationName` parameter: `Future<String> Function(String payload, String operationName)`. The operation name is appended to the URL as a query parameter, which is useful for server-side logging and APM tracing. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, nullable fields in generated constructors are emitted as `required this.fieldName` instead of optional `this.fieldName`. Use this to enforce that all fields are always explicitly passed at construction sites. |
| `immutableInputFields` | `boolean` | `true` | Input class fields are `final`. Recommended. |
| `immutableTypeFields` | `boolean` | `true` | Response type class fields are `final`. Recommended for client-side code. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` behaviour to every query and mutation. Each method returns a `{OperationName}FullResponse` holding nullable `data` and nullable `errors` instead of throwing on GraphQL errors. Equivalent to annotating every query and mutation field with `@glCaptureErrors` in the schema. |
| `appLocalizationsImport` | `string` \| `null` | `null` | Import path for an `AppLocalizations` class injected into generated Flutter UI widgets. Only relevant when `flutter` is configured. |
| `flutter` | `object` | — | Enables Flutter widget generation and sets project-wide UI defaults. Omit the key entirely to disable Flutter generation. See [`clientConfig.dart.flutter`](#clientconfigdartflutter) for the full sub-key reference. |

---

## `clientConfig.dart.flutter`

Flutter widget generation is enabled by adding a `flutter:` block inside `clientConfig.dart`. Omitting the block entirely disables Flutter generation. All keys are optional — unset keys use the built-in default.

Keys split into two groups: **generation toggles** (what to generate) and **UI defaults** (what values are baked into generated widget constructors).

### Generation toggles

| Option | Type | Default | Description |
|---|---|---|---|
| `generateTypes` | `boolean` | `true` | Generate stateless display widgets for schema `type` definitions (e.g. `VehicleWidget`). |
| `generateInputs` | `boolean` | `false` | Generate stateful form widgets for schema `input` definitions (e.g. `AddVehicleInputForm`). |
| `typesToSkip` | `string[]` | `[]` | Type names excluded from display widget generation. |
| `inputsToSkip` | `string[]` | `[]` | Input names excluded from form widget generation. |

### Global widget style

| Option | Type | Default | Description |
|---|---|---|---|
| `defaultGap` | `number` | `16` | Default spacing (dp) between rows in every generated widget and form. |
| `booleanWidget` | `"switchWidget"` \| `"checkbox"` \| `"tristate"` | `"switchWidget"` | Default widget for non-nullable `Boolean` fields. `switchWidget` → `Switch`/`SwitchListTile`. `checkbox` → `Checkbox`. `tristate` → Yes/No/— dropdown. |
| `nullableBooleanWidget` | `"checkbox"` \| `"tristate"` | `"checkbox"` | Default widget for nullable `Boolean?` fields. `switchWidget` is excluded — `Switch` cannot represent `null`. |
| `listWidget` | `"chips"` \| `"checkboxes"` | `"chips"` | Default widget for enum-list and scalar-list fields. |

### Input form defaults

These values are emitted as the default constructor parameter values in every generated form widget. They can be overridden per widget call site at runtime.

| Option | Type | Default | Description |
|---|---|---|---|
| `defaultLabelPosition` | `"floatingLabel"` \| `"beside"` \| `"above"` | `"floatingLabel"` | Default label position across all generated forms. |
| `defaultLabelWidth` | `number` | `120` | Default width (dp) of the label column in `beside` mode. |
| `defaultFormLayout` | `"column"` \| `"twoColumn"` | `"column"` | Default layout for all generated forms. |
| `defaultRequiredIndicator` | `"asterisk"` \| `"none"` \| `"requiredText"` \| `"optionalText"` | `"asterisk"` | Default required-field indicator style. |
| `defaultDebounceDuration` | `number` | `300` | Milliseconds to wait after the last field change before firing `onChange`. |
| `defaultStepperOrientation` | `"vertical"` \| `"horizontal"` | `"vertical"` | Default Flutter `StepperType` for forms that use the stepper layout (inputs with nested input fields). |

### Type display widget defaults

| Option | Type | Default | Description |
|---|---|---|---|
| `defaultTypeLayout` | `"labeledRow"` \| `"listTile"` \| `"listTileReversed"` \| `"expandable"` | `"labeledRow"` | Default layout for all generated display widgets. |
| `defaultGroupLayout` | `"labeledRow"` \| `"listTile"` \| `"listTileReversed"` | `"labeledRow"` | Default layout of the scalar accordion group inside the `expandable` layout. |

### Date picker defaults

These values are baked into the generated `DateInputConfig` class defaults and into every generated date-picker helper. Per-field `DateInputConfig` values always take precedence.

| Option | Type | Default | Description |
|---|---|---|---|
| `defaultDatePattern` | `string` | `"yyyy-MM-dd"` | Default `pattern` in the generated `DateInputConfig` class. Use `"dd/MM/yyyy"`, `"MM/dd/yyyy"`, etc. to match your locale. |
| `defaultDateFirstYear` | `number` | `1900` | Fallback `firstDate` year used by all generated date pickers when no `firstDate` is provided in `DateInputConfig`. |
| `defaultDateLastYear` | `number` | `2100` | Fallback `lastDate` year used by all generated date pickers when no `lastDate` is provided in `DateInputConfig`. |
| `defaultDateMode` | `"dialog"` \| `"inline"` | `"dialog"` | Default `DateInputMode` in the generated `DateInputConfig` class. |

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
          "autoGenerateQueriesFor": null,
          "autoGenerateQueriesArgumentLimit": 200,
          "maxFragmentBodySize": 8192,
          "defaultAlias": null,
          "operationNameAsParameter": false,
          "nullableFieldsRequired": false,
          "immutableInputFields": true,
          "immutableTypeFields": true,
          "inputAsRecord": false,
          "typeAsRecord": false,
          "jspecify": false,
          "asyncStyle": "blocking",
          "reactiveHttpClient": "jdk",
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
        autoGenerateQueriesFor: null
        autoGenerateQueriesArgumentLimit: 200
        maxFragmentBodySize: 8192
        defaultAlias: null
        operationNameAsParameter: false
        nullableFieldsRequired: false
        immutableInputFields: true
        immutableTypeFields: true
        inputAsRecord: false
        typeAsRecord: false
        jspecify: false
        asyncStyle: blocking
        reactiveHttpClient: jdk
        captureErrors: false
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** Java package name for generated files (e.g. `"com.example.generated"`). |
| `wsAdapter` | `"java11"` \| `"okhttp"` \| `"none"` | `"java11"` | Which WebSocket adapter to generate. `"java11"` uses `java.net.http.WebSocket` (zero extra dependencies). `"okhttp"` uses OkHttp's WebSocket client. `"none"` skips WebSocket adapter generation. |
| `jsonCodec` | `"jackson"` \| `"gson"` \| `"none"` | `"jackson"` | Which JSON codec helper to generate. `"jackson"` generates `JacksonGraphLinkJsonCodec`. `"gson"` generates `GsonGraphLinkJsonCodec`. `"none"` skips codec generation — supply your own lambdas. |
| `generateAllFieldsFragments` | `boolean` | `true` | Generates `_all_fields_TypeName` fragments for every type. Required for `autoGenerateQueries` and `autoGenerateQueriesFor`. |
| `autoGenerateQueries` | `boolean` | `true` | Automatically builds query strings for every operation. |
| `autoGenerateQueriesFor` | `object` \| `null` | `null` | Generates client methods only for the listed operations. Keys: `queries`, `mutations`, `subscriptions` — each takes a list of root field names. Unknown names cause a build error. Requires `generateAllFieldsFragments: true`. See [Selective auto-generation](custom-queries.md#selective-auto-generation-autogeneratequeriesfor). |
| `autoGenerateQueriesArgumentLimit` | `integer` \| `null` | `200` | Maximum number of propagated (nested-field) arguments allowed in the synthesized `fieldArgs` object of an auto-generated operation. When exceeded, GraphLink skips the operation and prints a `⚠` warning. Hand-written operations are never affected. See [Argument limit](custom-queries.md#auto-generated-query-argument-limit). |
| `maxFragmentBodySize` | `integer` \| `null` | `8192` | Maximum number of characters allowed in the serialized body of a generated `_all_fields` fragment. Fragments whose body exceeds this limit are silently omitted, and any auto-generated queries that depend on them are also skipped. Set to `null` to disable the cap. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the adapter interface includes an `operationName` parameter and the generated client appends it to the request URL as a query parameter. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, the generated input constructors do not accept `null` for nullable fields — `Objects.requireNonNull` is emitted for all fields. |
| `immutableInputFields` | `boolean` | `true` | Input class fields are `private final`. Inputs use builder pattern. |
| `immutableTypeFields` | `boolean` | `true` | Response type fields are `private final` with only getters. Recommended for client-side. |
| `inputAsRecord` | `boolean` | `false` | Generates input types as Java records instead of classes with builders. Records use component accessor syntax (`field()`) instead of getters (`getField()`). Requires Java 16+. |
| `typeAsRecord` | `boolean` | `false` | Generates response types as Java records. Affects how `fromJson` and mapping methods access fields. Requires Java 16+. |
| `jspecify` | `boolean` | `false` | Adds `@NonNull` / `@Nullable` from `org.jspecify.annotations` to all generated type, input, and interface fields. Imports are only emitted when enabled. |
| `asyncStyle` | `"blocking"` \| `"reactor"` \| `"rxjava3"` \| `"mutiny"` | `"blocking"` | Wraps query/mutation results in the library's deferred-single type (`Mono`/`Single`/`Uni`) and subscriptions in the deferred-many type (`Flux`/`Observable`/`Multi`). `"blocking"` keeps the pre-v5.0.0 direct-return / listener-callback client. See [Reactive client](java-client.md#reactive-client-v500). |
| `reactiveHttpClient` | `"jdk"` \| `"webclient"` | `"jdk"` | Transport used by the default adapter under a non-blocking `asyncStyle`. `"jdk"` uses `HttpClient.sendAsync` (works with every `asyncStyle`). `"webclient"` uses Spring `WebClient` (`asyncStyle: "reactor"` only). |
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
          "autoGenerateQueriesFor": null,
          "autoGenerateQueriesArgumentLimit": 200,
          "maxFragmentBodySize": 8192,
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
        autoGenerateQueriesFor: null
        autoGenerateQueriesArgumentLimit: 200
        maxFragmentBodySize: 8192
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
| `generateAllFieldsFragments` | `boolean` | `true` | Generates `_all_fields_TypeName` fragments for every type. Required for `autoGenerateQueries` and `autoGenerateQueriesFor`. |
| `autoGenerateQueries` | `boolean` | `true` | Automatically builds query strings for every operation using `_all_fields` fragments. |
| `autoGenerateQueriesFor` | `object` \| `null` | `null` | Generates client methods only for the listed operations. Keys: `queries`, `mutations`, `subscriptions` — each takes a list of root field names. Unknown names cause a build error. Requires `generateAllFieldsFragments: true`. See [Selective auto-generation](custom-queries.md#selective-auto-generation-autogeneratequeriesfor). |
| `autoGenerateQueriesArgumentLimit` | `integer` \| `null` | `200` | Maximum number of propagated (nested-field) arguments allowed in the synthesized `fieldArgs` object of an auto-generated operation. When exceeded, GraphLink skips the operation and prints a `⚠` warning. Hand-written operations are never affected. See [Argument limit](custom-queries.md#auto-generated-query-argument-limit). |
| `maxFragmentBodySize` | `integer` \| `null` | `8192` | Maximum number of characters allowed in the serialized body of a generated `_all_fields` fragment. Fragments whose body exceeds this limit are silently omitted, and any auto-generated queries that depend on them are also skipped. Set to `null` to disable the cap. |
| `defaultAlias` | `string` \| `null` | `null` | Default alias applied to all generated query fields globally. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, the adapter function signature includes an `operationName` parameter and the client appends it to the request URL. |
| `optionalNullableInputFields` | `boolean` | `true` | When `true`, nullable fields in generated input interfaces use `field?: T \| null` (TypeScript optional property). When `false`, they use `field: T \| null` (required but nullable). |
| `immutableTypeFields` | `boolean` | `true` | When `true`, generated type interfaces use `readonly` on all fields. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` behaviour to every query and mutation. Each method returns a `{OperationName}FullResponse` holding optional `data` and optional `errors` instead of throwing on GraphQL errors. Equivalent to annotating every query and mutation field with `@glCaptureErrors` in the schema. |

---

## `clientConfig.kotlin`

Used when `mode` is `"client"` and you want Kotlin output.

=== "JSON"

    ```json title="glink.json — clientConfig.kotlin"
    {
      "clientConfig": {
        "kotlin": {
          "packageName": "com.example.generated",
          "generateAllFieldsFragments": true,
          "autoGenerateQueries": true,
          "autoGenerateQueriesFor": null,
          "autoGenerateQueriesArgumentLimit": 200,
          "maxFragmentBodySize": 8192,
          "typeAsDataClass": true,
          "inputAsDataClass": true,
          "nullableFieldsRequired": false,
          "immutableTypeFields": true,
          "operationNameAsParameter": false,
          "captureErrors": false,
          "wsAdapter": "okhttp",
          "defaultAlias": null
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — clientConfig.kotlin"
    clientConfig:
      kotlin:
        packageName: com.example.generated
        generateAllFieldsFragments: true
        autoGenerateQueries: true
        autoGenerateQueriesFor: null
        autoGenerateQueriesArgumentLimit: 200
        maxFragmentBodySize: 8192
        typeAsDataClass: true
        inputAsDataClass: true
        nullableFieldsRequired: false
        immutableTypeFields: true
        operationNameAsParameter: false
        captureErrors: false
        wsAdapter: okhttp
        defaultAlias: null
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `packageName` | `string` | — | **Required.** Kotlin package name for all generated files. |
| `generateAllFieldsFragments` | `boolean` | `true` | Generates `_all_fields_TypeName` fragments for every type. Required for `autoGenerateQueries` and `autoGenerateQueriesFor`. |
| `autoGenerateQueries` | `boolean` | `true` | Automatically builds query strings for every operation using `_all_fields` fragments. |
| `autoGenerateQueriesFor` | `object` \| `null` | `null` | Generates client methods only for the listed operations. Keys: `queries`, `mutations`, `subscriptions` — each takes a list of root field names. Unknown names cause a build error. Requires `generateAllFieldsFragments: true`. See [Selective auto-generation](custom-queries.md#selective-auto-generation-autogeneratequeriesfor). |
| `autoGenerateQueriesArgumentLimit` | `integer` \| `null` | `200` | Maximum number of propagated (nested-field) arguments allowed in the synthesized `fieldArgs` object of an auto-generated operation. When exceeded, GraphLink skips the operation and prints a `⚠` warning. Hand-written operations are never affected. See [Argument limit](custom-queries.md#auto-generated-query-argument-limit). |
| `maxFragmentBodySize` | `integer` \| `null` | `8192` | Maximum number of characters allowed in the serialized body of a generated `_all_fields` fragment. Fragments whose body exceeds this limit are silently omitted, and any auto-generated queries that depend on them are also skipped. Set to `null` to disable the cap. |
| `typeAsDataClass` | `boolean` | `true` | Emit output types as `data class`. When `false`, uses `open class`. |
| `inputAsDataClass` | `boolean` | `true` | Emit input types as `data class`. When `false`, uses `open class`. |
| `nullableFieldsRequired` | `boolean` | `false` | When `true`, nullable constructor parameters have no default — callers must pass them explicitly. |
| `immutableTypeFields` | `boolean` | `true` | Generate `val` (immutable) fields instead of `var`. |
| `operationNameAsParameter` | `boolean` | `false` | When `true`, appends the operation name as a `?operationName=` query parameter in the HTTP request URL. |
| `captureErrors` | `boolean` | `false` | When `true`, applies `@glCaptureErrors` to every query and mutation. Each method returns a `{OperationName}FullResponse` with `data` and `errors` instead of throwing. |
| `wsAdapter` | `"okhttp"` \| `"none"` | `"okhttp"` | WebSocket adapter to generate. `"okhttp"` emits `DefaultGraphLinkWebSocketAdapter` using OkHttp; `"none"` emits only the `GraphLinkWebSocketAdapter` interface. |
| `defaultAlias` | `string?` | `null` | Default alias applied to all generated query fields globally. |

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

!!! info "Strict by default"
    Since v5.0.0, generated server types enforce real schema nullability by default and every type/interface gets a `GL<Type>Projection` companion interface. See [Strict server generation and projections](spring-server.md#strict-server-generation-and-projections), and the `@glServerLenient` / `@glReturnsProjection` directives in the [Directives reference](directives.md).

---

## `serverConfig.kotlinSpring`

Used when `mode` is `"server"` and you want a Kotlin Spring server instead of Java. See [Kotlin Spring Boot server](spring-server.md#kotlin-spring-boot-server) for the full walkthrough.

=== "JSON"

    ```json title="glink.json — serverConfig.kotlinSpring"
    {
      "serverConfig": {
        "kotlinSpring": {
          "basePackage": "com.example.generated",
          "typeAsDataClass": true,
          "inputAsDataClass": true,
          "blockingServices": true,
          "generateControllers": true,
          "generateRepositories": false,
          "immutableInputFields": true,
          "immutableTypeFields": false,
          "generateSchema": false,
          "schemaTargetPath": null
        }
      }
    }
    ```

=== "YAML"

    ```yaml title="glink.yaml — serverConfig.kotlinSpring"
    serverConfig:
      kotlinSpring:
        basePackage: com.example.generated
        typeAsDataClass: true
        inputAsDataClass: true
        blockingServices: true
        generateControllers: true
        generateRepositories: false
        immutableInputFields: true
        immutableTypeFields: false
        generateSchema: false
        schemaTargetPath: null
    ```

| Option | Type | Default | Description |
|---|---|---|---|
| `basePackage` | `string` | — | **Required.** Kotlin package name for all generated files. |
| `typeAsDataClass` | `boolean` | `false` | Emit output types as `data class`. When `false`, uses `open class`. |
| `inputAsDataClass` | `boolean` | `false` | Emit input types as `data class`. When `false`, uses `open class`. |
| `blockingServices` | `boolean` | `true` | Wraps each generated controller's service call in `withContext(Dispatchers.IO + SecurityCoroutineContext()) { ... }`. Set `false` for a coroutine-native, non-blocking service layer. |

The remaining options (`generateControllers`, `generateRepositories`, `immutableInputFields`, `immutableTypeFields`, `generateSchema`, `schemaTargetPath`) behave the same as their `serverConfig.spring` equivalents above.

---

## Identifier normalization

Since v5.0.0, every generated identifier — field names, argument names, enum values, and type/input/interface/union/enum names — is unconditionally rewritten to the target language's canonical casing convention (lowerCamelCase fields for Dart/Java/Kotlin/TypeScript, SCREAMING_SNAKE enum values for Java/Kotlin, PascalCase enum values for TypeScript, PascalCase type names everywhere). This is not opt-in and there is no config flag to disable it.

A GraphQL name that collides with a target-language reserved keyword (e.g. an argument or field named `default`, `return`, `object`) is also automatically sanitized (`default_`, with numeric suffixing on further collisions), while the wire/GraphQL name is preserved. This applies consistently to fields, arguments, enum values, resolver parameters, `@glMapsTo` mappings, and Spring controller/service signatures.

**Migration:** if your schema's GraphQL names aren't already in canonical casing (e.g. `snake_case` fields, lowercase type names), regenerating renames the corresponding generated fields/classes/methods. Review the diff after upgrading and update any application code that references generated identifiers directly. Because the generated identifier can now differ from the wire name, `toJson`/`fromJson` are mandatory on every serializer (Dart, Java, Kotlin, TypeScript) as of v5.0.0 — code that reads/writes generated objects without going through them can no longer assume the two names match.

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
