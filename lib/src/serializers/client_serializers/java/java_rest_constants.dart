import 'package:graphlink/src/java_code_gen_utils.dart';
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
            java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int read;
            while ((read = in.read(chunk)) != -1) buffer.write(chunk, 0, read);
            return buffer.toByteArray();
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
            byte[] chunk = new byte[8192];
            while (in.read(chunk) != -1) { }
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
            java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int read;
            while ((read = in.read(chunk)) != -1) buffer.write(chunk, 0, read);
            return buffer.toByteArray();
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
                    name = URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8");
                } catch (IllegalArgumentException | java.io.UnsupportedEncodingException e) {
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
                    out.add(new java.util.AbstractMap.SimpleImmutableEntry<>(key, joiner.toString()));
                } else {
                    for (Object item : items) out.add(new java.util.AbstractMap.SimpleImmutableEntry<>(key, restText(item)));
                }
            } else {
                for (int i = 0; i < list.size(); i++) {
                    restCollect(out, bracket ? key + "[" + i + "]" : key + "." + i, list.get(i), bracket, comma, true);
                }
            }
        } else {
            out.add(new java.util.AbstractMap.SimpleImmutableEntry<>(key, restText(value)));
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

final _cg = JavaCodeGenUtils();

const _override = '@Override\n';
const _emptyResponse =
    'throw new IllegalStateException("Empty REST response for a non-null result of " + request.getMethod() + " " + request.getPath());';

String _members(List<String> members) => members.join('\n\n');

String javaRestAdapterInterface(JavaReactiveFlavor flavor) => '@FunctionalInterface\n${_cg.createInterface(
      interfaceName: 'GLRestAdapter',
      statements: ['${flavor.singleType('RestResponse')} execute(RestRequest request);'],
    )}\n';

String javaNoGraphQLAdapter(JavaReactiveFlavor flavor, {required bool operationName}) {
  const failure = 'new IllegalStateException("This schema has no GraphQL operation: pass no GraphQL adapter")';
  return '${_cg.createClass(
    className: 'GraphLinkNoGraphQL',
    finalClass: true,
    interfaceNames: ['GraphLinkClientAdapter'],
    statements: [
      _cg.method(
        returnType: '${_override}public ${flavor.singleType('String')}',
        methodName: 'execute',
        arguments: ['String payload', if (operationName) 'String operationName'],
        statements: [flavor.isReactive ? 'return ${flavor.error(failure)};' : 'throw $failure;'],
      ),
    ],
  )}\n';
}

class _ValueOp {
  final String name;
  final String typeParams;
  final String resultType;
  final List<String> extraParams;
  final List<String> read;
  final List<String>? readOrNull;
  final String apply;

  _ValueOp({
    required this.name,
    this.typeParams = '',
    required this.resultType,
    this.extraParams = const [],
    required this.read,
    this.readOrNull,
    required this.apply,
  });
}

String _valueOps(JavaReactiveFlavor flavor, _ValueOp op) {
  final arguments = ['RestRequest request', ...op.extraParams, 'Runnable afterSuccess'];
  List<String> tail(List<String> read, {required bool nullable}) => [
        ...read,
        if (!nullable)
          _cg.ifStatement(condition: 'value == null', ifBlockStatements: [_emptyResponse]),
        _cg.constDecl('result', op.apply, type: op.resultType),
        'afterSuccess.run();',
      ];

  String build(String suffix, List<String> read, {required bool nullable}) {
    final nullableName = '${op.name}$suffix';
    if (!flavor.isReactive) {
      return _cg.method(
        returnType: 'protected ${op.typeParams}${op.resultType}',
        methodName: nullableName,
        arguments: arguments,
        statements: [
          _cg.constDecl('response', 'restCall(request)', type: 'RestResponse'),
          ...tail(read, nullable: nullable),
          'return result;',
        ],
      );
    }
    final open = nullable
        ? flavor.flatMapToMaybeOpen('restCall(request)', 'response')
        : flavor.mapOpen('restCall(request)', 'response');
    final returned = nullable ? flavor.maybeOf('result') : 'result';
    return _cg.method(
      returnType: 'protected ${op.typeParams}${nullable ? flavor.maybeType(op.resultType) : flavor.singleType(op.resultType)}',
      methodName: nullableName,
      arguments: arguments,
      statements: ['return ${_cg.lambdaBlock(open, [...tail(read, nullable: nullable), 'return $returned;'])}'],
    );
  }

  return _members([
    build('', op.read, nullable: false),
    build('OrNull', op.readOrNull ?? op.read, nullable: true),
  ]);
}

String javaRestResolver(JavaReactiveFlavor flavor, {required bool withGetAdapter}) {
  final r = flavor.isReactive;
  final fetchType = flavor.singleType('Optional<Object>');
  const staleRead = 'decode.apply(glDecoder__.decode(cached.data).get("__gl_v__"))';
  const completableFuture = 'java.util.concurrent.CompletableFuture<Optional<Object>>';

  final constructor = _cg.createMethod(
    returnType: 'protected',
    methodName: 'GraphLinkRestResolver',
    arguments: [
      'GraphLinkClientAdapter adapter',
      if (withGetAdapter) 'GraphLinkClientAdapter getAdapter',
      'GLRestAdapter restAdapter',
      'Map<String, String> fragmentMap',
      'GraphLinkCacheStore store',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
    ],
    statements: [
      'super(adapter, ${withGetAdapter ? 'getAdapter, ' : ''}fragmentMap, store, encoder, decoder);',
      'this.restAdapter = restAdapter;',
    ],
  );

  final restCall = r
      ? _members([
          _cg.method(
            returnType: 'protected ${flavor.singleType('RestResponse')}',
            methodName: 'restCall',
            arguments: ['RestRequest request'],
            statements: ['return ${flavor.flatMap('restAdapter.execute(request)', 'response -> restChecked(response)')};'],
          ),
          _cg.method(
            returnType: 'private ${flavor.singleType('RestResponse')}',
            methodName: 'restChecked',
            arguments: ['RestResponse response'],
            statements: [
              _cg.ifStatement(
                condition: 'response.isSuccess()',
                ifBlockStatements: ['return ${flavor.wrapValue('response')};'],
              ),
              'return ${flavor.error('new RestError(response.getStatus(), response.getHeaders(), response.text())')};',
            ],
          ),
        ])
      : _cg.method(
          returnType: 'protected RestResponse',
          methodName: 'restCall',
          arguments: ['RestRequest request'],
          statements: [
            _cg.constDecl('response', 'restAdapter.execute(request)', type: 'RestResponse'),
            _cg.ifStatement(
              condition: '!response.isSuccess()',
              ifBlockStatements: ['throw new RestError(response.getStatus(), response.getHeaders(), response.text());'],
            ),
            'return response;',
          ],
        );

  final voidOp = r
      ? _cg.method(
          returnType: 'protected ${flavor.voidType}',
          methodName: 'restVoid',
          arguments: ['RestRequest request', 'Runnable afterSuccess'],
          statements: [
            'return ${_cg.lambdaBlock(flavor.flatMapToVoidOpen('restCall(request)', 'response'), [
                  'response.drain();',
                  'afterSuccess.run();',
                  'return ${flavor.voidDone};',
                ])}',
          ],
        )
      : _cg.method(
          returnType: 'protected void',
          methodName: 'restVoid',
          arguments: ['RestRequest request', 'Runnable afterSuccess'],
          statements: ['restCall(request).drain();', 'afterSuccess.run();'],
        );

  final jsonOps = _valueOps(
    flavor,
    _ValueOp(
      name: 'restJson',
      typeParams: '<T> ',
      resultType: 'T',
      extraParams: ['List<String> path', 'Function<Object, T> decode'],
      read: [_cg.constDecl('value', 'restParse(response, path)', type: 'Object')],
      apply: 'decode.apply(value)',
    ),
  );
  final textOps = _valueOps(
    flavor,
    _ValueOp(
      name: 'restText',
      resultType: 'String',
      read: [_cg.constDecl('value', 'response.text()', type: 'String')],
      readOrNull: [
        'String value = response.text();',
        _cg.ifStatement(condition: 'value.isEmpty()', ifBlockStatements: ['value = null;']),
      ],
      apply: 'value',
    ),
  );
  final downloadOps = _valueOps(
    flavor,
    _ValueOp(
      name: 'restDownload',
      resultType: 'GLDownload',
      extraParams: ['DownloadProgressCallback onProgress'],
      read: [_cg.constDecl('value', 'restDownloadOf(response, onProgress)', type: 'GLDownload')],
      apply: 'value',
    ),
  );

  final fetch = _cg.method(
    returnType: 'protected ${r ? fetchType : 'Optional<Object>'}',
    methodName: 'restFetch',
    arguments: ['RestRequest request', 'List<String> path', 'boolean allowEmpty'],
    statements: [
      r
          ? 'return ${flavor.mapTo('restCall(request)', 'response -> restFetched(request, restParse(response, path), allowEmpty)')};'
          : 'return restFetched(request, restParse(restCall(request), path), allowEmpty);',
    ],
  );

  List<String> cachedArguments(String fetchArg) => [
        'String name',
        'Map<String, Object> variables',
        'long ttl',
        'List<String> tags',
        'boolean staleIfOffline',
        fetchArg,
        'Function<Object, T> decode',
      ];

  final cacheLookup = [
    _cg.constDecl('key', 'GraphLinkPartialQuery.computeCacheKey(name, variables, glEncoder__)', type: 'String'),
    _cg.constDecl('cached', 'getFromCache(key, tags, staleIfOffline)', type: 'GraphLinkCacheEntry'),
  ];

  final storeBody = [
    _cg.constDecl('json', 'fetched.orElse(null)', type: 'Object'),
    _cg.constDecl('value', 'decode.apply(json)', type: 'T'),
    _cg.ifStatement(condition: 'json != null', ifBlockStatements: [
      _cg.constDecl('wrapper', 'new HashMap<>()', type: 'Map<String, Object>'),
      'wrapper.put("__gl_v__", json);',
      _cg.constDecl(
        'entry',
        'new GraphLinkCacheEntry(glEncoder__.encode(wrapper), System.currentTimeMillis() + ttl * 1000L)',
        type: 'GraphLinkCacheEntry',
      ),
      'glStoreIfCurrent(key, glEncoder__.encode(entry.toJson()), tags, epoch);',
    ]),
    'return value;',
  ];

  final cached = r
      ? _members([
          _cg.method(
            returnType: 'protected <T> ${flavor.singleType('T')}',
            methodName: 'restCached',
            arguments: cachedArguments('Supplier<$fetchType> fetch'),
            statements: [
              ...cacheLookup,
              _cg.ifStatement(
                condition: 'cached != null && !cached.stale',
                ifBlockStatements: ['return ${flavor.wrapValue(staleRead)};'],
              ),
              _cg.constDecl('epoch', 'glEpoch(tags)', type: 'long'),
              'return ${_cg.lambdaBlock(
                flavor.onErrorResumeOpen(
                  flavor.mapTo('restFlight(key + "|" + epoch, fetch)', 'fetched -> restStore(key, epoch, ttl, tags, fetched, decode)'),
                  'failure',
                ),
                [
                  _cg.ifStatement(
                    condition: 'failure instanceof RestError || cached == null',
                    ifBlockStatements: ['return ${flavor.error('failure')};'],
                  ),
                  'return ${flavor.wrapValue(staleRead)};',
                ],
              )}',
            ],
          ),
          _cg.method(
            returnType: 'protected <T> ${flavor.maybeType('T')}',
            methodName: 'restCachedOrNull',
            arguments: cachedArguments('Supplier<$fetchType> fetch'),
            statements: [
              'return ${_cg.lambdaBlock(
                flavor.flatMapToMaybeOpen(
                  'restCached(name, variables, ttl, tags, staleIfOffline, fetch, json -> Optional.ofNullable(decode.apply(json)))',
                  'cached',
                ),
                ['return ${flavor.maybeOf('cached.orElse(null)')};'],
              )}',
            ],
          ),
          _cg.method(
            returnType: 'private <T> T',
            methodName: 'restStore',
            arguments: [
              'String key',
              'long epoch',
              'long ttl',
              'List<String> tags',
              'Optional<Object> fetched',
              'Function<Object, T> decode',
            ],
            statements: storeBody,
          ),
        ])
      : _cg.method(
          returnType: 'protected <T> T',
          methodName: 'restCached',
          arguments: cachedArguments('Supplier<Optional<Object>> fetch'),
          statements: [
            ...cacheLookup,
            _cg.ifStatement(
              condition: 'cached != null && !cached.stale',
              ifBlockStatements: ['return $staleRead;'],
            ),
            _cg.constDecl('epoch', 'glEpoch(tags)', type: 'long'),
            'Optional<Object> fetched;',
            _cg.tryCatch(
              tryStatements: ['fetched = restFlight(key + "|" + epoch, fetch);'],
              catches: [
                const JavaCatch('RestError', 'e', ['throw e;']),
                JavaCatch('RuntimeException', 'e', [
                  _cg.ifStatement(condition: 'cached != null', ifBlockStatements: ['return $staleRead;']),
                  'throw e;',
                ]),
              ],
            ),
            ...storeBody,
          ],
        );

  final restFlight = r
      ? _cg.method(
          returnType: 'private $fetchType',
          methodName: 'restFlight',
          arguments: ['String key', 'Supplier<$fetchType> fetch'],
          statements: [
            'return ${_cg.lambdaBlock(flavor.deferOpen(), [
                  _cg.constDecl('mine', 'new java.util.concurrent.CompletableFuture<>()', type: completableFuture),
                  _cg.constDecl('running', 'restFlights__.putIfAbsent(key, mine)', type: completableFuture),
                  _cg.ifStatement(
                    condition: 'running != null',
                    ifBlockStatements: ['return ${flavor.bridgeFuture('running.thenApply(v -> v)')};'],
                  ),
                  _cg.lambdaBlock('${flavor.toFuture('fetch.get()')}.whenComplete((value, e) -> {', [
                    'restFlights__.remove(key, mine);',
                    _cg.ifStatement(
                      condition: 'e == null',
                      ifBlockStatements: ['mine.complete(value);'],
                      elseBlockStatements: [
                        'mine.completeExceptionally(${_cg.ternaryOp(
                          condition: 'e instanceof java.util.concurrent.CompletionException && e.getCause() != null',
                          positiveStatement: 'e.getCause()',
                          negativeStatement: 'e',
                        )});',
                      ],
                    ),
                  ]),
                  'return ${flavor.bridgeFuture('mine.thenApply(v -> v)')};',
                ])}',
          ],
        )
      : _cg.method(
          returnType: 'private Optional<Object>',
          methodName: 'restFlight',
          arguments: ['String key', 'Supplier<Optional<Object>> fetch'],
          statements: [
            _cg.constDecl('mine', 'new java.util.concurrent.CompletableFuture<>()', type: completableFuture),
            _cg.constDecl('running', 'restFlights__.putIfAbsent(key, mine)', type: completableFuture),
            _cg.ifStatement(condition: 'running != null', ifBlockStatements: [
              _cg.tryCatch(
                tryStatements: ['return running.join();'],
                catches: [
                  JavaCatch('java.util.concurrent.CompletionException', 'e', [
                    _cg.ifStatement(
                      condition: 'e.getCause() instanceof RuntimeException',
                      ifBlockStatements: ['throw (RuntimeException) e.getCause();'],
                    ),
                    'throw e;',
                  ]),
                ],
              ),
            ]),
            _cg.tryCatch(
              tryStatements: [
                _cg.constDecl('result', 'fetch.get()', type: 'Optional<Object>'),
                'mine.complete(result);',
                'return result;',
              ],
              catches: [
                const JavaCatch('RuntimeException', 'e', ['mine.completeExceptionally(e);', 'throw e;']),
              ],
              finallyStatements: ['restFlights__.remove(key, mine);'],
            ),
          ],
        );

  final helpers = _members([
    restFlight,
    _cg.method(
      returnType: 'private Optional<Object>',
      methodName: 'restFetched',
      arguments: ['RestRequest request', 'Object value', 'boolean allowEmpty'],
      statements: [
        _cg.ifStatement(condition: 'value == null && !allowEmpty', ifBlockStatements: [_emptyResponse]),
        'return Optional.ofNullable(value);',
      ],
    ),
    _cg.method(
      returnType: 'private GLDownload',
      methodName: 'restDownloadOf',
      arguments: ['RestResponse response', 'DownloadProgressCallback onProgress'],
      statements: [
        _cg.ifStatement(condition: 'response.getStatus() == 204', ifBlockStatements: ['response.drain();', 'return null;']),
        'return GLDownload.fromResponse(response, onProgress);',
      ],
    ),
    _cg.method(
      returnType: 'private Object',
      methodName: 'restParse',
      arguments: ['RestResponse response', 'List<String> path'],
      statements: [
        _cg.constDecl('text', 'response.text()', type: 'String'),
        _cg.ifStatement(condition: 'text.trim().isEmpty()', ifBlockStatements: ['return null;']),
        _cg.constDecl('wrapper', 'glDecoder__.decode("{\\"v\\":" + text + "}")', type: 'Map<String, Object>'),
        'return GraphLinkRestUtils.restNavigate(wrapper.get("v"), path);',
      ],
    ),
    _cg.method(
      returnType: 'protected String',
      methodName: 'restEncodeJson',
      arguments: ['Object value'],
      statements: [
        _cg.constDecl('wrapper', 'new HashMap<>()', type: 'Map<String, Object>'),
        'wrapper.put("v", value);',
        _cg.constDecl('text', 'glEncoder__.encode(wrapper)', type: 'String'),
        "return text.substring(text.indexOf(':') + 1, text.lastIndexOf('}')).trim();",
      ],
    ),
  ]);

  return '${_cg.createClass(
    className: 'GraphLinkRestResolver',
    superClass: 'GraphLinkResolverBase',
    statements: [
      _members([
        'protected final GLRestAdapter restAdapter;',
        'private final java.util.concurrent.ConcurrentHashMap<String, $completableFuture> restFlights__ = new java.util.concurrent.ConcurrentHashMap<>();',
        constructor,
        restCall,
        voidOp,
        jsonOps,
        textOps,
        downloadOps,
        fetch,
        cached,
        helpers,
      ]),
    ],
  )}\n';
}

String _restUrlMethod() => _cg.method(
      returnType: 'private String',
      methodName: 'url',
      arguments: ['RestRequest request'],
      statements: [
        _cg.constDecl(
          'base',
          _cg.ternaryOp(
            condition: 'baseUrl.endsWith("/")',
            positiveStatement: 'baseUrl.substring(0, baseUrl.length() - 1)',
            negativeStatement: 'baseUrl',
          ),
          type: 'String',
        ),
        'return base + request.getPath() + queryString(request.getQuery());',
      ],
    );

String _restQueryStringMethod() => _cg.method(
      returnType: 'private static String',
      methodName: 'queryString',
      arguments: ['List<Map.Entry<String, String>> entries'],
      statements: [
        _cg.constDecl('joiner', 'new StringJoiner("&")', type: 'StringJoiner'),
        _cg.forEachLoop(
          type: 'Map.Entry<String, String>',
          variable: 'entry',
          iterable: 'entries',
          statements: [
            'joiner.add(GraphLinkRestUtils.restEncodeQuery(entry.getKey()) + "=" + GraphLinkRestUtils.restEncodeQuery(entry.getValue()));',
          ],
        ),
        'return joiner.length() == 0 ? "" : "?" + joiner;',
      ],
    );

String _restConvertMethod(List<String> flattenHeaders) => _cg.method(
      returnType: 'private static RestResponse',
      methodName: 'convert',
      arguments: ['int status', 'HttpHeaders headers', 'InputStream body'],
      statements: [
        _cg.constDecl('flat', 'new LinkedHashMap<>()', type: 'Map<String, String>'),
        ...flattenHeaders,
        _cg.constDecl('encoding', 'flat.get("content-encoding")', type: 'String'),
        _cg.ifStatement(condition: 'encoding != null', ifBlockStatements: [
          _cg.constDecl('coding', 'encoding.trim().toLowerCase(Locale.ROOT)', type: 'String'),
          _cg.tryCatch(
            tryStatements: [
              _cg.ifStatement(
                condition: 'coding.equals("gzip") || coding.equals("x-gzip")',
                ifBlockStatements: ['return new RestResponse(status, new GZIPInputStream(body), flat);'],
              ),
              _cg.ifStatement(
                condition: 'coding.equals("deflate")',
                ifBlockStatements: ['return new RestResponse(status, new InflaterInputStream(body), flat);'],
              ),
            ],
            catches: [
              const JavaCatch('IOException', 'e', ['throw new UncheckedIOException(e);']),
            ],
          ),
        ]),
        'return new RestResponse(status, body, flat);',
      ],
    );

List<String> _restMergedHeaders() => [
      'Map<String, String> headers = new LinkedHashMap<>();',
      _cg.constDecl('provided', 'headersProvider.get()', type: 'Map<String, String>'),
      _cg.ifStatement(condition: 'provided != null', ifBlockStatements: ['headers.putAll(provided);']),
      'headers.putAll(request.getHeaders());',
    ];

List<String> _restBodyStatements({
  required String nullBody,
  required String json,
  required String form,
  required String raw,
  required String multipartResult,
}) =>
    [
      'RestBody body = request.getBody();',
      _cg.ifStatement(condition: 'body == null', ifBlockStatements: ['return $nullBody;']),
      _cg.ifStatement(condition: 'body instanceof RestBody.Json', ifBlockStatements: ['return $json;']),
      _cg.ifStatement(condition: 'body instanceof RestBody.Form', ifBlockStatements: [
        _cg.constDecl('form', 'queryString(((RestBody.Form) body).getFields())', type: 'String'),
        'return $form;',
      ]),
      _cg.ifStatement(condition: 'body instanceof RestBody.Raw', ifBlockStatements: [
        _cg.constDecl('upload', '((RestBody.Raw) body).getUpload()', type: 'GLUpload'),
        'return $raw;',
      ]),
      _cg.constDecl('multipart', '((RestBody.Multipart) body).toBody()', type: 'GLMultipartBody'),
      'headers.put("Content-Type", multipart.getContentType());',
      'return $multipartResult;',
    ];

String javaRestJdkAdapter(JavaReactiveFlavor flavor) {
  final execute = flavor.isReactive
      ? _members([
          _cg.method(
            returnType: '${_override}public ${flavor.singleType('RestResponse')}',
            methodName: 'execute',
            arguments: ['RestRequest request'],
            statements: ['return ${flavor.defer('send(request)')};'],
          ),
          _cg.method(
            returnType: 'private ${flavor.singleType('RestResponse')}',
            methodName: 'send',
            arguments: ['RestRequest request'],
            statements: [
              _cg.constDecl('httpRequest', 'build(request)', type: 'HttpRequest'),
              _cg.ifStatement(condition: 'request.isStreamResponse()', ifBlockStatements: [
                'return ${flavor.bridgeFuture('httpClient.sendAsync(httpRequest, HttpResponse.BodyHandlers.ofInputStream()).thenApply(response -> convert(response.statusCode(), response.headers(), response.body()))')};',
              ]),
              'return ${flavor.bridgeFuture('httpClient.sendAsync(httpRequest, HttpResponse.BodyHandlers.ofByteArray()).thenApply(response -> convert(response.statusCode(), response.headers(), new ByteArrayInputStream(response.body())))')};',
            ],
          ),
        ])
      : _cg.method(
          returnType: '${_override}public RestResponse',
          methodName: 'execute',
          arguments: ['RestRequest request'],
          statements: [
            _cg.constDecl('httpRequest', 'build(request)', type: 'HttpRequest'),
            _cg.tryCatch(
              tryStatements: [
                _cg.ifStatement(condition: 'request.isStreamResponse()', ifBlockStatements: [
                  _cg.constDecl('response', 'httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofInputStream())',
                      type: 'HttpResponse<InputStream>'),
                  'return convert(response.statusCode(), response.headers(), response.body());',
                ]),
                _cg.constDecl('response', 'httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofByteArray())',
                    type: 'HttpResponse<byte[]>'),
                'return convert(response.statusCode(), response.headers(), new ByteArrayInputStream(response.body()));',
              ],
              catches: [
                const JavaCatch('IOException', 'e', ['throw new UncheckedIOException(e);']),
                const JavaCatch('InterruptedException', 'e', ['Thread.currentThread().interrupt();', 'throw new RuntimeException(e);']),
              ],
            ),
          ],
        );

  final build = _cg.method(
    returnType: 'private HttpRequest',
    methodName: 'build',
    arguments: ['RestRequest request'],
    statements: [
      ..._restMergedHeaders(),
      _cg.constDecl('publisher', 'publisher(request, headers)', type: 'HttpRequest.BodyPublisher'),
      _cg.constDecl(
        'builder',
        'HttpRequest.newBuilder().uri(URI.create(url(request))).method(request.getMethod(), publisher)',
        type: 'HttpRequest.Builder',
      ),
      _cg.forEachLoop(
        type: 'Map.Entry<String, String>',
        variable: 'header',
        iterable: 'headers.entrySet()',
        statements: ['builder.header(header.getKey(), header.getValue());'],
      ),
      'return builder.build();',
    ],
  );

  final publisher = _cg.method(
    returnType: 'private HttpRequest.BodyPublisher',
    methodName: 'publisher',
    arguments: ['RestRequest request', 'Map<String, String> headers'],
    statements: _restBodyStatements(
      nullBody: 'HttpRequest.BodyPublishers.noBody()',
      json: 'HttpRequest.BodyPublishers.ofString(((RestBody.Json) body).getJson())',
      form: 'HttpRequest.BodyPublishers.ofString(form.isEmpty() ? "" : form.substring(1))',
      raw: 'stream(GLMultipartBody.withProgress(upload.getStream(), upload.getLength(), request.getOnSendProgress()), upload.getLength())',
      multipartResult: 'stream(multipart.getStream(request.getOnSendProgress()), multipart.getLength())',
    ),
  );

  final stream = _cg.method(
    returnType: 'private static HttpRequest.BodyPublisher',
    methodName: 'stream',
    arguments: ['InputStream in', 'long length'],
    statements: [
      _cg.ifStatement(condition: 'length == 0', ifBlockStatements: ['return HttpRequest.BodyPublishers.noBody();']),
      _cg.constDecl('publisher', 'HttpRequest.BodyPublishers.ofInputStream(() -> in)', type: 'HttpRequest.BodyPublisher'),
      'return ${_cg.ternaryOp(
        condition: 'length > 0',
        positiveStatement: 'HttpRequest.BodyPublishers.fromPublisher(publisher, length)',
        negativeStatement: 'publisher',
      )};',
    ],
  );

  final convert = _restConvertMethod([
    _cg.forEachLoop(
      type: 'Map.Entry<String, List<String>>',
      variable: 'entry',
      iterable: 'headers.map().entrySet()',
      statements: ['flat.put(entry.getKey().toLowerCase(Locale.ROOT), String.join(",", entry.getValue()));'],
    ),
  ]);

  final constructors = _members([
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl'],
      statements: ['this(baseUrl, () -> null);'],
    ),
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl', 'Supplier<Map<String, String>> headersProvider'],
      statements: [
        'this(baseUrl, headersProvider, HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).followRedirects(HttpClient.Redirect.NORMAL).build());',
      ],
    ),
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl', 'Supplier<Map<String, String>> headersProvider', 'HttpClient httpClient'],
      statements: [
        'this.baseUrl = baseUrl;',
        'this.headersProvider = headersProvider;',
        'this.httpClient = httpClient;',
      ],
    ),
  ]);

  return '${_cg.createClass(
    className: 'DefaultGraphLinkRestAdapter',
    interfaceNames: ['GLRestAdapter'],
    statements: [
      _members([
        'private final String baseUrl;',
        'private final Supplier<Map<String, String>> headersProvider;',
        'private final HttpClient httpClient;',
        constructors,
        execute,
        build,
        _restUrlMethod(),
        _restQueryStringMethod(),
        publisher,
        stream,
        convert,
      ]),
    ],
  )}\n';
}

String javaGLWebClientContentType() {
  final sanitize = _cg.method(
    returnType: 'public static ExchangeFilterFunction',
    methodName: 'sanitize',
    statements: ['return (request, next) -> next.exchange(request).map(GLWebClientContentType::sanitize);'],
  );
  final response = _cg.method(
    returnType: 'private static ClientResponse',
    methodName: 'sanitize',
    arguments: ['ClientResponse response'],
    statements: [
      _cg.constDecl('value', 'response.headers().asHttpHeaders().getFirst(HttpHeaders.CONTENT_TYPE)', type: 'String'),
      _cg.ifStatement(condition: 'value == null || parses(value)', ifBlockStatements: ['return response;']),
      _cg.constDecl('cleaned', 'withoutCharset(value)', type: 'String'),
      'return response.mutate().headers(headers -> replace(headers, cleaned)).build();',
    ],
  );
  final replace = _cg.method(
    returnType: 'private static void',
    methodName: 'replace',
    arguments: ['HttpHeaders headers', 'String cleaned'],
    statements: [
      'headers.remove(HttpHeaders.CONTENT_TYPE);',
      _cg.ifStatement(condition: 'parses(cleaned)', ifBlockStatements: ['headers.set(HttpHeaders.CONTENT_TYPE, cleaned);']),
    ],
  );
  final parses = _cg.method(
    returnType: 'private static boolean',
    methodName: 'parses',
    arguments: ['String value'],
    statements: [
      _cg.tryCatch(
        tryStatements: ['MediaType.parseMediaType(value);', 'return true;'],
        catches: [
          const JavaCatch('InvalidMediaTypeException', 'e', ['return false;']),
        ],
      ),
    ],
  );
  final withoutCharset = _cg.method(
    returnType: 'private static String',
    methodName: 'withoutCharset',
    arguments: ['String value'],
    statements: [
      'return Arrays.stream(value.split(";")).filter(part -> !part.trim().toLowerCase(Locale.ROOT).startsWith("charset=")).collect(Collectors.joining(";"));',
    ],
  );
  return '${_cg.createClass(
    className: 'GLWebClientContentType',
    finalClass: true,
    statements: [_members([sanitize, response, replace, parses, withoutCharset])],
  )}\n';
}

String javaGLDataBufferInputStream() {
  final subscriber = _cg.block([
    _cg.method(
      returnType: '${_override}protected void',
      methodName: 'hookOnSubscribe',
      arguments: ['Subscription subscription'],
      statements: ['subscription.request(1);'],
    ),
    _cg.method(
      returnType: '${_override}protected void',
      methodName: 'hookOnNext',
      arguments: ['DataBuffer buffer'],
      statements: ['queue.add(bytesOf(buffer));'],
    ),
    _cg.method(
      returnType: '${_override}protected void',
      methodName: 'hookOnComplete',
      statements: ['queue.add(END);'],
    ),
    _cg.method(
      returnType: '${_override}protected void',
      methodName: 'hookOnError',
      arguments: ['Throwable failure'],
      statements: ['queue.add(failure);'],
    ),
  ]);

  final constructor = _cg.createMethod(
    methodName: 'GLDataBufferInputStream',
    arguments: ['Flux<DataBuffer> body'],
    statements: [
      'subscriber = new BaseSubscriber<DataBuffer>() $subscriber;',
      'body.subscribe(subscriber);',
    ],
  );

  final read = _cg.method(
    returnType: '${_override}public int',
    methodName: 'read',
    arguments: ['byte[] target', 'int offset', 'int length'],
    throwsTypes: ['IOException'],
    statements: [
      _cg.ifStatement(condition: 'length == 0', ifBlockStatements: ['return 0;']),
      'while (position >= current.length) ${_cg.block([
            _cg.ifStatement(condition: 'finished', ifBlockStatements: ['return -1;']),
            _cg.constDecl('next', 'take()', type: 'Object'),
            _cg.ifStatement(condition: 'next == END', ifBlockStatements: ['finished = true;', 'return -1;']),
            _cg.ifStatement(
              condition: 'next instanceof Throwable',
              ifBlockStatements: ['finished = true;', 'throw new IOException((Throwable) next);'],
            ),
            'current = (byte[]) next;',
            'position = 0;',
            'subscriber.request(1);',
          ])}',
      _cg.constDecl('count', 'Math.min(length, current.length - position)', type: 'int'),
      'System.arraycopy(current, position, target, offset, count);',
      'position += count;',
      'return count;',
    ],
  );

  final readByte = _cg.method(
    returnType: '${_override}public int',
    methodName: 'read',
    throwsTypes: ['IOException'],
    statements: [
      'byte[] one = new byte[1];',
      'return read(one, 0, 1) == -1 ? -1 : one[0] & 0xff;',
    ],
  );

  final take = _cg.method(
    returnType: 'private Object',
    methodName: 'take',
    throwsTypes: ['IOException'],
    statements: [
      _cg.tryCatch(
        tryStatements: ['return queue.take();'],
        catches: [
          const JavaCatch('InterruptedException', 'e', [
            'Thread.currentThread().interrupt();',
            'subscriber.dispose();',
            'throw new InterruptedIOException();',
          ]),
        ],
      ),
    ],
  );

  final close = _cg.method(
    returnType: '${_override}public void',
    methodName: 'close',
    statements: ['finished = true;', 'subscriber.dispose();'],
  );

  return '${_cg.createClass(
    className: 'GLDataBufferInputStream',
    packagePrivate: true,
    finalClass: true,
    superClass: 'InputStream',
    statements: [
      _members([
        'private static final Object END = new Object();',
        'private final BlockingQueue<Object> queue = new LinkedBlockingQueue<>();',
        'private final BaseSubscriber<DataBuffer> subscriber;',
        'private byte[] current = new byte[0];',
        'private int position = 0;',
        'private boolean finished = false;',
        constructor,
        _cg.method(
          returnType: 'static byte[]',
          methodName: 'bytesOf',
          arguments: ['DataBuffer buffer'],
          statements: [
            _cg.constDecl('bytes', 'new byte[buffer.readableByteCount()]', type: 'byte[]'),
            'buffer.read(bytes);',
            'DataBufferUtils.release(buffer);',
            'return bytes;',
          ],
        ),
        readByte,
        read,
        take,
        close,
      ]),
    ],
  )}\n';
}

String javaRestWebClientAdapter() {
  final execute = _members([
    _cg.method(
      returnType: '${_override}public Mono<RestResponse>',
      methodName: 'execute',
      arguments: ['RestRequest request'],
      statements: ['return Mono.defer(() -> send(request));'],
    ),
    _cg.method(
      returnType: 'private Mono<RestResponse>',
      methodName: 'send',
      arguments: ['RestRequest request'],
      statements: [
        ..._restMergedHeaders(),
        _cg.constDecl('body', 'body(request, headers)', type: 'BodyInserter<?, ? super ClientHttpRequest>'),
        _cg.constDecl(
          'spec',
          'webClient.method(HttpMethod.valueOf(request.getMethod())).uri(URI.create(url(request)))',
          type: 'WebClient.RequestBodySpec',
        ),
        'headers.forEach(spec::header);',
        _cg.constDecl('ready', 'body == null ? spec : spec.body(body)', type: 'WebClient.RequestHeadersSpec<?>'),
        _cg.constDecl('response', 'ready.retrieve().onStatus(status -> true, failure -> Mono.empty())', type: 'WebClient.ResponseSpec'),
        _cg.ifStatement(condition: 'request.isStreamResponse()', ifBlockStatements: [
          'return response.toEntityFlux(DataBuffer.class).publishOn(Schedulers.boundedElastic()).map(entity -> convert(entity.getStatusCode().value(), entity.getHeaders(), new GLDataBufferInputStream(entity.getBody())));',
        ]),
        'return response.toEntityFlux(DataBuffer.class).flatMap(entity -> DataBufferUtils.join(entity.getBody()).map(GLDataBufferInputStream::bytesOf).defaultIfEmpty(new byte[0]).map(bytes -> convert(entity.getStatusCode().value(), entity.getHeaders(), new ByteArrayInputStream(bytes))));',
      ],
    ),
  ]);

  const inserter = 'BodyInserter<?, ? super ClientHttpRequest>';
  final body = _cg.method(
    returnType: 'private $inserter',
    methodName: 'body',
    arguments: ['RestRequest request', 'Map<String, String> headers'],
    statements: _restBodyStatements(
      nullBody: 'null',
      json: 'BodyInserters.fromValue(((RestBody.Json) body).getJson())',
      form: 'BodyInserters.fromValue(form.isEmpty() ? "" : form.substring(1))',
      raw: 'resource(GLMultipartBody.withProgress(upload.getStream(), upload.getLength(), request.getOnSendProgress()), upload.getLength())',
      multipartResult: 'resource(multipart.getStream(request.getOnSendProgress()), multipart.getLength())',
    ),
  );

  final resource = _cg.method(
    returnType: 'private static $inserter',
    methodName: 'resource',
    arguments: ['InputStream in', 'long length'],
    statements: [
      _cg.ifStatement(condition: 'length == 0', ifBlockStatements: ['return BodyInserters.fromValue(new byte[0]);']),
      'return BodyInserters.fromResource(new InputStreamResource(in) ${_cg.block(['@Override public long contentLength() { return length; }'])});',
    ],
  );

  final convert = _restConvertMethod(
    ['headers.forEach((name, values) -> flat.put(name.toLowerCase(Locale.ROOT), String.join(",", values)));'],
  );

  final constructors = _members([
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl'],
      statements: ['this(baseUrl, () -> null);'],
    ),
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl', 'Supplier<Map<String, String>> headersProvider'],
      statements: [
        'this(baseUrl, headersProvider, WebClient.builder().clientConnector(new ReactorClientHttpConnector(reactor.netty.http.client.HttpClient.create().followRedirect(true))).build());',
      ],
    ),
    _cg.createMethod(
      returnType: 'public',
      methodName: 'DefaultGraphLinkRestAdapter',
      arguments: ['String baseUrl', 'Supplier<Map<String, String>> headersProvider', 'WebClient webClient'],
      statements: [
        'this.baseUrl = baseUrl;',
        'this.headersProvider = headersProvider;',
        'this.webClient = webClient.mutate().filter(GLWebClientContentType.sanitize()).build();',
      ],
    ),
  ]);

  return '${_cg.createClass(
    className: 'DefaultGraphLinkRestAdapter',
    interfaceNames: ['GLRestAdapter'],
    statements: [
      _members([
        'private final String baseUrl;',
        'private final Supplier<Map<String, String>> headersProvider;',
        'private final WebClient webClient;',
        constructors,
        execute,
        _restUrlMethod(),
        _restQueryStringMethod(),
        body,
        resource,
        convert,
      ]),
    ],
  )}\n';
}
