# Generated Java does not compile on Java 8

GraphLink supports Java 8+, but generated Java uses Java 9–11 language features and APIs. Nothing catches it because
every Java test package compiles with JDK 21 (`maven.compiler.source/target` 21 in the client `pom.xml`s).

## Test added

`make -C server_integration_tests java8-check` (or `make -C clients/java_client java8-check`, `java_reactive_client`):
`scripts/java8_check.sh` compiles the generated sources with `javac --release 8`. Files importing `java.net.http`
(the opt-in `java11` transports) are compiled at `--release 11` first and put on the classpath, so they are the only
files allowed to use Java 9+.

Current result: **fails**, 14 errors in each of `java_client` and `java_reactive_client`.

Not wired into CI yet: it would fail until bug 1 is fixed.

## Bugs

### 1. `for (var x : …)` in every generated Java client (Java 10+)

- Source: `JavaCodeGenUtils.forEachLoop`, `lib/src/java_code_gen_utils.dart:225` writes `for (var $variable : $iterable)`.
- Emitted into `client/GraphLinkResolverBase.java` of **every** Java client (14 loops: cache tags, partial queries,
  fragment names), through `java_client_runtime_serializer.dart` and `java_client_adapters_serializer.dart`.
- Fix: give `forEachLoop` a required element type (or emit `final Object` / let callers pass `String tag`).
  Every caller knows the element type.

### 2. `final var` in generated Spring REST controllers (Java 10+)

- Source: `JavaCodeGenUtils.constDecl`, `lib/src/java_code_gen_utils.dart:188` defaults the type to `var`.
- Callers without `type:`: `jvm_spring_rest_controller_serializer_base.dart` lines 201, 316, 338, 371, 439, 468, 496 and
  `java/java_spring_rest_controller_serializer.dart` lines 96, 106, 241, 254.
- Seen in 16 files of `servers/java_server` and 11 of `servers/java_server_reactive` generated code.
- Impact today: low (Spring Boot 3 needs Java 17), but it breaks the moment the server target supports Spring Boot 2
  / Java 8, and `constDecl` silently defaults to `var` for any future Java caller.
- Fix: make `type` required in `JavaCodeGenUtils.constDecl` and pass the declared type.

### 3. Java 9+ APIs in the REST client runtime (`java_rest_constants.dart`)

Found by compiling `integration_tests/real/java_rest_client_tests_real` and `java_rest_reactor_client_tests_real`
with `--release 8` (same script, by hand):

| Generated file | API | Since | Source line |
|---|---|---|---|
| `RestResponse.java` | `InputStream.readAllBytes()` | 9 | `java_rest_constants.dart:146` |
| `RestResponse.java` | `InputStream.transferTo`, `OutputStream.nullOutputStream()` | 9 / 11 | `:159` |
| `GLDownload.java` | `InputStream.readAllBytes()` | 9 | `:227` |
| `GLDownload.java` | `URLDecoder.decode(String, Charset)` | 10 | `:260` |
| `GraphLinkRestUtils.java` | `Map.entry` | 9 | `:362`, `:364`, `:372` |
| `GraphLinkRestResolver.java` | `String.isBlank()` | 11 | `:709` |

Fix: a byte-copy loop, `URLDecoder.decode(s, "UTF-8")`, `new AbstractMap.SimpleImmutableEntry<>(k, v)`,
`text.trim().isEmpty()`.

### 4. Java 10 API in the persisted-queries GET request

- `GraphLinkGetRequest.java`: `URLEncoder.encode(value, StandardCharsets.UTF_8)` (Java 10).
- Source: `java_client_constants.dart:991`. Fix: `URLEncoder.encode(value, "UTF-8")`.

### Not bugs

- `DefaultGraphLinkClientAdapter` / `DefaultGraphLinkWebSocketAdapter` / `DefaultGraphLinkRestAdapter` use
  `java.net.http` and `List.of`: they are the `java11` transports, Java 11 by design.
- `spring_rest_support.dart:161` (`readAllBytes`): Spring Boot 3 server runtime, Java 17 anyway.

## Follow-ups

- Add `java8-check` to the REST and persisted-queries Java packages in `integration_tests/` (they hold bugs 3 and 4,
  which the two clients here do not generate).
- Run `java8-check` in CI once bugs 1, 3 and 4 are fixed.
- Optionally a unit test in `test/java/` that asserts generated Java contains no `var ` declarations.
