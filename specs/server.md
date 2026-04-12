# GraphLink — Server Generation Spec

Rules for generating server-side code from a GraphQL schema. The reference target is Spring Boot (MVC and WebFlux), but these rules are framework-agnostic where possible.

---

## Config options (`serverConfig.spring`)

| Key | Type | Default | Effect |
|---|---|---|---|
| `basePackage` | string | required | Root Java package. Sub-packages are appended per artifact (`types`, `inputs`, `services`, `controllers`, etc.) |
| `generateControllers` | bool | `true` | Emit controller classes |
| `generateInputs` | bool | `true` | Emit input classes |
| `generateTypes` | bool | `true` | Emit type classes |
| `generateRepositories` | bool | `false` | Emit JPA repository interfaces (requires `@glRepository` on schema interfaces) |
| `inputAsRecord` | bool | `false` | Emit inputs as Java records instead of classes |
| `typeAsRecord` | bool | `false` | Emit types as Java records instead of classes |
| `generateSchema` | bool | `false` | Copy the schema file to `schemaTargetPath` |
| `schemaTargetPath` | string | — | Required when `generateSchema: true`. Must end with `.graphql` or `.graphqls` |
| `injectDataFetching` | bool | `false` | Add `DataFetchingEnvironment` parameter to every controller and service method |
| `reactive` | bool | `false` | Use `Mono`/`Flux` (WebFlux) instead of `CompletableFuture` (MVC) |
| `useSpringSecurity` | bool | `false` | Capture and propagate `SecurityContext` inside `CompletableFuture` lambdas. MVC only — has no effect when `reactive: true` |
| `immutableInputFields` | bool | `true` | Generate input fields as `final` |
| `immutableTypeFields` | bool | `false` | Generate type fields as `final` |

---

## Schema constructs

### Types → classes / records

Every non-root, non-internal type produces one file.

- Fields annotated `@glSkipOnServer` are excluded from the generated class.
- Fields annotated `@glSkipOnClient` are included (server-only fields).
- `immutableTypeFields: true` → fields are `final`, constructor-initialized.
- `typeAsRecord: true` → emit as a Java `record` instead of a class.

### Inputs → classes / records

Same rules as types, with `immutableInputFields` and `inputAsRecord`.

### Enums

Emitted as Java `enum` with one constant per value.

### Interfaces

Emitted as Java `interface`. Fields become getter method signatures.

---

## Services

One service interface is generated per logical service group. The default grouping is by the return type of the operation. Use `@glServiceName` to override.

### Method signatures

| Mode | Query/Mutation return | Subscription return |
|---|---|---|
| MVC (`reactive: false`) | `T methodName(args)` | `Flux<T> methodName(args)` |
| WebFlux (`reactive: true`) | `Mono<T> methodName(args)` | `Flux<T> methodName(args)` |

### `@glValidate`

Adding `@glValidate` to a query or mutation generates an additional method in the service interface:

```
// MVC
void validateMethodName(args);

// WebFlux
Mono<Void> validateMethodName(args);
```

The validation method is named `validate` + operation name with first letter uppercased.

---

## Controllers

One controller class is generated per service. It holds a `final` reference to the service and delegates all calls.

### MVC (`reactive: false`)

- Query and mutation methods return `CompletableFuture<T>`.
- The service call is wrapped in `CompletableFuture.supplyAsync(() -> ...)`.
- Void mutations use `CompletableFuture.runAsync(() -> ...)`.
- Subscription methods return `Flux<T>` directly (no `CompletableFuture`).

#### With `@glValidate`

When the operation has `@glValidate`, the validation call is placed **inside** the `CompletableFuture` lambda, before the service call:

```java
return CompletableFuture.supplyAsync(() -> {
    service.validateMethodName(args);
    return service.methodName(args);
});
```

#### With `useSpringSecurity: true`

The `SecurityContext` is captured on the request thread before the lambda, set on the worker thread at the start of the lambda, and cleared in a `finally` block:

```java
SecurityContext securityContext = SecurityContextHolder.getContext();
return CompletableFuture.supplyAsync(() -> {
    SecurityContextHolder.setContext(securityContext);
    try {
        // validation call if @glValidate present
        return service.methodName(args);
    } finally {
        SecurityContextHolder.clearContext();
    }
});
```

### WebFlux (`reactive: true`)

- Query and mutation methods return `Mono<T>`.
- The service call is returned directly: `return service.methodName(args);`.
- Subscription methods return `Flux<T>` directly.

#### With `@glValidate`

The `Mono<Void>` validation call is chained with `.then()`:

```java
return service.validateMethodName(args).then(service.methodName(args));
```

### `injectDataFetching: true`

Adds `DataFetchingEnvironment dataFetchingEnvironment` as the last parameter on every controller and service method. The same parameter is forwarded in the service call.

---

## Directives

### `@glSkipOnServer`

Applied to a **type**: the type is excluded from server generation. The type's fields are mapped to `Object` (or a `mapTo` target) in service/controller signatures.

- `@glSkipOnServer` alone → return type becomes `Object`
- `@glSkipOnServer(mapTo: "SomeServerType")` → return type becomes `SomeServerType`
- `@glSkipOnServer(batch: true)` → generates a `@BatchMapping` instead of `@SchemaMapping`
- `@glSkipOnServer(batch: false)` → generates a `@SchemaMapping`

Applied to a **field on a non-root type**: the field is excluded from the generated class. The field must have `@glSkipOnServer` if it has arguments (schema mappings with arguments require explicit opt-in).

### `@glSkipOnClient`

Applied to a field: the field is included in server generation and excluded from client generation. Use for server-only fields (e.g. `password`, internal IDs).

### `@glServiceName(name: "ServiceName")`

Applied to a query, mutation, or subscription: assigns the operation to the named service instead of the default service derived from the return type.

### `@glValidate`

Applied to a query or mutation: generates a validation method in the service interface and calls it before the main service call in the controller. See controller section for generated code.

### `@glRepository(glType: "Entity", glIdType: "Long")`

Applied to an interface: generates a Spring Data JPA repository interface extending `JpaRepository<Entity, Long>`. Requires `generateRepositories: true`.

- `glClass` arg: override the base repository class (default `JpaRepository`)

### `@glDecorators(value: ["@Transactional"], applyOnServer: true)`

Applied to a type, field, or argument: adds the listed annotations to the generated Java element. Controlled by `applyOnServer` / `applyOnClient` flags.

### `@glEqualsHashcode(fields: ["id"])`

Applied to a type: generates `equals()` and `hashCode()` based on the listed fields.

### `@glMapsTo(type: "TargetType")`

Applied to an input: generates a `toTargetType()` conversion method on the input class.

### `@glMapField(to: "targetFieldName")`

Applied to an input field: maps this field to a differently-named field on the `@glMapsTo` target type when generating the conversion method.

### `@glUpload`

Applied to a scalar: marks the scalar as a file upload type.

- MVC → parameter type becomes `MultipartFile` (or `List<MultipartFile>`)
- WebFlux → parameter type becomes `FilePart` (or `List<FilePart>`)

### `@glExternal(glClass: "com.example.MyClass", glImport: "com.example.MyClass")`

Applied to a scalar: the scalar is mapped to the given Java class. No class is generated; the import is added wherever the scalar is used.

---

## Schema mappings

When a type has fields annotated with `@glSkipOnServer`, the generator produces `@SchemaMapping` (or `@BatchMapping`) methods in the controller to resolve those fields from the backing server type.

| Mapping kind | Controller method | Service method |
|---|---|---|
| Regular (`batch: false`) | `@SchemaMapping` — takes the parent object as `SomeType value` | Returns the field type |
| Batch (`batch: true`) | `@BatchMapping` — takes `List<SomeType> value` | Returns `Map<SomeType, FieldType>` |
| Identity | Returns the value directly (getter passthrough) | — |
| Forwarded | Calls the getter on the backing server type | — |
| Forbidden | Throws `GraphQLException("Access denied …")` | — |
