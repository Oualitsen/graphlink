import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';

class JavaClientAdaptersSerializer {
  final JavaClientSerializer _client;
  JavaClientAdaptersSerializer(this._client);

  GLParser get _grammar => _client.grammar;
  JavaCodeGenUtils get codeGenUtils => _client.codeGenUtils;
  JavaReactiveFlavor get flavor => _client.flavor;
  GLSerializer get serializer => _client.serializer;
  String _wrapSingle(String inner) => _client.wrapSingle(inner);
  void _requireGet() => _client.requireGet();

  /// Raw-Java reactive variant of the `GraphLinkClientAdapter` functional
  /// interface whose `execute` returns the flavor's deferred-single type
  /// (`Mono`/`Single`/`Uni`<String>). Used in place of the GraphQL-derived
  /// `String`-returning interface when an async style is selected.
  GLClassModel generateReactiveClientAdapterInterfaceFile() {
    final ret = '${flavor.single}<String>';
    final params = _grammar.operationNameAsParameter
        ? 'String payload, String operationName'
        : 'String payload';
    final body = '@FunctionalInterface\n${codeGenUtils.createInterface(
      interfaceName: 'GraphLinkClientAdapter',
      statements: ['$ret execute($params);'],
    )}';
    return GLClassModel(
      imports: [...flavor.singleImports],
      body: body,
    );
  }

  GLClassModel generateJsonCodecFile(String codec, String importPrefix) =>
      GLClassModel(
        imports: [
          codec == 'jackson'
              ? 'com.fasterxml.jackson.databind.ObjectMapper'
              : 'com.google.gson.Gson',
          JavaImports.map,
        ],
        importDepencies: [
          _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: codec == 'jackson' ? jacksonCodecClass : gsonCodecClass,
      );

  GLClassModel generateDefaultClientAdapterFile(
          String flavor, String importPrefix) =>
      GLClassModel(
        imports: [
          ...(flavor == 'okhttp'
              ? [
                  'okhttp3.MediaType',
                  'okhttp3.OkHttpClient',
                  'okhttp3.Request',
                  'okhttp3.RequestBody',
                  'okhttp3.Response',
                  if (_grammar.hasUploadMutations) 'okhttp3.MultipartBody',
                ]
              : [
                  'java.net.URI',
                  'java.net.http.HttpClient',
                  'java.net.http.HttpRequest',
                  'java.net.http.HttpResponse',
                ]),
          ...([
            JavaImports.map,
            JavaImports.supplier,
            if (_grammar.hasUploadMutations) JavaImports.ioException,
          ]),
        ],
        importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
        body: _grammar.hasUploadMutations
            ? (flavor == 'okhttp'
                ? defaultClientAdapterOkHttpWithUpload(_grammar.operationNameAsParameter)
                : defaultClientAdapterJava11WithUpload(_grammar.operationNameAsParameter))
            : (flavor == 'okhttp'
                ? defaultClientAdapterOkHttp(_grammar.operationNameAsParameter)
                : defaultClientAdapterJava11(_grammar.operationNameAsParameter)),
      );

  /// Reactive `DefaultGraphLinkClientAdapter` whose `execute` returns the
  /// flavor's deferred-single type. Uses the JDK `HttpClient.sendAsync`
  /// universal bridge (zero extra HTTP dependency) — native framework
  /// transports (WebClient, Vert.x Mutiny) can be added as follow-up flavors.
  GLClassModel generateReactiveDefaultClientAdapterFile() {
    final ret = '${flavor.single}<String>';
    final params = _grammar.operationNameAsParameter
        ? 'String payload, String operationName'
        : 'String payload';
    const future =
        'httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString()).thenApply(HttpResponse::body)';
    final hasUploads = _grammar.hasUploadMutations;
    final body = codeGenUtils.createClass(
      className: 'DefaultGraphLinkClientAdapter',
      interfaceNames: [
        'GraphLinkClientAdapter',
        if (hasUploads) 'GraphLinkMultipartAdapter',
      ],
      statements: [
        'private final String url;',
        'private final HttpClient httpClient;',
        'private final Supplier<Map<String, String>> headersProvider;',
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkClientAdapter',
          arguments: ['String url'],
          statements: ['this(url, () -> null);'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkClientAdapter',
          arguments: ['String url', 'Supplier<Map<String, String>> headersProvider'],
          statements: [
            'this.url = url;',
            'this.headersProvider = headersProvider;',
            'this.httpClient = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build();',
          ],
        ),
        '',
        '@Override\n${codeGenUtils.createMethod(
          returnType: 'public $ret',
          methodName: 'execute',
          arguments: [params],
          statements: [
            'HttpRequest.Builder builder = HttpRequest.newBuilder()\n    .uri(URI.create(url))\n    .header("Content-Type", "application/json")\n    .POST(HttpRequest.BodyPublishers.ofString(payload));',
            'Map<String, String> headers = headersProvider.get();',
            codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: [
                codeGenUtils.forEachLoop(
                  variable: 'entry',
                  iterable: 'headers.entrySet()',
                  statements: ['builder.header(entry.getKey(), entry.getValue());'],
                ),
              ],
            ),
            'HttpRequest request = builder.build();',
            'return ${flavor.bridgeFuture(future)};',
          ],
        )}',
        if (hasUploads) ..._reactiveMultipartMembers(ret),
      ],
    );
    return GLClassModel(
      imports: [
        'java.net.URI',
        'java.net.http.HttpClient',
        'java.net.http.HttpRequest',
        'java.net.http.HttpResponse',
        JavaImports.map,
        JavaImports.supplier,
        if (hasUploads) JavaImports.ioException,
        ...flavor.singleImports,
      ],
      // GraphLinkMultipartAdapter lives in the same `client` package, so it
      // needs no import dependency (it also has no grammar token).
      importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
      body: body,
    );
  }

  /// Reactive `DefaultGraphLinkGetAdapter` over the JDK `HttpClient.sendAsync`
  /// bridge, the same transport as [generateReactiveDefaultClientAdapterFile].
  GLClassModel generateReactiveDefaultGetAdapterFile() {
    _requireGet();
    final params = _grammar.operationNameAsParameter
        ? 'String payload, String operationName'
        : 'String payload';
    final send =
        'httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString()).thenApply(response -> {\n'
        '${[
      codeGenUtils.ifStatement(
        condition: 'response.statusCode() == 405',
        ifBlockStatements: ['throw new GraphLinkGetNotSupported("GET is not allowed");'],
      ),
      'return response.body();',
    ].join('\n').ident()}\n})';
    final body = codeGenUtils.createClass(
      className: 'DefaultGraphLinkGetAdapter',
      interfaceNames: ['GraphLinkClientAdapter'],
      statements: [
        'private final String url;',
        'private final Supplier<Map<String, String>> headersProvider;',
        'private final GraphLinkJsonEncoder encoder;',
        'private final GraphLinkJsonDecoder decoder;',
        'private final HttpClient httpClient;',
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkGetAdapter',
          arguments: ['String url', 'GraphLinkJsonEncoder encoder', 'GraphLinkJsonDecoder decoder'],
          statements: ['this(url, () -> null, encoder, decoder);'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkGetAdapter',
          arguments: [
            'String url',
            'Supplier<Map<String, String>> headersProvider',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: [
            'this.url = url;',
            'this.headersProvider = headersProvider;',
            'this.encoder = encoder;',
            'this.decoder = decoder;',
            'this.httpClient = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build();',
          ],
        ),
        '',
        '@Override\n${codeGenUtils.createMethod(
          returnType: 'public ${_wrapSingle('String')}',
          methodName: 'execute',
          arguments: [params],
          statements: [
            'String separator = url.contains("?") ? "&" : "?";',
            'HttpRequest.Builder builder = HttpRequest.newBuilder()\n    .uri(URI.create(url + separator + GraphLinkGetRequest.queryString(payload, decoder, encoder)))\n    .GET();',
            'Map<String, String> headers = headersProvider.get();',
            codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: [
                codeGenUtils.forEachLoop(
                  variable: 'entry',
                  iterable: 'headers.entrySet()',
                  statements: ['builder.header(entry.getKey(), entry.getValue());'],
                ),
              ],
            ),
            'HttpRequest request = builder.build();',
            'return ${flavor.bridgeFuture(send)};',
          ],
        )}',
      ],
    );
    return GLClassModel(
      imports: [
        'java.net.URI',
        'java.net.http.HttpClient',
        'java.net.http.HttpRequest',
        'java.net.http.HttpResponse',
        JavaImports.map,
        JavaImports.supplier,
        ...flavor.singleImports,
      ],
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkClientAdapter')!,
        _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
      ],
      body: body,
    );
  }

  /// WebClient flavor of [generateReactiveDefaultGetAdapterFile] (Reactor only).
  GLClassModel generateWebClientDefaultGetAdapterFile() {
    _requireGet();
    final params = _grammar.operationNameAsParameter
        ? 'String payload, String operationName'
        : 'String payload';
    final body = codeGenUtils.createClass(
      className: 'DefaultGraphLinkGetAdapter',
      interfaceNames: ['GraphLinkClientAdapter'],
      statements: [
        'private final String url;',
        'private final WebClient webClient;',
        'private final Supplier<Map<String, String>> headersProvider;',
        'private final GraphLinkJsonEncoder encoder;',
        'private final GraphLinkJsonDecoder decoder;',
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkGetAdapter',
          arguments: ['String url', 'GraphLinkJsonEncoder encoder', 'GraphLinkJsonDecoder decoder'],
          statements: ['this(url, () -> null, encoder, decoder);'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkGetAdapter',
          arguments: [
            'String url',
            'Supplier<Map<String, String>> headersProvider',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: ['this(url, headersProvider, encoder, decoder, WebClient.create());'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkGetAdapter',
          arguments: [
            'String url',
            'Supplier<Map<String, String>> headersProvider',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
            'WebClient webClient',
          ],
          statements: [
            'this.url = url;',
            'this.headersProvider = headersProvider;',
            'this.encoder = encoder;',
            'this.decoder = decoder;',
            'this.webClient = webClient;',
          ],
        ),
        '',
        '@Override\n${codeGenUtils.createMethod(
          returnType: 'public Mono<String>',
          methodName: 'execute',
          arguments: [params],
          statements: [
            'String separator = url.contains("?") ? "&" : "?";',
            'WebClient.RequestHeadersSpec<?> request = webClient.get()\n    .uri(URI.create(url + separator + GraphLinkGetRequest.queryString(payload, decoder, encoder)));',
            'Map<String, String> headers = headersProvider.get();',
            codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: ['request = request.headers(h -> headers.forEach(h::add));'],
            ),
            'return request.retrieve()\n    .onStatus(status -> status.value() == 405, response -> Mono.error(new GraphLinkGetNotSupported("GET is not allowed")))\n    .bodyToMono(String.class);',
          ],
        )}',
      ],
    );
    return GLClassModel(
      imports: [
        'org.springframework.web.reactive.function.client.WebClient',
        'java.net.URI',
        JavaImports.map,
        JavaImports.supplier,
        'reactor.core.publisher.Mono',
      ],
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkClientAdapter')!,
        _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
      ],
      body: body,
    );
  }

  /// Native Spring WebClient reactive adapter (Reactor only). `execute` and
  /// `executeMultipart` return `Mono<String>` directly — no bridge. Multipart
  /// streams a `GLMultipartBody` through `BodyInserters.fromResource`.
  GLClassModel generateWebClientDefaultClientAdapterFile() {
    final opNameUri = _grammar.operationNameAsParameter
        ? 'url + "?operationName=" + operationName'
        : 'url';
    final params = _grammar.operationNameAsParameter
        ? 'String payload, String operationName'
        : 'String payload';
    final hasUploads = _grammar.hasUploadMutations;
    final body = codeGenUtils.createClass(
      className: 'DefaultGraphLinkClientAdapter',
      interfaceNames: [
        'GraphLinkClientAdapter',
        if (hasUploads) 'GraphLinkMultipartAdapter',
      ],
      statements: [
        'private final String url;',
        'private final WebClient webClient;',
        'private final Supplier<Map<String, String>> headersProvider;',
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkClientAdapter',
          arguments: ['String url'],
          statements: ['this(url, () -> null);'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkClientAdapter',
          arguments: ['String url', 'Supplier<Map<String, String>> headersProvider'],
          statements: ['${codeGenUtils.callExpression('this', ['url', 'headersProvider', 'WebClient.create()'])};'],
        ),
        '',
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: 'DefaultGraphLinkClientAdapter',
          arguments: [
            'String url',
            'Supplier<Map<String, String>> headersProvider',
            'WebClient webClient',
          ],
          statements: [
            'this.url = url;',
            'this.headersProvider = headersProvider;',
            'this.webClient = webClient;',
          ],
        ),
        '',
        '@Override\n${codeGenUtils.createMethod(
          returnType: 'public Mono<String>',
          methodName: 'execute',
          arguments: [params],
          statements: [
            'WebClient.RequestBodySpec request = webClient.post()\n    .uri($opNameUri)\n    .contentType(MediaType.APPLICATION_JSON);',
            'Map<String, String> headers = headersProvider.get();',
            codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: ['headers.forEach(request::header);'],
            ),
            'return request.bodyValue(payload).retrieve().bodyToMono(String.class);',
          ],
        )}',
        if (hasUploads) ..._webClientMultipartMembers(),
      ],
    );
    return GLClassModel(
      imports: [
        'org.springframework.web.reactive.function.client.WebClient',
        'org.springframework.http.MediaType',
        if (hasUploads)
          'org.springframework.web.reactive.function.BodyInserters',
        if (hasUploads) 'org.springframework.core.io.InputStreamResource',
        JavaImports.map,
        JavaImports.supplier,
        'reactor.core.publisher.Mono',
      ],
      importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
      body: body,
    );
  }

  /// WebClient multipart `executeMultipart` body (GraphQL multipart spec).
  /// The body is streamed lazily through an `InputStreamResource`.
  List<String> _webClientMultipartMembers() {
    final executeMultipartMethod = '@Override\n${codeGenUtils.createMethod(
      returnType: 'public Mono<String>',
      methodName: 'executeMultipart',
      arguments: [
        'String operations',
        'String mapJson',
        'Map<String, GLUpload> files',
        'UploadProgressCallback onProgress',
      ],
      statements: [
        'GLMultipartBody body = GLMultipartBody.ofGraphQL(operations, mapJson, files);',
        'InputStreamResource resource = new InputStreamResource(body.getStream(onProgress)) ${codeGenUtils.block([
              '@Override public long contentLength() { return body.getLength(); }',
            ])};',
        'WebClient.RequestBodySpec request = webClient.post()\n    .uri(url)\n    .contentType(MediaType.parseMediaType(body.getContentType()));',
        'Map<String, String> headers = headersProvider.get();',
        codeGenUtils.ifStatement(
          condition: 'headers != null',
          ifBlockStatements: ['headers.forEach(request::header);'],
        ),
        'return request.body(BodyInserters.fromResource(resource)).retrieve().bodyToMono(String.class);',
      ],
    )}';

    return ['', executeMultipartMethod];
  }

  /// The reactive `executeMultipart` (GraphQL multipart spec over JDK
  /// `sendAsync`, bridged to the flavor single). The body is streamed lazily.
  List<String> _reactiveMultipartMembers(String ret) {
    const mpFuture =
        'httpClient.sendAsync(mpRequest, HttpResponse.BodyHandlers.ofString()).thenApply(HttpResponse::body)';

    final executeMultipartMethod = '@Override\n${codeGenUtils.createMethod(
      returnType: 'public $ret',
      methodName: 'executeMultipart',
      arguments: [
        'String operations',
        'String mapJson',
        'Map<String, GLUpload> files',
        'UploadProgressCallback onProgress',
      ],
      statements: [
        'GLMultipartBody mpBody = GLMultipartBody.ofGraphQL(operations, mapJson, files);',
        'java.io.InputStream mpStream = mpBody.getStream(onProgress);',
        'HttpRequest.BodyPublisher publisher = HttpRequest.BodyPublishers.ofInputStream(() -> mpStream);',
        codeGenUtils.ifStatement(
          condition: 'mpBody.getLength() >= 0',
          ifBlockStatements: ['publisher = HttpRequest.BodyPublishers.fromPublisher(publisher, mpBody.getLength());'],
        ),
        'HttpRequest.Builder mpBuilder = HttpRequest.newBuilder()\n    .uri(URI.create(url))\n    .header("Content-Type", mpBody.getContentType())\n    .POST(publisher);',
        'Map<String, String> mpHeaders = headersProvider.get();',
        codeGenUtils.ifStatement(
          condition: 'mpHeaders != null',
          ifBlockStatements: [
            codeGenUtils.forEachLoop(
              variable: 'entry',
              iterable: 'mpHeaders.entrySet()',
              statements: ['mpBuilder.header(entry.getKey(), entry.getValue());'],
            ),
          ],
        ),
        'HttpRequest mpRequest = mpBuilder.build();',
        'return ${flavor.bridgeFuture(mpFuture)};',
      ],
    )}';

    return ['', executeMultipartMethod];
  }

  GLClassModel generateDefaultWebSocketAdapterFile(
          String flavor, String importPrefix) =>
      GLClassModel(
        imports: [
          ...(flavor == 'okhttp'
              ? [
                  'okhttp3.OkHttpClient',
                  'okhttp3.Request',
                  'okhttp3.Response',
                  'okhttp3.WebSocket',
                  'okhttp3.WebSocketListener',
                ]
              : [
                  'java.net.URI',
                  'java.net.http.HttpClient',
                  'java.net.http.WebSocket',
                  'java.util.concurrent.CompletableFuture',
                  'java.util.concurrent.CompletionStage',
                ]),
          ...([
            JavaImports.hashMap,
            JavaImports.list,
            JavaImports.map,
            'java.util.concurrent.Executors',
            'java.util.concurrent.ScheduledExecutorService',
            'java.util.concurrent.TimeUnit',
            'java.util.concurrent.atomic.AtomicInteger',
            JavaImports.consumer,
            JavaImports.supplier,
          ]),
        ],
        body: flavor == 'okhttp'
            ? defaultWsAdapterOkHttp
            : defaultWsAdapterJava11,
      );
}
