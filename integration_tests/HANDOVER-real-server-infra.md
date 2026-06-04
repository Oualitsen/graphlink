# Handover: Real-server integration test infrastructure

## What was done

This session completed the Java and Kotlin upload integration tests and overhauled
the real-server test infrastructure (Makefiles, CI, server shutdown).

---

## 1. Java upload tests — `java_client_tests_real/`

### What changed
- `schema/schema.gql` — copy of the full mock schema with upload mutations returning
  `Boolean!` instead of `User!` (same as dart/typescript real tests)
- `config.json` — `schemaPaths` changed from `../dart_client_tests/schema/*.gql`
  to `schema/schema.gql` so regeneration uses the local modified schema
- Code regenerated — `UploadOneFileResponse` now wraps `Boolean getUploadOneFile()`
- `client-app/src/test/java/dev/graphlink/test/RealMultipartAdapter.java` — new;
  builds a `multipart/form-data` POST using Java 11 `HttpClient`
- `Fixtures.java` — added `UPLOAD_URL` constant and `newUploadClient()` factory
- `client-app/src/test/java/dev/graphlink/test/UploadTest.java` — new; 6 tests:
  3 × `uploadOneFile`, 3 × `uploadFileList`, all asserting `true` is returned

### GLUpload fields (Java)
```java
// constructor: (InputStream stream, long length, String filename, String mimeType)
u.getStream()    // InputStream
u.getLength()    // long
u.getFilename()  // String (nullable)
u.getMimeType()  // String
```

---

## 2. Kotlin upload tests — `kotlin_client_tests_real/`

### What changed
- `schema/schema.gql` — same modified schema as Java
- `config.json` — same `schemaPaths` change
- Code regenerated — `UploadOneFileResponse` now has `val uploadOneFile: Boolean`
- `client-app/src/test/kotlin/dev/graphlink/test/OkHttpMultipartAdapter.kt` — new;
  uses OkHttp 4 `MultipartBody.Builder`; reads `InputStream` via `readBytes()`
- `Fixtures.kt` — added `UPLOAD_URL` constant and `newUploadClient()` factory
- `client-app/src/test/kotlin/dev/graphlink/test/UploadTest.kt` — new; 6 tests,
  same structure as Java

### GLUpload fields (Kotlin)
```kotlin
// data class GLUpload(stream: InputStream, mimeType: String, length: Long, filename: String? = null)
upload.stream    // InputStream  ← NOT ByteArray (handover doc was wrong)
upload.mimeType  // String
upload.length    // Long
upload.filename  // String?
```

### GraphLinkClient constructor order (Kotlin)
```kotlin
GraphLinkClient(adapter, wsAdapter, multipartAdapter, encoder, decoder)
```

---

## 3. Server shutdown — actuator endpoint

Both Spring servers now expose `POST /actuator/shutdown` for graceful stop.

### What changed in the servers
- `spring_server/build.gradle.kts` — added `spring-boot-starter-actuator`
- `spring_upload_server/build.gradle.kts` — same
- `spring_server/src/main/resources/application.yml` — enabled shutdown endpoint:
  ```yaml
  management:
    endpoint:
      shutdown:
        enabled: true
    endpoints:
      web:
        exposure:
          include: shutdown
  ```
- `spring_upload_server/src/main/resources/application.yml` — same
- Both JARs rebuilt after these changes

### Usage
```bash
curl -s -X POST http://localhost:9999/actuator/shutdown   # test server
curl -s -X POST http://localhost:9998/actuator/shutdown   # upload server
```
Returns `{"message":"Shutting down, bye..."}` and exits. Safe to call when the
server is not running — curl returns connection refused, `|| true` suppresses it.

---

## 4. Makefile pattern (all four real-test suites)

`start-server` shuts down any existing instance before starting fresh:
```make
start-server:
	curl -s -X POST http://localhost:9999/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9999/actuator/shutdown || true

start-upload-server:
	curl -s -X POST http://localhost:9998/actuator/shutdown || true
	sleep 2
	java -jar $(UPLOAD_SERVER_JAR) &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9998/actuator/shutdown || true

ci: start-server start-upload-server generate test stop-server stop-upload-server
```

The two `sleep` values:
- `sleep 2` after shutdown — lets the OS release the port before the new process binds
- `sleep 6` after start — gives Spring Boot time to be fully ready before tests run

---

## 5. Top-level `integration_tests/Makefile`

Added `upload-server` build target and `all-real` convenience target:
```make
upload-server:
	$(MAKE) -C spring_upload_server build

all-real: dart-real typescript-real java-real kotlin-real
```

Run all real-server suites sequentially:
```bash
cd integration_tests && make all-real
```

---

## 6. CI — `.github/workflows/ci.yml`

Added five missing jobs:

| Job | Notes |
|---|---|
| `integration-tests-kotlin-client` | mock-adapter Kotlin tests (was absent) |
| `integration-tests-dart-real` | builds both JARs, then `make ci` |
| `integration-tests-typescript-real` | adds Node 20, builds both JARs |
| `integration-tests-java-real` | builds both JARs, then `make ci` |
| `integration-tests-kotlin-real` | builds both JARs, then `make ci` |

Each real-server job builds both servers before running:
```yaml
- name: Build servers
  run: |
    cd ../spring_server && ./gradlew build -x test
    cd ../spring_upload_server && ./gradlew build -x test
```

The JARs do not exist on a fresh checkout — this build step is required.

---

## Things to watch for

**Server startup time**: `sleep 6` has been enough locally. On a slow CI runner it
may need to be increased. If tests fail with connection-refused errors, bump it to 10.

**Port conflicts in CI**: Each job runs in its own VM so there is no conflict between
jobs. Locally, `make all-real` runs suites sequentially and each suite shuts down
both servers before the next one starts — no conflicts there either.

**Schema path**: All four real-test `config.json` files now point to a local
`schema/schema.gql` inside their own directory. If the mock schema
(`dart_client_tests/schema/schema.gql`) gains new types, those changes need to be
manually synced to the four local copies **and** the upload mutation return types must
stay as `Boolean!` (not `User!`).
