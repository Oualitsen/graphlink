import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';

const javaRestBody = r'''
public abstract class RestBody {
    private RestBody() {}

    public static final class Json extends RestBody {
        private final String json;

        public Json(String json) { this.json = json; }

        public String getJson() { return json; }
    }

    public static final class Form extends RestBody {
        private final List<Map.Entry<String, String>> fields;

        public Form(List<Map.Entry<String, String>> fields) { this.fields = fields; }

        public List<Map.Entry<String, String>> getFields() { return fields; }
    }

    public static final class Multipart extends RestBody {
        private final List<RestPart> parts;

        public Multipart(List<RestPart> parts) { this.parts = parts; }

        public List<RestPart> getParts() { return parts; }

        public GLMultipartBody toBody() {
            List<GLMultipartBody.Part> converted = new java.util.ArrayList<>();
            for (RestPart part : parts) {
                converted.add(part.getFile() != null
                    ? GLMultipartBody.Part.file(part.getName(), part.getFile())
                    : GLMultipartBody.Part.text(part.getName(), part.getValue(), part.getMimeType()));
            }
            return GLMultipartBody.of(converted);
        }
    }

    public static final class Raw extends RestBody {
        private final GLUpload upload;

        public Raw(GLUpload upload) { this.upload = upload; }

        public GLUpload getUpload() { return upload; }
    }
}
''';

const javaRestPart = r'''
public final class RestPart {
    private final String name;
    private final String value;
    private final GLUpload file;
    private final String mimeType;

    private RestPart(String name, String value, GLUpload file, String mimeType) {
        this.name = name;
        this.value = value;
        this.file = file;
        this.mimeType = mimeType;
    }

    public static RestPart text(String name, String value) { return new RestPart(name, value, null, null); }

    public static RestPart text(String name, String value, String mimeType) { return new RestPart(name, value, null, mimeType); }

    public static RestPart file(String name, GLUpload file) { return new RestPart(name, null, file, null); }

    public String getName() { return name; }
    public String getValue() { return value; }
    public GLUpload getFile() { return file; }
    public String getMimeType() { return mimeType; }
}
''';

const javaRestRequest = r'''
public final class RestRequest {
    private final String method;
    private final String path;
    private final List<Map.Entry<String, String>> query;
    private final Map<String, String> headers;
    private final RestBody body;
    private final UploadProgressCallback onSendProgress;
    private final boolean streamResponse;

    public RestRequest(
            String method,
            String path,
            List<Map.Entry<String, String>> query,
            Map<String, String> headers,
            RestBody body,
            UploadProgressCallback onSendProgress,
            boolean streamResponse) {
        this.method = method;
        this.path = path;
        this.query = query;
        this.headers = headers;
        this.body = body;
        this.onSendProgress = onSendProgress;
        this.streamResponse = streamResponse;
    }

    public String getMethod() { return method; }
    public String getPath() { return path; }
    public List<Map.Entry<String, String>> getQuery() { return query; }
    public Map<String, String> getHeaders() { return headers; }
    public RestBody getBody() { return body; }
    public UploadProgressCallback getOnSendProgress() { return onSendProgress; }

    /** True when the caller consumes the body as a stream (downloads); otherwise an adapter may buffer it. */
    public boolean isStreamResponse() { return streamResponse; }
}
''';

const javaRestResponse = r'''
public final class RestResponse implements Closeable {
    private final int status;
    private final InputStream stream;
    private final Map<String, String> headers;

    public RestResponse(int status, InputStream stream, Map<String, String> headers) {
        this.status = status;
        this.stream = stream;
        this.headers = headers;
    }

    public static RestResponse ofText(int status, String text, Map<String, String> headers) {
        return new RestResponse(status, new ByteArrayInputStream(text.getBytes(StandardCharsets.UTF_8)), headers);
    }

    public static RestResponse ofText(int status, String text) {
        return ofText(status, text, Collections.emptyMap());
    }

    public int getStatus() { return status; }
    public InputStream getStream() { return stream; }
    public Map<String, String> getHeaders() { return headers; }

    public boolean isSuccess() { return status >= 200 && status < 300; }

    public byte[] bytes() {
        try (InputStream in = stream) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public String text() {
        String value = new String(bytes(), StandardCharsets.UTF_8);
        return !value.isEmpty() && value.charAt(0) == 0xFEFF ? value.substring(1) : value;
    }

    public void drain() {
        try (InputStream in = stream) {
            in.transferTo(OutputStream.nullOutputStream());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public void close() {
        try {
            stream.close();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
''';

const javaRestError = r'''
public class RestError extends RuntimeException {
    private final int status;
    private final Map<String, String> headers;
    private final String body;

    public RestError(int status, Map<String, String> headers, String body) {
        super("RestError(" + status + "): " + body);
        this.status = status;
        this.headers = headers;
        this.body = body;
    }

    public int getStatus() { return status; }
    public Map<String, String> getHeaders() { return headers; }
    public String getBody() { return body; }
}
''';

const javaDownloadProgressCallback = r'''
@FunctionalInterface
public interface DownloadProgressCallback {
    void onProgress(long received, long total);
}
''';

const javaGLDownload = r'''
public final class GLDownload implements Closeable {
    private static final Pattern FILENAME = Pattern.compile("filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?", Pattern.CASE_INSENSITIVE);

    private final InputStream stream;
    private final String filename;
    private final String contentType;
    private final long length;

    public GLDownload(InputStream stream, String filename, String contentType, long length) {
        this.stream = stream;
        this.filename = filename;
        this.contentType = contentType;
        this.length = length;
    }

    public InputStream getStream() { return stream; }
    public String getFilename() { return filename; }
    public String getContentType() { return contentType; }

    /** The Content-Length of the response, or -1 when unknown. */
    public long getLength() { return length; }

    public byte[] bytes() {
        try (InputStream in = stream) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public void close() {
        try {
            stream.close();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public static GLDownload fromResponse(RestResponse response, DownloadProgressCallback onProgress) {
        String lengthHeader = header(response, "content-length");
        long length = -1L;
        if (lengthHeader != null) {
            try {
                length = Long.parseLong(lengthHeader.trim());
            } catch (NumberFormatException ignored) {
                length = -1L;
            }
        }
        InputStream stream = onProgress == null ? response.getStream() : new CountingInputStream(response.getStream(), length, onProgress);
        String disposition = header(response, "content-disposition");
        String name = null;
        if (disposition != null) {
            Matcher matcher = FILENAME.matcher(disposition);
            if (matcher.find()) {
                String raw = matcher.group(1);
                try {
                    name = URLDecoder.decode(raw.replace("+", "%2B"), StandardCharsets.UTF_8);
                } catch (IllegalArgumentException e) {
                    name = raw;
                }
            }
        }
        return new GLDownload(stream, name, header(response, "content-type"), length);
    }

    private static String header(RestResponse response, String name) {
        for (Map.Entry<String, String> entry : response.getHeaders().entrySet()) {
            if (entry.getKey().equalsIgnoreCase(name)) return entry.getValue();
        }
        return null;
    }

    private static final class CountingInputStream extends InputStream {
        private final InputStream delegate;
        private final long total;
        private final DownloadProgressCallback callback;
        private long received = 0L;

        CountingInputStream(InputStream delegate, long total, DownloadProgressCallback callback) {
            this.delegate = delegate;
            this.total = total;
            this.callback = callback;
        }

        @Override
        public int read() throws IOException {
            int value = delegate.read();
            if (value >= 0) report(1);
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int count = delegate.read(buffer, offset, length);
            if (count > 0) report(count);
            return count;
        }

        @Override
        public void close() throws IOException { delegate.close(); }

        private void report(long count) {
            received += count;
            callback.onProgress(received, total);
        }
    }
}
''';

const javaRestUtils = r'''
public final class GraphLinkRestUtils {
    private GraphLinkRestUtils() {}

    public static String restEncode(String value) {
        StringBuilder out = new StringBuilder();
        for (byte b : value.getBytes(StandardCharsets.UTF_8)) {
            int c = b & 0xFF;
            boolean unreserved = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
                    || c == '-' || c == '_' || c == '.' || c == '~';
            if (unreserved) {
                out.append((char) c);
            } else {
                out.append('%').append(String.format("%02X", c));
            }
        }
        return out.toString();
    }

    public static String restEncodeQuery(String value) {
        return restEncode(value).replace("%20", "+");
    }

    private static String restText(Object value) {
        return value instanceof String ? (String) value : value.toString();
    }

    private static void restCollect(List<Map.Entry<String, String>> out, String key, Object value, boolean bracket, boolean comma, boolean inList) {
        if (value == null) return;
        if (value instanceof Map) {
            Map<String, Object> sorted = new TreeMap<>();
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) sorted.put(String.valueOf(entry.getKey()), entry.getValue());
            for (Map.Entry<String, Object> entry : sorted.entrySet()) {
                restCollect(out, bracket ? key + "[" + entry.getKey() + "]" : key + "." + entry.getKey(), entry.getValue(), bracket, comma, false);
            }
        } else if (value instanceof List) {
            List<?> list = (List<?>) value;
            List<Object> items = new ArrayList<>();
            boolean scalars = true;
            for (Object item : list) {
                if (item == null) continue;
                items.add(item);
                if (item instanceof Map || item instanceof List) scalars = false;
            }
            if (items.isEmpty()) return;
            if (!inList && scalars) {
                if (comma) {
                    StringJoiner joiner = new StringJoiner(",");
                    for (Object item : items) joiner.add(restText(item));
                    out.add(Map.entry(key, joiner.toString()));
                } else {
                    for (Object item : items) out.add(Map.entry(key, restText(item)));
                }
            } else {
                for (int i = 0; i < list.size(); i++) {
                    restCollect(out, bracket ? key + "[" + i + "]" : key + "." + i, list.get(i), bracket, comma, true);
                }
            }
        } else {
            out.add(Map.entry(key, restText(value)));
        }
    }

    public static List<Map.Entry<String, String>> restEntries(String key, Object value, boolean bracket, boolean comma) {
        List<Map.Entry<String, String>> out = new ArrayList<>();
        restCollect(out, key, value, bracket, comma, false);
        return out;
    }

    public static List<Map.Entry<String, String>> restEntries(String key, Object value) {
        return restEntries(key, value, false, false);
    }

    public static List<Map.Entry<String, String>> restSpreadEntries(Object json, Map<String, String> names, boolean bracket, boolean comma) {
        List<Map.Entry<String, String>> out = new ArrayList<>();
        if (json instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) json;
            for (Map.Entry<String, String> name : names.entrySet()) {
                restCollect(out, name.getValue(), map.get(name.getKey()), bracket, comma, false);
            }
        }
        return out;
    }

    public static Map<String, String> restNames(String... pairs) {
        Map<String, String> out = new LinkedHashMap<>();
        for (int i = 0; i + 1 < pairs.length; i += 2) out.put(pairs[i], pairs[i + 1]);
        return out;
    }

    public static String restHeaderValue(Object value) {
        if (value instanceof List) {
            StringJoiner joiner = new StringJoiner(",");
            for (Object item : (List<?>) value) {
                if (item != null) joiner.add(restText(item));
            }
            return joiner.toString();
        }
        return restText(value);
    }

    public static Map<String, String> restHeader(String name, Object value) {
        if (value == null) return Collections.emptyMap();
        return Collections.singletonMap(name, restHeaderValue(value));
    }

    public static Map<String, String> restHeaders(Object json, Map<String, String> names) {
        Map<String, String> out = new LinkedHashMap<>();
        if (json instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) json;
            for (Map.Entry<String, String> name : names.entrySet()) {
                Object value = map.get(name.getKey());
                if (value != null) out.put(name.getValue(), restHeaderValue(value));
            }
        }
        return out;
    }

    @SafeVarargs
    public static Map<String, String> restMerge(Map<String, String>... maps) {
        Map<String, String> out = new LinkedHashMap<>();
        for (Map<String, String> map : maps) out.putAll(map);
        return out;
    }

    @SafeVarargs
    public static <T> List<T> restConcat(List<? extends T>... lists) {
        List<T> out = new ArrayList<>();
        for (List<? extends T> list : lists) out.addAll(list);
        return out;
    }

    public static List<RestPart> restParts(List<Map.Entry<String, String>> entries) {
        List<RestPart> out = new ArrayList<>();
        for (Map.Entry<String, String> entry : entries) out.add(RestPart.text(entry.getKey(), entry.getValue()));
        return out;
    }

    public static Object restNavigate(Object json, List<String> path) {
        Object current = json;
        for (String segment : path) {
            current = current instanceof Map ? ((Map<?, ?>) current).get(segment) : null;
        }
        return current;
    }
}
''';

String javaRestAdapterInterface(JavaReactiveFlavor flavor) => '''
@FunctionalInterface
public interface GLRestAdapter {
    ${flavor.singleType('RestResponse')} execute(RestRequest request);
}
''';

String javaNoGraphQLAdapter(JavaReactiveFlavor flavor, {required bool operationName}) {
  final params = operationName ? 'String payload, String operationName' : 'String payload';
  const failure = 'new IllegalStateException("This schema has no GraphQL operation: pass no GraphQL adapter")';
  return '''
public final class GraphLinkNoGraphQL implements GraphLinkClientAdapter {
    @Override
    public ${flavor.singleType('String')} execute($params) {
        ${flavor.isReactive ? 'return ${flavor.error(failure)};' : 'throw $failure;'}
    }
}
''';
}


String _lambdaBlock(String header, List<String> lines) => '$header\n${lines.join('\n').ident()}\n});';

String _method(String signature, List<String> body) => '$signature {\n${body.join('\n').ident()}\n}';

String _braces(String header, List<String> lines) => '$header {\n${lines.join('\n').ident()}\n}';

class _ValueOp {
  final String name;
  final String typeParams;
  final String resultType;
  final String extraParams;
  final String decodeParam;
  final List<String> read;
  final List<String> readOrNull;
  final String apply;

  const _ValueOp({
    required this.name,
    this.typeParams = '',
    required this.resultType,
    this.extraParams = '',
    this.decodeParam = '',
    required this.read,
    List<String>? readOrNull,
    required this.apply,
  }) : readOrNull = readOrNull ?? read;
}

String _valueOps(JavaReactiveFlavor flavor, _ValueOp op) {
  final params = 'RestRequest request${op.extraParams}${op.decodeParam}, Runnable afterSuccess';
  const empty =
      'throw new IllegalStateException("Empty REST response for a non-null result of " + request.getMethod() + " " + request.getPath());';
  List<String> tail(List<String> read, {required bool nullable}) => [
        ...read,
        if (!nullable) _braces('if (value == null)', [empty]),
        '${op.resultType} result = ${op.apply};',
        'afterSuccess.run();',
      ];

  if (!flavor.isReactive) {
    return [
      _method('protected ${op.typeParams}${op.resultType} ${op.name}($params)', [
        'RestResponse response = restCall(request);',
        ...tail(op.read, nullable: false),
        'return result;',
      ]),
      _method('protected ${op.typeParams}${op.resultType} ${op.name}OrNull($params)', [
        'RestResponse response = restCall(request);',
        ...tail(op.readOrNull, nullable: true),
        'return result;',
      ]),
    ].join('\n\n');
  }
  return [
    _method('protected ${op.typeParams}${flavor.singleType(op.resultType)} ${op.name}($params)', [
      'return ${_lambdaBlock(flavor.mapOpen('restCall(request)', 'response'), [...tail(op.read, nullable: false), 'return result;'])}',
    ]),
    _method('protected ${op.typeParams}${flavor.maybeType(op.resultType)} ${op.name}OrNull($params)', [
      'return ${_lambdaBlock(flavor.flatMapToMaybeOpen('restCall(request)', 'response'), [...tail(op.readOrNull, nullable: true), 'return ${flavor.maybeOf('result')};'])}',
    ]),
  ].join('\n\n');
}

String javaRestResolver(JavaReactiveFlavor flavor, {required bool withGetAdapter}) {
  final r = flavor.isReactive;
  final fetchType = flavor.singleType('Optional<Object>');
  const staleRead = 'decode.apply(glDecoder__.decode(cached.data).get("__gl_v__"))';

  final constructor = _braces(
    'protected GraphLinkRestResolver(\n${[
      'GraphLinkClientAdapter adapter',
      if (withGetAdapter) 'GraphLinkClientAdapter getAdapter',
      'GLRestAdapter restAdapter',
      'Map<String, String> fragmentMap',
      'GraphLinkCacheStore store',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
    ].join(',\n').ident().ident()}\n)',
    [
      'super(adapter, ${withGetAdapter ? 'getAdapter, ' : ''}fragmentMap, store, encoder, decoder);',
      'this.restAdapter = restAdapter;',
    ],
  );

  final restCall = r
      ? [
          _method('protected ${flavor.singleType('RestResponse')} restCall(RestRequest request)', [
            'return ${flavor.flatMap('restAdapter.execute(request)', 'response -> restChecked(response)')};',
          ]),
          _method('private ${flavor.singleType('RestResponse')} restChecked(RestResponse response)', [
            _braces('if (response.isSuccess())', ['return ${flavor.wrapValue('response')};']),
            'return ${flavor.error('new RestError(response.getStatus(), response.getHeaders(), response.text())')};',
          ]),
        ].join('\n\n')
      : _method('protected RestResponse restCall(RestRequest request)', [
          'RestResponse response = restAdapter.execute(request);',
          _braces('if (!response.isSuccess())', [
            'throw new RestError(response.getStatus(), response.getHeaders(), response.text());',
          ]),
          'return response;',
        ]);

  final voidOp = r
      ? _method('protected ${flavor.voidType} restVoid(RestRequest request, Runnable afterSuccess)', [
          'return ${_lambdaBlock(flavor.flatMapToVoidOpen('restCall(request)', 'response'), [
                'response.drain();',
                'afterSuccess.run();',
                'return ${flavor.voidDone};',
              ])}',
        ])
      : _method('protected void restVoid(RestRequest request, Runnable afterSuccess)', [
          'restCall(request).drain();',
          'afterSuccess.run();',
        ]);

  final jsonOps = _valueOps(
    flavor,
    const _ValueOp(
      name: 'restJson',
      typeParams: '<T> ',
      resultType: 'T',
      extraParams: ', List<String> path',
      decodeParam: ', Function<Object, T> decode',
      read: ['Object value = restParse(response, path);'],
      apply: 'decode.apply(value)',
    ),
  );
  final textOps = _valueOps(
    flavor,
    const _ValueOp(
      name: 'restText',
      resultType: 'String',
      read: ['String value = response.text();'],
      readOrNull: ['String value = response.text();', 'if (value.isEmpty()) {\n    value = null;\n}'],
      apply: 'value',
    ),
  );
  final downloadOps = _valueOps(
    flavor,
    const _ValueOp(
      name: 'restDownload',
      resultType: 'GLDownload',
      extraParams: ', DownloadProgressCallback onProgress',
      read: ['GLDownload value = restDownloadOf(response, onProgress);'],
      apply: 'value',
    ),
  );

  final fetch = r
      ? _method('protected $fetchType restFetch(RestRequest request, List<String> path, boolean allowEmpty)', [
          'return ${flavor.mapTo('restCall(request)', 'response -> restFetched(request, restParse(response, path), allowEmpty)')};',
        ])
      : _method('protected Optional<Object> restFetch(RestRequest request, List<String> path, boolean allowEmpty)', [
          'return restFetched(request, restParse(restCall(request), path), allowEmpty);',
        ]);

  String cachedSignature(String returnType, String fetchArg) => 'protected <T> $returnType restCached(\n${[
        'String name',
        'Map<String, Object> variables',
        'long ttl',
        'List<String> tags',
        'boolean staleIfOffline',
        fetchArg,
        'Function<Object, T> decode',
      ].join(',\n').ident().ident()}\n)';

  final storeBody = [
    'Object json = fetched.orElse(null);',
    'T value = decode.apply(json);',
    _braces('if (json != null)', [
      'Map<String, Object> wrapper = new HashMap<>();',
      'wrapper.put("__gl_v__", json);',
      'GraphLinkCacheEntry entry = new GraphLinkCacheEntry(glEncoder__.encode(wrapper), System.currentTimeMillis() + ttl * 1000L);',
      'glStore__.set(key, glEncoder__.encode(entry.toJson()));',
      _braces('if (!tags.isEmpty())', ['addKeyToTags(key, tags);']),
    ]),
    'return value;',
  ];

  final cached = r
      ? [
          _method(cachedSignature(flavor.singleType('T'), 'Supplier<$fetchType> fetch'), [
            'String key = GraphLinkPartialQuery.computeCacheKey(name, variables, glEncoder__);',
            'GraphLinkCacheEntry cached = getFromCache(key, tags, staleIfOffline);',
            _braces('if (cached != null && !cached.stale)', ['return ${flavor.wrapValue(staleRead)};']),
            'return ${_lambdaBlock(flavor.onErrorResumeOpen(flavor.mapTo('fetch.get()', 'fetched -> restStore(key, ttl, tags, fetched, decode)'), 'failure'), [
                  _braces('if (failure instanceof RestError || cached == null)', ['return ${flavor.error('failure')};']),
                  'return ${flavor.wrapValue(staleRead)};',
                ])}',
          ]),
          _method(cachedSignature(flavor.maybeType('T'), 'Supplier<$fetchType> fetch').replaceFirst('restCached', 'restCachedOrNull'), [
            'return ${_lambdaBlock(
              flavor.flatMapToMaybeOpen('restCached(name, variables, ttl, tags, staleIfOffline, fetch, json -> Optional.ofNullable(decode.apply(json)))', 'cached'),
              ['return ${flavor.maybeOf('cached.orElse(null)')};'],
            )}',
          ]),
          _method('private <T> T restStore(String key, long ttl, List<String> tags, Optional<Object> fetched, Function<Object, T> decode)', storeBody),
        ].join('\n\n')
      : _method(cachedSignature('T', 'Supplier<Optional<Object>> fetch'), [
          'String key = GraphLinkPartialQuery.computeCacheKey(name, variables, glEncoder__);',
          'GraphLinkCacheEntry cached = getFromCache(key, tags, staleIfOffline);',
          _braces('if (cached != null && !cached.stale)', ['return $staleRead;']),
          'Optional<Object> fetched;',
          [
            _braces('try', ['fetched = fetch.get();']),
            _braces('catch (RestError e)', ['throw e;']),
            _braces('catch (RuntimeException e)', [
              _braces('if (cached != null)', ['return $staleRead;']),
              'throw e;',
            ]),
          ].join(' '),
          ...storeBody,
        ]);

  final helpers = [
    _method('private Optional<Object> restFetched(RestRequest request, Object value, boolean allowEmpty)', [
      _braces('if (value == null && !allowEmpty)', [
        'throw new IllegalStateException("Empty REST response for a non-null result of " + request.getMethod() + " " + request.getPath());',
      ]),
      'return Optional.ofNullable(value);',
    ]),
    _method('private GLDownload restDownloadOf(RestResponse response, DownloadProgressCallback onProgress)', [
      _braces('if (response.getStatus() == 204)', ['response.drain();', 'return null;']),
      'return GLDownload.fromResponse(response, onProgress);',
    ]),
    _method('private Object restParse(RestResponse response, List<String> path)', [
      'String text = response.text();',
      _braces('if (text.isBlank())', ['return null;']),
      'Map<String, Object> wrapper = glDecoder__.decode("{\\"v\\":" + text + "}");',
      'return GraphLinkRestUtils.restNavigate(wrapper.get("v"), path);',
    ]),
    _method('protected String restEncodeJson(Object value)', [
      'Map<String, Object> wrapper = new HashMap<>();',
      'wrapper.put("v", value);',
      'String text = glEncoder__.encode(wrapper);',
      "return text.substring(text.indexOf(':') + 1, text.lastIndexOf('}')).trim();",
    ]),
  ].join('\n\n');

  final body = [
    'protected final GLRestAdapter restAdapter;',
    constructor,
    restCall,
    voidOp,
    jsonOps,
    textOps,
    downloadOps,
    fetch,
    cached,
    helpers,
  ].join('\n\n');
  return 'public class GraphLinkRestResolver extends GraphLinkResolverBase {\n${body.ident()}\n}\n';
}

String javaRestJdkAdapter(JavaReactiveFlavor flavor) {
  final execute = flavor.isReactive
      ? [
          _method('@Override\npublic ${flavor.singleType('RestResponse')} execute(RestRequest request)', [
            'return ${flavor.defer('send(request)')};',
          ]),
          _method('private ${flavor.singleType('RestResponse')} send(RestRequest request)', [
            'HttpRequest httpRequest = build(request);',
            _braces('if (request.isStreamResponse())', [
              'return ${flavor.bridgeFuture('httpClient.sendAsync(httpRequest, HttpResponse.BodyHandlers.ofInputStream()).thenApply(response -> convert(response.statusCode(), response.headers(), response.body()))')};',
            ]),
            'return ${flavor.bridgeFuture('httpClient.sendAsync(httpRequest, HttpResponse.BodyHandlers.ofByteArray()).thenApply(response -> convert(response.statusCode(), response.headers(), new ByteArrayInputStream(response.body())))')};',
          ]),
        ].join('\n\n')
      : _method('@Override\npublic RestResponse execute(RestRequest request)', [
          'HttpRequest httpRequest = build(request);',
          [
            _braces('try', [
              _braces('if (request.isStreamResponse())', [
                'HttpResponse<InputStream> response = httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofInputStream());',
                'return convert(response.statusCode(), response.headers(), response.body());',
              ]),
              'HttpResponse<byte[]> response = httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofByteArray());',
              'return convert(response.statusCode(), response.headers(), new ByteArrayInputStream(response.body()));',
            ]),
            _braces('catch (IOException e)', ['throw new UncheckedIOException(e);']),
            _braces('catch (InterruptedException e)', [
              'Thread.currentThread().interrupt();',
              'throw new RuntimeException(e);',
            ]),
          ].join(' '),
        ]);

  final build = _method('private HttpRequest build(RestRequest request)', [
    'Map<String, String> headers = new LinkedHashMap<>();',
    'Map<String, String> provided = headersProvider.get();',
    _braces('if (provided != null)', ['headers.putAll(provided);']),
    'headers.putAll(request.getHeaders());',
    'HttpRequest.BodyPublisher publisher = publisher(request, headers);',
    'HttpRequest.Builder builder = HttpRequest.newBuilder().uri(URI.create(url(request))).method(request.getMethod(), publisher);',
    _braces('for (Map.Entry<String, String> header : headers.entrySet())', ['builder.header(header.getKey(), header.getValue());']),
    'return builder.build();',
  ]);

  final url = _method('private String url(RestRequest request)', [
    'String base = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;',
    'return base + request.getPath() + queryString(request.getQuery());',
  ]);

  final queryString = _method('private static String queryString(List<Map.Entry<String, String>> entries)', [
    'StringJoiner joiner = new StringJoiner("&");',
    _braces('for (Map.Entry<String, String> entry : entries)', [
      'joiner.add(GraphLinkRestUtils.restEncodeQuery(entry.getKey()) + "=" + GraphLinkRestUtils.restEncodeQuery(entry.getValue()));',
    ]),
    'return joiner.length() == 0 ? "" : "?" + joiner;',
  ]);

  final publisher = _method('private HttpRequest.BodyPublisher publisher(RestRequest request, Map<String, String> headers)', [
    'RestBody body = request.getBody();',
    _braces('if (body == null)', ['return HttpRequest.BodyPublishers.noBody();']),
    _braces('if (body instanceof RestBody.Json)', ['return HttpRequest.BodyPublishers.ofString(((RestBody.Json) body).getJson());']),
    _braces('if (body instanceof RestBody.Form)', [
      'String form = queryString(((RestBody.Form) body).getFields());',
      'return HttpRequest.BodyPublishers.ofString(form.isEmpty() ? "" : form.substring(1));',
    ]),
    _braces('if (body instanceof RestBody.Raw)', [
      'GLUpload upload = ((RestBody.Raw) body).getUpload();',
      'return stream(GLMultipartBody.withProgress(upload.getStream(), upload.getLength(), request.getOnSendProgress()), upload.getLength());',
    ]),
    'GLMultipartBody multipart = ((RestBody.Multipart) body).toBody();',
    'headers.put("Content-Type", multipart.getContentType());',
    'return stream(multipart.getStream(request.getOnSendProgress()), multipart.getLength());',
  ]);

  final stream = _method('private static HttpRequest.BodyPublisher stream(InputStream in, long length)', [
    _braces('if (length == 0)', ['return HttpRequest.BodyPublishers.noBody();']),
    'HttpRequest.BodyPublisher publisher = HttpRequest.BodyPublishers.ofInputStream(() -> in);',
    'return length > 0 ? HttpRequest.BodyPublishers.fromPublisher(publisher, length) : publisher;',
  ]);

  final convert = _method('private static RestResponse convert(int status, HttpHeaders headers, InputStream body)', [
    'Map<String, String> flat = new LinkedHashMap<>();',
    _braces('for (Map.Entry<String, List<String>> entry : headers.map().entrySet())', [
      'flat.put(entry.getKey().toLowerCase(Locale.ROOT), String.join(",", entry.getValue()));',
    ]),
    'String encoding = flat.get("content-encoding");',
    _braces('if (encoding != null)', [
      'String coding = encoding.trim().toLowerCase(Locale.ROOT);',
      [
        _braces('try', [
          _braces('if (coding.equals("gzip") || coding.equals("x-gzip"))', ['return new RestResponse(status, new GZIPInputStream(body), flat);']),
          _braces('if (coding.equals("deflate"))', ['return new RestResponse(status, new InflaterInputStream(body), flat);']),
        ]),
        _braces('catch (IOException e)', ['throw new UncheckedIOException(e);']),
      ].join(' '),
    ]),
    'return new RestResponse(status, body, flat);',
  ]);

  final constructors = [
    _method('public DefaultGraphLinkRestAdapter(String baseUrl)', ['this(baseUrl, () -> null);']),
    _method('public DefaultGraphLinkRestAdapter(String baseUrl, Supplier<Map<String, String>> headersProvider)', [
      'this(baseUrl, headersProvider, HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).followRedirects(HttpClient.Redirect.NORMAL).build());',
    ]),
    _method('public DefaultGraphLinkRestAdapter(String baseUrl, Supplier<Map<String, String>> headersProvider, HttpClient httpClient)', [
      'this.baseUrl = baseUrl;',
      'this.headersProvider = headersProvider;',
      'this.httpClient = httpClient;',
    ]),
  ].join('\n\n');

  final body = [
    'private final String baseUrl;',
    'private final Supplier<Map<String, String>> headersProvider;',
    'private final HttpClient httpClient;',
    constructors,
    execute,
    build,
    url,
    queryString,
    publisher,
    stream,
    convert,
  ].join('\n\n');
  return 'public class DefaultGraphLinkRestAdapter implements GLRestAdapter {\n${body.ident()}\n}\n';
}

String javaGLWebClientContentType() {
  final sanitize = _method('public static ExchangeFilterFunction sanitize()', [
    'return (request, next) -> next.exchange(request).map(GLWebClientContentType::sanitize);',
  ]);
  final response = _method('private static ClientResponse sanitize(ClientResponse response)', [
    'String value = response.headers().asHttpHeaders().getFirst(HttpHeaders.CONTENT_TYPE);',
    _braces('if (value == null || parses(value))', ['return response;']),
    'String cleaned = withoutCharset(value);',
    'return response.mutate().headers(headers -> replace(headers, cleaned)).build();',
  ]);
  final replace = _method('private static void replace(HttpHeaders headers, String cleaned)', [
    'headers.remove(HttpHeaders.CONTENT_TYPE);',
    _braces('if (parses(cleaned))', ['headers.set(HttpHeaders.CONTENT_TYPE, cleaned);']),
  ]);
  final parses = _method('private static boolean parses(String value)', [
    _braces('try', ['MediaType.parseMediaType(value);', 'return true;']),
    _braces('catch (InvalidMediaTypeException e)', ['return false;']),
  ]);
  final withoutCharset = _method('private static String withoutCharset(String value)', [
    'return Arrays.stream(value.split(";")).filter(part -> !part.trim().toLowerCase(Locale.ROOT).startsWith("charset=")).collect(Collectors.joining(";"));',
  ]);
  final members = [sanitize, response, replace, parses, withoutCharset].join('\n\n');
  return 'public final class GLWebClientContentType {\n${members.ident()}\n}\n';
}

String javaGLDataBufferInputStream() {
  final constructor = _method('GLDataBufferInputStream(Flux<DataBuffer> body)', [
    _braces('subscriber = new BaseSubscriber<DataBuffer>()', [
      _method('@Override\nprotected void hookOnSubscribe(Subscription subscription)', ['subscription.request(1);']),
      _method('@Override\nprotected void hookOnNext(DataBuffer buffer)', ['queue.add(bytesOf(buffer));']),
      _method('@Override\nprotected void hookOnComplete()', ['queue.add(END);']),
      _method('@Override\nprotected void hookOnError(Throwable failure)', ['queue.add(failure);']),
    ]).replaceFirst(RegExp(r'\}$'), '};'),
    'body.subscribe(subscriber);',
  ]);

  final read = _method('@Override\npublic int read(byte[] target, int offset, int length) throws IOException', [
    _braces('if (length == 0)', ['return 0;']),
    _braces('while (position >= current.length)', [
      _braces('if (finished)', ['return -1;']),
      'Object next = take();',
      _braces('if (next == END)', ['finished = true;', 'return -1;']),
      _braces('if (next instanceof Throwable)', ['finished = true;', 'throw new IOException((Throwable) next);']),
      'current = (byte[]) next;',
      'position = 0;',
      'subscriber.request(1);',
    ]),
    'int count = Math.min(length, current.length - position);',
    'System.arraycopy(current, position, target, offset, count);',
    'position += count;',
    'return count;',
  ]);

  final readByte = _method('@Override\npublic int read() throws IOException', [
    'byte[] one = new byte[1];',
    'return read(one, 0, 1) == -1 ? -1 : one[0] & 0xff;',
  ]);

  final take = _method('private Object take() throws IOException', [
    [
      _braces('try', ['return queue.take();']),
      _braces('catch (InterruptedException e)', [
        'Thread.currentThread().interrupt();',
        'subscriber.dispose();',
        'throw new InterruptedIOException();',
      ]),
    ].join(' '),
  ]);

  final close = _method('@Override\npublic void close()', [
    'finished = true;',
    'subscriber.dispose();',
  ]);

  final body = [
    'private static final Object END = new Object();',
    'private final BlockingQueue<Object> queue = new LinkedBlockingQueue<>();',
    'private final BaseSubscriber<DataBuffer> subscriber;',
    'private byte[] current = new byte[0];',
    'private int position = 0;',
    'private boolean finished = false;',
    constructor,
    _method('static byte[] bytesOf(DataBuffer buffer)', [
      'byte[] bytes = new byte[buffer.readableByteCount()];',
      'buffer.read(bytes);',
      'DataBufferUtils.release(buffer);',
      'return bytes;',
    ]),
    readByte,
    read,
    take,
    close,
  ].join('\n\n');
  return 'final class GLDataBufferInputStream extends InputStream {\n${body.ident()}\n}\n';
}

String javaRestWebClientAdapter() {
  final execute = [
    _method('@Override\npublic Mono<RestResponse> execute(RestRequest request)', ['return Mono.defer(() -> send(request));']),
    _method('private Mono<RestResponse> send(RestRequest request)', [
      'Map<String, String> headers = new LinkedHashMap<>();',
      'Map<String, String> provided = headersProvider.get();',
      _braces('if (provided != null)', ['headers.putAll(provided);']),
      'headers.putAll(request.getHeaders());',
      'BodyInserter<?, ? super ClientHttpRequest> body = body(request, headers);',
      'WebClient.RequestBodySpec spec = webClient.method(HttpMethod.valueOf(request.getMethod())).uri(URI.create(url(request)));',
      'headers.forEach(spec::header);',
      'WebClient.RequestHeadersSpec<?> ready = body == null ? spec : spec.body(body);',
      'WebClient.ResponseSpec response = ready.retrieve().onStatus(status -> true, failure -> Mono.empty());',
      _braces('if (request.isStreamResponse())', [
        'return response.toEntityFlux(DataBuffer.class).publishOn(Schedulers.boundedElastic()).map(entity -> convert(entity.getStatusCode().value(), entity.getHeaders(), new GLDataBufferInputStream(entity.getBody())));',
      ]),
      'return response.toEntityFlux(DataBuffer.class).flatMap(entity -> DataBufferUtils.join(entity.getBody()).map(GLDataBufferInputStream::bytesOf).defaultIfEmpty(new byte[0]).map(bytes -> convert(entity.getStatusCode().value(), entity.getHeaders(), new ByteArrayInputStream(bytes))));',
    ]),
  ].join('\n\n');

  final url = _method('private String url(RestRequest request)', [
    'String base = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;',
    'return base + request.getPath() + queryString(request.getQuery());',
  ]);

  final queryString = _method('private static String queryString(List<Map.Entry<String, String>> entries)', [
    'StringJoiner joiner = new StringJoiner("&");',
    _braces('for (Map.Entry<String, String> entry : entries)', [
      'joiner.add(GraphLinkRestUtils.restEncodeQuery(entry.getKey()) + "=" + GraphLinkRestUtils.restEncodeQuery(entry.getValue()));',
    ]),
    'return joiner.length() == 0 ? "" : "?" + joiner;',
  ]);

  final body = _method('private BodyInserter<?, ? super ClientHttpRequest> body(RestRequest request, Map<String, String> headers)', [
    'RestBody body = request.getBody();',
    _braces('if (body == null)', ['return null;']),
    _braces('if (body instanceof RestBody.Json)', ['return BodyInserters.fromValue(((RestBody.Json) body).getJson());']),
    _braces('if (body instanceof RestBody.Form)', [
      'String form = queryString(((RestBody.Form) body).getFields());',
      'return BodyInserters.fromValue(form.isEmpty() ? "" : form.substring(1));',
    ]),
    _braces('if (body instanceof RestBody.Raw)', [
      'GLUpload upload = ((RestBody.Raw) body).getUpload();',
      'return resource(GLMultipartBody.withProgress(upload.getStream(), upload.getLength(), request.getOnSendProgress()), upload.getLength());',
    ]),
    'GLMultipartBody multipart = ((RestBody.Multipart) body).toBody();',
    'headers.put("Content-Type", multipart.getContentType());',
    'return resource(multipart.getStream(request.getOnSendProgress()), multipart.getLength());',
  ]);

  final resource = _method('private static BodyInserter<?, ? super ClientHttpRequest> resource(InputStream in, long length)', [
    _braces('if (length == 0)', ['return BodyInserters.fromValue(new byte[0]);']),
    'return BodyInserters.fromResource(new InputStreamResource(in) ${_braces('', ['@Override public long contentLength() { return length; }'])});',
  ]);

  final convert = _method('private static RestResponse convert(int status, HttpHeaders headers, InputStream body)', [
    'Map<String, String> flat = new LinkedHashMap<>();',
    'headers.forEach((name, values) -> flat.put(name.toLowerCase(Locale.ROOT), String.join(",", values)));',
    'String encoding = flat.get("content-encoding");',
    _braces('if (encoding != null)', [
      'String coding = encoding.trim().toLowerCase(Locale.ROOT);',
      [
        _braces('try', [
          _braces('if (coding.equals("gzip") || coding.equals("x-gzip"))', ['return new RestResponse(status, new GZIPInputStream(body), flat);']),
          _braces('if (coding.equals("deflate"))', ['return new RestResponse(status, new InflaterInputStream(body), flat);']),
        ]),
        _braces('catch (IOException e)', ['throw new UncheckedIOException(e);']),
      ].join(' '),
    ]),
    'return new RestResponse(status, body, flat);',
  ]);

  final constructors = [
    _method('public DefaultGraphLinkRestAdapter(String baseUrl)', ['this(baseUrl, () -> null);']),
    _method('public DefaultGraphLinkRestAdapter(String baseUrl, Supplier<Map<String, String>> headersProvider)', [
      'this(baseUrl, headersProvider, WebClient.builder().clientConnector(new ReactorClientHttpConnector(reactor.netty.http.client.HttpClient.create().followRedirect(true))).build());',
    ]),
    _method('public DefaultGraphLinkRestAdapter(String baseUrl, Supplier<Map<String, String>> headersProvider, WebClient webClient)', [
      'this.baseUrl = baseUrl;',
      'this.headersProvider = headersProvider;',
      'this.webClient = webClient.mutate().filter(GLWebClientContentType.sanitize()).build();',
    ]),
  ].join('\n\n');

  final members = [
    'private final String baseUrl;',
    'private final Supplier<Map<String, String>> headersProvider;',
    'private final WebClient webClient;',
    constructors,
    execute,
    url,
    queryString,
    body,
    resource,
    convert,
  ].join('\n\n');
  return 'public class DefaultGraphLinkRestAdapter implements GLRestAdapter {\n${members.ident()}\n}\n';
}
