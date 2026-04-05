# File Upload Support

## Overview

Add `@glUpload` directive support across the full GraphLink pipeline: directive parsing, IR enrichment, config surface, and code generation for Dart (Dio + http), Java (OkHttp + Java 11 HttpClient), and Spring Boot server.

Transport: **GraphQL multipart request spec** (Jayden Seric).

---

## 1. Schema / Directive Parsing

### 1.1 Directive Definition

Inject as a built-in — users do not declare it:

```graphql
directive @glUpload on SCALAR
```

### 1.2 Scalar IR Enrichment

Extend the scalar IR node with an `isUpload` flag:

```dart
class ScalarType {
  final String name;
  final bool isUpload; // true when @glUpload is present
}
```

When converting `ScalarTypeDefinitionNode` → IR, inspect `node.directives` for `name.value == 'glUpload'`.

### 1.3 Type Resolver Propagation

The function that maps a GraphQL type name to a language type string must:
- Accept/query full scalar metadata, not just the name
- Unwrap NonNull and List wrappers to reach the scalar and check `isUpload`
- Emit the upload-specific type (see per-target sections below)

### 1.4 Mutation-Level Upload Detection

```dart
bool mutationHasUploads(MutationDefinition mutation, TypeRegistry registry) {
  return mutation.variables.any((v) => isUploadType(v.type, registry));
}

bool isUploadType(TypeRef typeRef, TypeRegistry registry) {
  final unwrapped = typeRef.unwrapNonNull().unwrapList().unwrapNonNull();
  if (unwrapped is NamedTypeRef) {
    return registry.lookupScalar(unwrapped.name)?.isUpload ?? false;
  }
  return false;
}
```

Drives: multipart transport switch, `onProgress` param emission, wrapper class generation.

**v1 constraint:** Only direct mutation variable args are supported. Nested uploads inside input object fields are unsupported — document as a known limitation, planned for v2.

---

## 2. Config Changes

New `uploadOptions` block:

```json
{
  "uploadOptions": {
    "generateProgressCallback": true,
    "javaUploadRepresentation": "inputstream"
  }
}
```

| Key | Default | Description |
|---|---|---|
| `generateProgressCallback` | `true` | Emit `onProgress` param on upload mutations |
| `javaUploadRepresentation` | `"inputstream"` | `"inputstream"` / `"file"` / `"bytes"` |

The `dartUploadType` key is not needed — it inherits from the existing adapter config.

---

## 3. Dart Codegen

### 3.1 Type Mapping

| Adapter | `Upload` scalar | `[Upload!]!` |
|---|---|---|
| Dio | `MultipartFile` | `List<MultipartFile>` |
| http | `http.MultipartFile` | `List<http.MultipartFile>` |

### 3.2 Progress Callback

Emitted once per generated client file when any mutation has uploads:

```dart
typedef UploadProgressCallback = void Function(int sent, int total);
```

### 3.3 Generated Method Signature

```dart
Future<UploadAvatarMutation$Data> uploadAvatar({
  required MultipartFile file,
  required String userId,
  required String caption,
  UploadProgressCallback? onProgress,  // omitted when generateProgressCallback: false
}) async { ... }
```

### 3.4 Multipart Request — Dio Adapter

Dio's `onSendProgress` matches the callback shape — no wrapper class needed.

```dart
final operations = jsonEncode({
  'query': _uploadAvatarDocument,
  'variables': {'file': null, 'userId': userId, 'caption': caption},
});
final map = jsonEncode({'0': ['variables.file']});

final formData = FormData.fromMap({
  'operations': operations,
  'map': map,
  '0': file,
});

final response = await _dio.post(
  _endpoint,
  data: formData,
  onSendProgress: onProgress != null ? (sent, total) => onProgress(sent, total) : null,
);
```

**List of files:**
```dart
final mapEntries = {for (var i = 0; i < files.length; i++) '$i': ['variables.files.$i']};
final formData = FormData.fromMap({
  'operations': jsonEncode({
    'query': _uploadDocumentsDocument,
    'variables': {'files': List.filled(files.length, null), 'label': label},
  }),
  'map': jsonEncode(mapEntries),
  ...{for (var i = 0; i < files.length; i++) '$i': files[i]},
});
```

### 3.5 Multipart Request — http Adapter

No native progress support. A byte-counting wrapper is generated once per file:

```dart
// Generated helper — emitted once when http adapter + upload mutations present
class _CountingStreamedRequest extends http.BaseRequest {
  final Stream<List<int>> _stream;
  final UploadProgressCallback? _onProgress;
  final int _total;

  _CountingStreamedRequest(String method, Uri url, this._stream, this._onProgress, this._total)
      : super(method, url);

  @override
  http.ByteStream finalize() {
    int sent = 0;
    final counting = _stream.map((chunk) {
      sent += chunk.length;
      _onProgress?.call(sent, _total);
      return chunk;
    });
    return http.ByteStream(counting);
  }
}
```

Files are buffered to compute total length before streaming. **Document:** for large files prefer the Dio adapter.

`http.MultipartFile` field naming: use the `field` constructor parameter (`'0'`, `'1'`, ...) — not post-construction rename.

---

## 4. Java Codegen

### 4.1 Upload Type

**Recommended: `InputStream` + companion `long contentLength` (`-1` = unknown).**

| Type | Verdict |
|---|---|
| `File` | Ties to filesystem — not suitable for in-memory or streamed data |
| `byte[]` | Entire file in memory, no streaming |
| `InputStream` | ✓ Universal, streams from any source; use `-1` for unknown length |

### 4.2 Progress Callback

Emitted once per generated client file when any mutation has uploads:

```java
@FunctionalInterface
public interface UploadProgressCallback {
    void onProgress(long sent, long total);
}
```

### 4.3 Generated Method Signature

```java
public UploadAvatarMutation.Response uploadAvatar(
        InputStream file,
        long fileContentLength,
        String userId,
        String caption,
        /* @Nullable */ UploadProgressCallback onProgress) throws IOException { ... }

// List variant
public UploadDocumentsMutation.Response uploadDocuments(
        List<InputStream> files,
        List<Long> filesContentLengths,  // parallel list; -1 for unknown
        String label,
        /* @Nullable */ UploadProgressCallback onProgress) throws IOException { ... }
```

`onProgress` is placed last, always nullable. Omitted entirely when `generateProgressCallback: false`.

### 4.4 OkHttp Adapter

Generated `ProgressRequestBody` inner class (once per client file when needed):

```java
private static final class ProgressRequestBody extends RequestBody {
    private final RequestBody delegate;
    private final UploadProgressCallback callback;

    ProgressRequestBody(RequestBody delegate, UploadProgressCallback callback) {
        this.delegate = delegate;
        this.callback = callback;
    }

    @Override public MediaType contentType() { return delegate.contentType(); }
    @Override public long contentLength() throws IOException { return delegate.contentLength(); }

    @Override
    public void writeTo(BufferedSink sink) throws IOException {
        final long total = contentLength();
        final long[] sent = {0};
        BufferedSink countingSink = Okio.buffer(new ForwardingSink(sink) {
            @Override public void write(Buffer source, long byteCount) throws IOException {
                super.write(source, byteCount);
                sent[0] += byteCount;
                callback.onProgress(sent[0], total);
            }
        });
        delegate.writeTo(countingSink);
        countingSink.flush();
    }
}
```

Generated mutation body:

```java
String operations = gson.toJson(Map.of(
    "query", UPLOAD_AVATAR_DOCUMENT,
    "variables", Map.of("file", null, "userId", userId, "caption", caption)
));
String mapJson = gson.toJson(Map.of("0", List.of("variables.file")));

RequestBody fileBody = new RequestBody() {
    @Override public MediaType contentType() { return MediaType.parse("application/octet-stream"); }
    @Override public long contentLength() { return fileContentLength; }
    @Override public void writeTo(BufferedSink sink) throws IOException {
        sink.writeAll(Okio.source(file));
    }
};

RequestBody uploadBody = onProgress != null ? new ProgressRequestBody(fileBody, onProgress) : fileBody;

MultipartBody body = new MultipartBody.Builder()
    .setType(MultipartBody.FORM)
    .addFormDataPart("operations", operations)
    .addFormDataPart("map", mapJson)
    .addFormDataPart("0", "upload", uploadBody)
    .build();
```

### 4.5 Java 11 HttpClient Adapter

Generated `CountingBodyPublisher` wrapper:

```java
private static final class CountingBodyPublisher implements HttpRequest.BodyPublisher {
    private final HttpRequest.BodyPublisher delegate;
    private final UploadProgressCallback callback;

    CountingBodyPublisher(HttpRequest.BodyPublisher delegate, UploadProgressCallback callback) {
        this.delegate = delegate;
        this.callback = callback;
    }

    @Override public long contentLength() { return delegate.contentLength(); }

    @Override
    public void subscribe(Flow.Subscriber<? super ByteBuffer> subscriber) {
        delegate.subscribe(new Flow.Subscriber<>() {
            long sent = 0;
            final long total = delegate.contentLength();
            @Override public void onSubscribe(Flow.Subscription sub) { subscriber.onSubscribe(sub); }
            @Override public void onNext(ByteBuffer item) {
                sent += item.remaining();
                callback.onProgress(sent, total);
                subscriber.onNext(item);
            }
            @Override public void onError(Throwable t) { subscriber.onError(t); }
            @Override public void onComplete() { subscriber.onComplete(); }
        });
    }
}
```

Java 11 `HttpClient` has no built-in multipart support. Generate a `buildMultipartBody(...)` helper that writes MIME parts manually (boundary + headers + binary). **Document:** entire body is buffered in `ByteArrayOutputStream` — streaming implementation planned for v2.

### 4.6 List Upload Progress Edge Case

With multiple files and a single callback, each `ProgressRequestBody` / `CountingBodyPublisher` fires independently — `sent` resets per file. **v1 behavior: per-file progress.** Document explicitly. Aggregate callback planned for v2.

---

## 5. Spring Boot Server Codegen

### 5.1 Type Mapping

| GraphQL type | MVC (default) | WebFlux (`reactive: true`) |
|---|---|---|
| `Upload` | `MultipartFile` | `FilePart` |
| `[Upload!]!` | `List<MultipartFile>` | `Flux<FilePart>` |

### 5.2 Service Interface

```java
import org.springframework.web.multipart.MultipartFile;

public interface MutationService {
    User uploadAvatar(MultipartFile file, String userId, String caption);
    Document uploadDocuments(List<MultipartFile> files, String label);
}
```

No progress callback on the server side.

### 5.3 Controller

```java
@Controller
public class MutationController {

    @MutationMapping
    public User uploadAvatar(
            @Argument MultipartFile file,
            @Argument String userId,
            @Argument String caption) {
        return mutationService.uploadAvatar(file, userId, caption);
    }
}
```

`@MutationMapping` is unchanged. Spring for GraphQL 1.x+ handles multipart binding automatically via `@Argument` — no `@RequestParam` / `@RequestPart` needed.

### 5.4 Required User Config (documented, not generated)

```yaml
spring:
  servlet:
    multipart:
      enabled: true
      max-file-size: 10MB
      max-request-size: 10MB
```

---

## 6. Build Order

1. Directive injection + `isUpload` IR flag + unit tests
2. Config model (`UploadOptions` class + defaults)
3. Type resolver updates (Dart + Java) + unit tests
4. `mutationHasUploads` helper + unit tests
5. Spring Boot server codegen (simplest — no wrappers, no progress)
6. Dart / Dio codegen
7. Dart / http codegen (byte-counting wrapper)
8. Java / OkHttp codegen (`ProgressRequestBody`)
9. Java / Java 11 HttpClient codegen (`CountingBodyPublisher` + manual multipart)
10. Integration tests per target (mock multipart server validating spec-correct request shape)
11. Docs + `llms.txt` updates

---

## 7. Known Limitations (v1)

| Limitation | Planned |
|---|---|
| Nested input object uploads (`input Foo { file: Upload! }`) | v2 |
| Java 11 HttpClient buffers entire upload in memory | v2 streaming |
| List upload progress is per-file, not aggregate | v2 aggregate callback |
| `contentLength = -1` gives indeterminate progress | Documented behavior |
