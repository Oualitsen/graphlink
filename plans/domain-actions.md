# Hexagonal support: domain actions on models

Status: discussion notes, nothing decided yet. To pick up later.

## Goal

Help users build hexagonal (ports and adapters) backends with as little GraphLink code to maintain as possible, and with results
that make developers happy (adoption first).

## What GraphLink already gives a hexagon

- The generated service interface is the **inbound port**; controllers/resolvers are the **inbound adapter**.
- `@glSkipOnClient` on a type or field strips it from every client and from the served schema. A type marked `@glSkipOnClient` is
  therefore a **domain-only type**: declared in the `.graphql`, never exposed. This answers "domain types would leak into the API".
- `@glMapsTo` maps an API input to a type, respecting types and nullability (`createOrderInput.toOrder()`): the boundary mapper.
- What GraphLink can't generate: repositories, outbound ports, the domain logic itself. The schema describes the API, not the
  domain or the storage. Generating "the architecture" (folders, layers) would be opinion, not derivation. Out of scope.

## The idea: actions on models

A directive (working name `@glAction`) on a field of a type: the field is not data and not resolvable; it becomes a method on the
model that the developer implements. Arguments become parameters, the field type becomes the return type.

```graphql
type Order @glSkipOnClient {          # domain type, never exposed
  id: ID!
  lines: [OrderLine!]!
  total(currency: Currency!): Money! @glAction
  cancel(reason: String): Order! @glAction
}
```

## Options discussed

### A. Abstract method on the model, developer subclasses it (rejected)

```java
public abstract class Order { ...fields...; public abstract Money total(Currency currency); }
public class OrderImpl extends Order { ... }
```

Generated code creates instances itself (`fromJson`, nested decoding, `copyWith`, `@glMapsTo` mappers) and would never create the
developer's subclass. Every type serializer of every target would have to change. Per language:

| Language | Generated today | Abstract + subclass? |
|---|---|---|
| Java | plain class (Spring server), records possible | a class can be abstract, a record can't be extended; `fromJson` calls `new Article(...)` anyway |
| Kotlin | data class or open class (config) | a `data class` can't be `abstract` or `open`; an open class has the same `fromJson` problem |
| TypeScript | `interface` + `namespace`, `fromJson` returns a plain object literal | impossible: the model can't have methods at all |
| Python | pydantic model | `@abstractmethod` works on pydantic v2 (to verify), but nested decoding calls the generated class, never the subclass |
| Go | struct | no abstract types, no inheritance |

### B. One generated port per type (rejected)

```java
public interface OrderActions { Money total(Order order, Currency currency); }
```

Cheap (reuses the schema-mapping IR), but it's an anemic model plus a service: behaviour beside the entity, not on it. Developers
expect `order.total(EUR)`. In hexagonal architecture, ports are for crossing the boundary (repositories, external services, use
cases); entity behaviour lives on the entity. B was a mistake, recommended only to avoid the instantiation problem of A.

### C. Generated method forwards to developer code (current favourite)

Generated, regenerated every time:
```java
public record Order(String id, List<OrderLine> lines) {
  public Money total(Currency currency) { return OrderLogic.total(this, currency); }
}
```

Written by the developer; GraphLink creates a stub once if it's missing and never overwrites it:
```java
public final class OrderLogic {
  static Money total(Order order, Currency currency) { ... }
}
```

- Developers get `order.total(EUR)`.
- Enforced like an abstract method: a missing or wrong `OrderLogic.total` is a compile error.
- The model stays a normal generated class: records, data classes, `fromJson`, `copyWith`, mappers untouched.
- Small maintenance: one forwarding method per action per target, plus the stub file the first time.
- Limit: the logic is static, no injection. Dependencies become parameters (`total(currency, rates)`), which is how domain logic
  should be written anyway, but some developers will want DI inside entities.

Per language:

| Language | Shape |
|---|---|
| Java | method forwarding to a static class `OrderLogic` |
| Kotlin | method forwarding to `object OrderLogic` |
| Dart, Python | method forwarding to top-level functions in a developer-owned file that the generated file imports |
| TypeScript | no methods possible on the interface: a function in the existing namespace, `Order.total(order, EUR)`, forwarding to the developer's function (same style as `Order.toJson(order)`). Real methods would mean turning all TS types into classes: not for this feature |
| Go | native: the developer writes `func (o Order) Total(c Currency) Money` in another file of the package; GraphLink generates `var _ OrderActions = Order{}` so a missing method fails to compile. No forwarding |
| Swift, C#, Rust (future) | native too: `extension`, `partial`, `impl` in a developer file |

## Related: factories

`Order create()` in typical rich models is a factory, not an action on an instance. `@glMapsTo` already generates it from an input
(`createOrderInput.toOrder()`). A factory with logic (a static action) is a possible later addition; keep it out of v1.

## Related: mapping to several types

With domain types in the schema, `@glMapsTo` could become repeatable: one input mapped to several types (e.g. the domain type and a
command). Probably cheap once the IR handles one target; needs a concrete use case first.

## Open questions

1. Directive name: `@glAction`?
2. Where the developer's logic files live: convention (`<outputDir>/../domain/`) or a config key (leaning: config key with a default).
3. Server only for v1? (leaning yes: hexagonal is a backend concern)
4. Must `@glAction` require the type to be `@glSkipOnClient` (keeps actions off API types)? Leaning yes.
5. Option C confirmed as the default, Go native, TypeScript namespace functions?

## Other topics from the same conversation (not part of this feature)

- **New targets**: C# (ASP.NET Core, `System.Text.Json` built in, close to the Java/Kotlin serializers) before Rust (small
  schema-first market, serde/tokio dependencies, hard IR fit). A Go server may be the cheapest new backend (the Go type serializer
  exists, gqlgen is the schema-first standard).
- **FastAPI / Django vs the Spring philosophy** (reviewed on the `server_integration_tests` output):
  - Aligned: one `Protocol` per service (like the Java interface), separate guards, same batch-mapping signature, explicit
    `to_json`/`from_json`, more precise nullability than Java.
  - REST is a framework-neutral route table with runtime shape validation (`rest/core.py`), not native FastAPI/Django code like
    Spring's `@GetMapping`. Deliberate (one core for two frameworks); keep for now, OpenAPI covers the docs gap.
  - FastAPI `create_app` owns the whole app and hardcodes `CORSMiddleware(allow_origins=["*"])`; Spring emits no CORS. Fix:
    expose a mountable router, drop the CORS middleware.
  - Django: every REST view and the GraphQL view are `csrf_exempt`. Fine with token auth, silently disables CSRF with session
    cookies. Document it, ideally make it configurable.
  - One `GraphLinkServices` dataclass with every service required: less idiomatic than DI but the same fail-at-startup behaviour.
