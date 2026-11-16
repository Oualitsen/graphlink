# REST operations on the generated servers — design, tests, findings

Autonomous run, written for review. Scope: Spring Boot (Java MVC, Java reactive, Kotlin blocking, Kotlin suspend) first, then Express.

## Result

Every `@glRest*` operation of the schema is now served by the generated server, next to the GraphQL operations, through a
**separate REST controller that calls the same service interface** the GraphQL controller uses.

| | Java MVC | Java reactive | Kotlin blocking | Kotlin suspend | Express |
|---|---|---|---|---|---|
| REST controller | `<Service>RestController` | same, `Mono`/`Flux` results | same, plain `fun` | same, `suspend fun` | one router, `rest/build-rest-router.ts` |
| `server_rest` cases (202 + concurrency) | pass, 1 known defect | pass | pass, 1 known defect | pass, 1 known defect | pass |
| `server_faults` (GraphQL) | pass | pass, 2 new known defects (WebFlux) | pass | pass | pass |

* New generator unit tests: `test/server/rest/rest_server_test.dart`, 62 tests. 1105 tests of the directories that touch controllers, the
  GraphQL serializer, mappings, keywords, uploads and the REST clients still pass.
* Client x server regression (existing GraphQL suites): dart x TS, ts x TS, go x TS, ts x Java, java x Java, kotlin x Java reactive,
  java_reactive x Java reactive, dart x Kotlin blocking, python x Kotlin suspend pass. Swift was not run (needs Xcode).

## Design

### One IR, two transports
* `resolveRestOperations()` (until now client mode only) also runs in server mode (`resolveServerRestOperations`, `gl_grammar_rest_server_extension.dart`),
  then `validateRestServerSupport()` rejects what the server cannot serve yet, with a message.
* A REST operation stays a field of its **service** (so the service interface carries it), but it is taken out of
  * the GraphQL controller (`GLController.ofService(..., skip: isRestField)`; a service left without GraphQL fields has no GraphQL controller),
  * the generated GraphQL schema (`GLGraphqlSerializer`; the `Void` / `Download` marker scalars are dropped too — graphql-java refuses a custom scalar with no wiring; a `Query` left without fields while a `Mutation` still has GraphQL ones keeps a `_glRestOnly: Boolean` field so the schema stays valid),
  * **everything GraphQL when the schema has no GraphQL operation at all** (`GLParser.restOnly`): no GraphQL schema file, no map type resolver config, and for Express no `typeDefs.ts`, no `build-resolvers.ts`, no Apollo — `createServer` is an Express app with the REST router and `restErrorHandler`,
  * the GraphQL resolvers (Express), and `@glInjectContext` / global `injectContext` do not apply to it.
* `GLRestController` (`model/gl_rest_controller.dart`) is the model of the REST adapter of one service; `GLParser.restControllers` holds them.

### Why separate classes
Same answer as before the work started: the service interface is the seam, the REST controller is a thin adapter, and a separate class lets REST be switched
off per service without touching the GraphQL side. Mixing annotations in one class works in Spring too, but class-level annotations
(`@PreAuthorize`, `@Validated`, `@CrossOrigin`, `@RequestMapping`) would then hit both transports.

### Wire values: numbers, strings and maps
As for the GraphQL controllers, the REST controllers never take generated types:

| Argument | Spring parameter | Converted with |
|---|---|---|
| `Int`, `Float`, `Boolean`, `String`, `ID` | `Integer` / `Double` / `Boolean` / `String` (primitive when required) | nothing |
| enum | `String` | `Enum.fromJson(String)` (unknown value: `400`) |
| input object in the body | `Map<String, Object>` | `Input.fromJson(map)` inside `GraphLinkRest.decode` |
| list of input objects | `List<Map<String, Object>>` | `list.stream().map(Input::fromJson)` |
| input object in the query / headers (SPREAD) | one parameter per field | a `Map` is assembled from the present ones, then `Input.fromJson` |
| result | `Map<String, Object>` / `List<...>` / scalar / `String` | `toJson()` |

`GraphLinkRest.decode` (generated once, `rest/GraphLinkRest.java|kt`) turns any `RuntimeException` of a conversion (`ClassCastException`, `NullPointerException`
from a missing required field, an unknown enum value) into `400 Bad Request` without echoing the message. Express reaches the same result differently
(next section), because its generated `fromJson` only casts.

### Spring specifics
* Mapping per method: `@GetMapping` / `@PostMapping` / `@PutMapping` / `@PatchMapping` / `@DeleteMapping`; `@PathVariable`, `@RequestParam`, `@RequestHeader`,
  `@RequestBody`. A required argument is `required = true`; a nullable or defaulted one is `required = false` (and `defaultValue = "..."`).
* Blocking Java and Kotlin call the service directly on the request thread. Reactive Java returns `Mono<T>` (`Mono<List<T>>` for a list: `collectList()`),
  `Void` is `Mono<Void>` via `.then()`. `@glValidate` is chained with `.then(Mono.defer(...))` as for GraphQL. Kotlin suspend handlers are `suspend fun`
  (Spring MVC 6.1+ supports them; the test servers run Spring Boot 3.4).
* `Void` results answer `204` (`@ResponseStatus(NO_CONTENT)`), `response: TEXT` sets `produces = "text/plain"`.
* A plain `String` result would be written as bare text by `StringHttpMessageConverter` (no quotes, so invalid JSON). It is wrapped by
  `GraphLinkRest.json(...)` (a `@JsonValue` holder), which makes Jackson write `"hello"`.
* Java annotations need `value = "..."` once a second attribute is present; Kotlin takes the path positionally and arrays as `["..."]` (hooks `pathAttribute`, `annotationArray`).

### Express specifics
* One `Router` (`buildRestRouter(services)`) built from every REST operation, mounted by `createServer` after the GraphQL middleware and before the error handler.
  `RestServices` is a subset of `GraphLinkServices`, so the existing object is passed as is. `contextFactory(req, res)` provides `context` (REST has no `info`).
* `rest/support.ts` (static runtime): `pathArg`, `queryArg`, `queryListArg`, `headerArg`, `headerListArg`, `bodyArg`, `validate`, response senders, `RestError`.
  * Query strings are read with `URLSearchParams` on `originalUrl` (not Express's `qs`), so `a[b]=c` is not an object and `+` is a space, as in Spring.
  * Lists: repeated keys, and comma separated values (Spring splits them for a `List` parameter, so both servers agree).
  * Scalars are parsed strictly (`Int` is a 32-bit integer, `Boolean` is `true` / `false`, enums are checked against their values).
  * The generated `Input.fromJson` is `json["qty"] as number`, i.e. it validates nothing. Bodies (and spread inputs) are therefore validated against a **shape**
    generated from the input type (`required`, types, enums, lists, nested inputs) before `fromJson` runs.
  * A request body is "present" when `Content-Length` > 0 or chunked, because `express.json()` leaves `{}` in `req.body` for an absent body.
    A non-JSON content type on a present body is `415`. Optional arguments that are absent reach the service as `null`, not `undefined`.
  * `405` (with `Allow`) for a known path with another method, `404` JSON under the common REST prefix; both without stack traces. A service exception is `500 {"status":500,"error":"Internal Server Error"}`.
* `serializeService` drops the `info` parameter of REST operations; `Void` maps to `void`.

### Uploads (multipart file parts and raw bodies)

| Schema | Spring MVC / Kotlin | Spring WebFlux | Express |
|---|---|---|---|
| `file: Upload! @glRestPart` | `@RequestPart MultipartFile` | `@RequestPart Part`, checked to be a `FilePart` | `fileArg(form, ...)` → `FileUpload` |
| `files: [Upload!]! @glRestPart` | `@RequestPart List<MultipartFile>` | `@RequestPart List<FilePart>` | `fileListArg` (request order kept) |
| scalar / enum `@glRestPart` | `@RequestParam` (binds multipart text fields) | `@RequestPart String` + `Integer.valueOf` / `fromJson` | `formArg` / `formListArg` (same shapes as query values) |
| `file: Upload! @glRestBody` | `GraphLinkRestUpload.rawFile(HttpServletRequest)` (a `MultipartFile` over the request stream) | `GraphLinkRestUpload.rawFile(headers, Flux<DataBuffer>)` (a `FilePart`) | `rawUploadArg(req)` (the request stream) |

* The upload types are the ones GraphQL uploads already used (`MultipartFile` / `FilePart` / `FileUpload`), so one service implementation reads the same type whichever transport called it.
* **The service interface moves the upload argument to the end** (the retyping re-adds it). The REST controllers call the service in the service's own argument order, not the schema's; before, the generated code did not compile.
* A nullable `Upload` argument is optional; a required one that is absent, or sent as a plain text field, is a `400`.
* Spring MVC: `@RequestPart` on a request that is not multipart throws `MultipartException`, which Boot answers `500`; a controller-local `@ExceptionHandler` turns it into `400` (and `MaxUploadSizeExceededException` into `413`). WebFlux gets the same for `DecodingException`.
* Express: `busboy` writes each file to a temporary directory (removed when the response closes) so `createReadStream()` works after parsing; files keep the order of the request; names and filenames are decoded as UTF-8; above `maxFileSize` (100 MB) a `413`.
  `busboy` is imported by `rest/uploads.ts` only when a schema has multipart parts. The GraphQL upload machinery (`graphql-upload`, `csrfPrevention: false`, the `Upload` scalar in the schema) is generated only when a *GraphQL* operation takes an upload.

### Forms (`@glRestField`)
`application/x-www-form-urlencoded` bodies: scalars, enums, defaults, lists (repeated or comma separated keys) and the structured values below.

* Java / Kotlin MVC: `@RequestParam` (Spring reads query string and form for it; `PUT`/`PATCH`/`DELETE` forms work through Boot's `FormContentFilter`).
* WebFlux: `@RequestParam` sees **only the query string**, and `@RequestBody MultiValueMap` answers `415`. The handler takes `ServerWebExchange`, reads `getFormData()` and
  runs the whole body inside `flatMap`; fields are read with `GraphLinkRest.field` / `fields` and parsed with the same helpers as multipart text parts.
* Express: `express.text({ type: 'application/x-www-form-urlencoded' })` and `URLSearchParams` (`readForm`); a non-form body is `415`.
* A JSON body sent to a form operation is `400` or `415` depending on the server (the suite accepts both).

### Structured query and form values
An input object with **nested objects**, a **list of input objects** and any value sent as **JSON text** (`encoding: JSON`) in the query string or a form.

* Keys nest with dots (`address.city`, `items.0.name`) or brackets (`address[city]`, `items[0][name]`); both are read, whatever `formNesting` the client used. A
  spread argument (`SPREAD`, the default for a query) reads its fields at the top level (with their `@glRestParam(name:)` names), `FLAT` reads them under the argument name.
* Spring: a generated `rest/GraphLinkRestParams` (Java and Kotlin) walks a **shape** the controller builds from the schema (`Shape.obj().field("address", "address", ...)`),
  parses scalars strictly (`-?\d+`, `true` / `false`, enum members) and hands the nested map to the same `fromJson` the bodies use. Express reuses its body `shapes`
  (`nestedArg`, `jsonArg`, then `validate`).
* Limits: a list of objects is read until the first missing index (`items.0`, `items.2` reads only the first); an empty list or an absent value is `null`; a recursive input is
  rejected at generation time; a list of lists stays rejected; an input object as a multipart part stays rejected.

### Downloads (`@glDownload`)
A service returns `GraphLinkDownload` (generated into `rest/`): Spring `new GraphLinkDownload(Resource, filename?, contentType?)`, Express `{ data: Readable | Uint8Array | string, filename?, contentType?, length? }`.

* Spring answers `ResponseEntity<Resource>` (`Mono<...>` on WebFlux, `204` for an empty `Mono`). The content type is explicit, else guessed from the file name, else
  `application/octet-stream`: without that, MVC picked `application/json` (found by the suite). `Content-Disposition: attachment` uses `filename*=UTF-8''...` for non-ASCII names.
* Express pipes a stream (`stream/promises.pipeline`, so a failure destroys the response) or ends with a buffer, and writes `Content-Disposition` itself (found by the suite: the
  library's header carried a raw `é` in a quoted string).
* A nullable `Download` answers `204` for `null`. A 5 MB stream with no length is checked byte by byte. Not covered: `Range` requests (Spring serves them for a `Resource`, Express does not), `HEAD`.

### `responsePath`
The server **nests** the result: `responsePath: "data.items"` answers `{"data":{"items":[...]}}`, which is what a client generated from the same schema unwraps. A nullable result stays in the
envelope (`{"result":null}`), also for an empty `Mono`.

### Interceptors and the request context
`@glIntercept` (on the operation or on its `type` / `extend type` block) and `@glInjectContext` work on REST operations.

* The interceptor and the service take the same context type as for GraphQL. A REST request has no GraphQL context, so the server builds one **per request** whose only entry is
  the HTTP request, under `request` (`HttpServletRequest` on MVC, `ServerWebExchange` on WebFlux). Express uses its `contextFactory`, as before.
* `runBefore` runs **after** the arguments are decoded (it receives the decoded values, as in GraphQL) and **before** `@glValidate` and the service. A throw denies the request: use
  `ResponseStatusException(HttpStatus.FORBIDDEN)` on Spring or `RestError(403, ...)` (from `rest/support`) on Express; any other exception is a `500`.
* Kotlin handlers of an intercepted operation are `suspend` (the interceptor is); a blocking service then runs on `Dispatchers.IO + SecurityCoroutineContext`, as in the GraphQL controllers.
* A block level `@glIntercept` applies to REST operations too. (The earlier rejection of `@glIntercept` only looked at the field's own directive, so a block level one would have been skipped without a word; inferred from that code, not reproduced. The suite has a case for the block level.)

### Error behaviour (same on all five servers, asserted by the suite)

| Situation | Status |
|---|---|
| bad scalar / enum / list element in path, query or header, missing required value | 400 |
| malformed JSON, JSON `null`, a scalar or array where an object is expected, missing or mistyped field, unknown enum value, `null` list element | 400 |
| body present but not JSON | 400 or 415 |
| known path, wrong method | 405 |
| unknown path (under the REST prefix) | 404 |
| exception in the service (or in `@glValidate`) | 500, JSON or empty body, no stack trace, file path or exception message |
| nullable result that is `null` | 200 with an empty body |
| `Void` | 204 |

## Tests

### `server_rest/` (integration, all five servers, the important part)
`schema_rest/rest.gql` is merged into every **server** schema (never into the client harnesses' `schema/`). Each server implements it
(`impl/RestImpl.java|kt`, `impl/rest-impl.ts`), so one table, `server_rest/cases.json`, drives all of them through `run_rest.py` (stdlib Python, raw HTTP):

* 202 cases + an 80-thread concurrency check, per server. Path (string, int, float, boolean, enum, percent-encoding, Unicode), query (scalars, defaults, repeated and
  comma lists, enum lists, spread input object, `+`, `&`, `=`, 4 KB values), headers (case-insensitive names, spread input), JSON bodies (object, list, empty list,
  optional body, `null`, `[]`, `42`, 50 KB value, 500-deep array, wrong content types, unknown fields, `null` optional fields, Unicode), responses (object, list, scalar, string,
  enum list, text, `Void`, nullable `null`), PUT / PATCH / DELETE, `@glValidate`, reserved words as argument names (`class`, `return`, `if`, `switch`),
  uploads (a file, text parts next to it, Unicode filename and text, empty, 64 KB of every byte value, 6 MB, a list of files, an optional file with and without a body, a raw body with a header, 6 MB, chunked and empty, plus not-multipart, no body, missing file, a file sent as text, bad enum and int parts, a malformed envelope and one without boundary), 405 / 404, a service that throws, and a GraphQL operation on the same service as REST ones (the GraphQL schema, read by introspection, must not contain any REST operation).
* Every response is checked for leaks (stack frames, `/Users/`, `node_modules`, `org.springframework`, the exception messages the services throw); every error body must be empty or JSON; the server
  must answer afterwards (a case that kills it fails the next ones loudly).
* Comparison treats a missing key as `null` (the TS server omits `undefined`, Spring emits `null`) and keeps booleans and numbers distinct.
* Uploads are checked by SHA-256 and size of what the service read, against what the runner sent (`{{sha256:file}}`, `{{size:file}}` in the expected JSON).
* `known_defects.json` (a passing known defect fails the run): one entry, `upload_multipart_without_boundary` on the three servlet-stack Spring servers (see below). Nothing else is excluded.
* Run: `make -C server_integration_tests ci-rest-<typescript|java|java-reactive|kotlin-blocking|kotlin-suspend>`; `ci-http-<server>` runs the fault suite and the REST suite
  against one server start (what the `server-faults` CI job now does, still 5 jobs); `make rest`, `make http` run all five.

### Unit tests (`test/server/rest/rest_server_test.dart`, 62)
IR and exclusion (GraphQL controller keeps only GraphQL fields, no controller for a REST-only service, service interface keeps REST methods, schema excludes REST and `Void`, REST-only `Query` stays valid), the
Java MVC, Java reactive, Kotlin blocking / suspend and Express output (annotations, parameters, conversions, `204`, JSON string vs text, `405`, `Mono`, `collectList`, no wildcard), and
six generation errors with their messages.

## Bugs found while doing it (all fixed unless noted)

| Where | Bug | Fix |
|---|---|---|
| Spring | A `String` result is written as bare text, not a JSON string | `GraphLinkRest.json` |
| Spring | `scalar Void` in the generated SDL fails graphql-java startup (no scalar wiring) | `Void` / `Download` scalars are not written to the server schema |
| Java reactive | `Mono<List<? extends Map<..>>>` does not accept `collectList()`'s `List<Map<..>>` | wildcard stripped for the reactive return type |
| Java / Kotlin | Java rejects `@GetMapping("/p", produces = "x")`, Kotlin rejects `produces = "x"` (array) | language hooks |
| Express | `req.body` is `{}` for an absent body; generated `fromJson` validates nothing; Express's `qs` makes `a[b]=c` an object | body-presence rule, shapes, `URLSearchParams` |
| Express | optional absent values were `undefined` where the service types say `null` | `null` |
| Express | `Void` was emitted as an undefined TS type `Void` | `void` |
| Spring MVC | The generated REST controller called the service with the schema's argument order; the service interface puts an upload last (does not compile) | call in the service field's order |
| Spring MVC | A non-multipart request to a `@RequestPart` method answered `500` (`MultipartException`) | controller-local `@ExceptionHandler` (`400`, `413`) |
| Spring WebFlux | A text field sent to a `FilePart` parameter: `argument type mismatch` `500`; a malformed multipart body: `DecodingException` `500`; an empty raw body: `400` | `Part` + `GraphLinkRest.filePart`, `@ExceptionHandler(DecodingException)`, optional raw body |
| Express | Files arrived in the order they finished writing, not the order of the request (`[Upload!]!` came back reversed) | indexed and sorted before they reach the service |
| Express | `GraphQLUpload`, `csrfPrevention: false` and the `Upload` scalar were generated for REST-only uploads; a nullable `Upload` was typed `FileUpload` | only when a GraphQL operation takes an upload; `FileUpload \| null` |
| test harness | `java_server_reactive` ran on the servlet stack (`spring-boot-starter-websocket`), where `FilePart` and `Flux<DataBuffer>` cannot be bound: the reactive upload code could not be tested | the server now runs on WebFlux (`spring-boot-starter-webflux`); GraphQL suites re-run, see Decisions |
| test harness (pre-existing) | `clients/{java,java_reactive,kotlin}_client` `Fixtures` called `DefaultGraphLinkClientAdapter(url, codec)`; the generated adapter takes `(url)` / `(url, headers)`, so the three harnesses did not compile | `Fixtures` fixed |
| test harness | `server.sh start` right after `stop` failed with "port held by a process this script did not start": Gradle's `bootRun` JVM outlives the process group that is killed | `start` waits up to 30 s for the previous owner to release the port |
| test side | graphql-java's "bad faith introspection" protection rejects a query using `__Type.fields` twice | two queries |

## Decisions to review

1. **A schema with `@glRest` operations generates REST endpoints in the server** (it used to generate GraphQL resolvers for them, which no client calls). That is the point of the work, but a project that shares one schema between a client of
   *someone else's* REST API and a GraphLink server will now get a controller for operations it does not serve. There is no opt-out switch. Say if you want one (`serverConfig.rest: false`).
2. **No `@ControllerAdvice` / error mapper was generated** (the earlier decision). REST errors are Spring Boot's default error JSON and the Express shape above. An exception thrown by a service, including a `@glValidate`
   `IllegalArgumentException`, is a `500`: the generated code cannot know that it means `400`.
3. **Status codes**: `200` for everything that returns a body (including `POST`), `204` for `Void`. `201` for creations would need a directive argument; the REST client accepts any `2xx`.
4. **`required` on a non-null argument means the value must be present**; a non-null argument with a default is optional and gets its default.
5. **`java_server_reactive` is now a WebFlux application.** It was `reactive: true` generated code on Spring MVC, which cannot run the generated upload code. Dart, TS, Kotlin, Java and Python clients pass against it, subscriptions included.
   Two GraphQL fault cases became known Spring GraphQL WebFlux defects: an empty body answers `200` (MVC: `400`), a body above the 256 KB codec limit a `500` (MVC: accepted up to Tomcat's limit).
6. The REST router is mounted at the application root with its own paths (`/products/{id}`), not under `graphqlPath`.

## Not done / limitations

* Rejected at generation time with a message: an input object as a multipart part (scalars, enums, lists of them and uploads work), a recursive input object in a query or form,
  lists of lists, custom scalars with a codec in path / query / header (decoded fine inside bodies). Everything else the REST client supports is served.
* Uploads: a Spring MVC envelope with **no boundary** answers `500` (known defect, `DispatcherServlet.checkMultipart` runs before any controller; needs a `@ControllerAdvice` or a filter). Size limits are the application's (`spring.servlet.multipart.*`, 1 MB default file size in Spring); the test servers set 50 MB. Not covered: the Express `maxFileSize` `413`, a client that disconnects mid-upload, many files in one request, `Content-Disposition` filenames with quotes or `\`, `Upload` in a reactive Kotlin server (there is none).
* WebFlux raw bodies and multipart are covered by the integration suite on `java_server_reactive` only; Spring Security / CORS are not.
* Spring converts some non-canonical booleans itself (`1`, `yes`, `on` are `true`); Express accepts only `true` / `false`. Only `maybe` is in the shared suite. Not measured, known Spring behaviour.
* Not covered: uploads (the TS upload server has no REST), Spring Security / CORS, `HEAD` and `OPTIONS`, content negotiation (`Accept`), request-size limits of REST routes (Express uses the global `express.json()` limit, 100 KB; Spring has no limit for JSON),
  batch-mapping and `@SchemaMapping` fields in a REST response (they are GraphQL resolvers: a REST operation must return a type whose fields the service fills in, the same limit as the REST client's `@glRestNullable` copies).
* `OpenAPI` output is not generated.
* The Swift client was not run against any server (needs Xcode); the CI job exists.
