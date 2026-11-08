import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_runtime_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_adapters_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_rest_operation_serializer.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';




class JavaClientSerializer extends GLClientSerializer {
  final GLParser _grammar;
  GLParser get grammar => _grammar;
  late final runtime = JavaClientRuntimeSerializer(this);
  late final adapters = JavaClientAdaptersSerializer(this);
  final codeGenUtils = JavaCodeGenUtils();
  final JavaJsonCodec jsonCodec;
  final JavaReactiveFlavor flavor;
  final JavaRestHttpAdapter restHttpAdapter;
  final JavaReactiveHttpClient reactiveHttpClient;

  late final JavaClientContext _ctx;
  late final JavaClientOperationSerializer _opSer;
  late final JavaRestOperationSerializer _restSer;
  GLImportContainer? _activeContainer;

  JavaClientSerializer(this._grammar, GLSerializer serializer,
      {this.jsonCodec = JavaJsonCodec.jackson,
      this.flavor = JavaReactiveFlavor.blocking,
      this.restHttpAdapter = JavaRestHttpAdapter.jdk,
      this.reactiveHttpClient = JavaReactiveHttpClient.jdk,
      bool commaQueryLists = false,
      bool bracketFormNesting = false})
      : super(serializer, GLGraphqlSerializer(_grammar, false)) {
    _ctx = JavaClientContext(_grammar, codeGenUtils, gqlSerializer, serializer,
        flavor: flavor);
    _opSer = JavaClientOperationSerializer(_ctx);
    _restSer = JavaRestOperationSerializer(
      _grammar,
      codeGenUtils,
      serializer as JavaSerializer,
      flavor,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _grammar.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) =>
      _grammar.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get hasRest => _grammar.restOperations.isNotEmpty;

  bool get _hasGraphQL => GLQueryType.values.any(_grammar.hasQueryType);

  bool get generatesRestAdapter => hasRest && restHttpAdapter != JavaRestHttpAdapter.none;

  bool get restAdapterUsesWebClient =>
      generatesRestAdapter && flavor.isReactive && reactiveHttpClient == JavaReactiveHttpClient.webclient;

  bool get _restOnly => hasRest && !_hasGraphQL;

  List<String> get _restCtorParams => !hasRest
      ? const []
      : generatesRestAdapter
          ? const ['String restBaseUrl']
          : const ['GLRestAdapter restAdapter'];

  List<String> get _restNames => !hasRest ? const [] : [generatesRestAdapter ? 'restBaseUrl' : 'restAdapter'];

  List<String> _withRest(List<String> args, {bool headers = false, String? expr}) {
    if (!hasRest) return args;
    final at = args.indexOf('encoder');
    final restExpr = expr ??
        (generatesRestAdapter
            ? 'new DefaultGraphLinkRestAdapter(restBaseUrl${headers ? ', headersProvider' : ''})'
            : 'restAdapter');
    return [...args.sublist(0, at), restExpr, ...args.sublist(at)];
  }

  Set<GLToken> _restTokens(GLQueryType type) {
    final tokens = <GLToken>{};
    for (final operation in _restOperations(type)) {
      final names = [
        operation.field.type.firstType.token,
        ...operation.arguments.map((a) => a.argument.type.firstType.token),
      ];
      for (final name in names) {
        if (_grammar.isRestImportableType(name)) {
          final token = _grammar.getTokenByKey(name);
          if (token != null) tokens.add(token);
        }
      }
    }
    return tokens;
  }

  @override
  String renderQueryMethod(GLQueryDefinition def) =>
      _opSer.queryToMethod(def, _activeContainer!);

  @override
  String renderMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def, _activeContainer!);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def, _activeContainer!);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) =>
      _opSer.subscriptionToMethod(def, _activeContainer!);

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(
        imports: [
          JavaImports.inputStream,
          JavaImports.byteArrayInputStream,
          JavaImports.fileInputStream,
          JavaImports.file,
          JavaImports.ioException,
        ],
        body: javaGLUpload,
      );

  GLClassModel generateMultipartBodyFile() => const GLClassModel(
        imports: [
          JavaImports.inputStream,
          JavaImports.byteArrayInputStream,
          JavaImports.ioException,
          JavaImports.list,
          JavaImports.arrayList,
          'java.io.SequenceInputStream',
          'java.nio.charset.StandardCharsets',
          'java.util.Collections',
          'java.util.UUID',
          JavaImports.map,
        ],
        body: javaGLMultipartBody,
      );


  @override
  GLClassModel generateClient({bool hasDefaultAdapters = true}) {
    final container = GLImportContainer();
    container.imports.addAll([
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.objects,
      JavaImports.supplier,
    ]);
    container.importDepencies.addAll([
      _grammar.getTokenByKey('GraphLinkClientAdapter')!,
      _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
    ]);
    final bodyBuf = StringBuffer();
    bodyBuf
        .writeln(codeGenUtils.createClass(className: clientName, statements: [
      'private final Map<String, String> $svFragmentMap = new HashMap<>();',
      if (_hasOperations(GLQueryType.query))
        'public final ${classNameFromType(GLQueryType.query)} queries;',
      if (_hasOperations(GLQueryType.mutation))
        'public final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_grammar.hasSubscriptions)
        'public final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      codeGenUtils.createMethod(
        methodName: clientName,
        returnType: 'public',
        statements: [
          '${codeGenUtils.callExpression('this', _withRest([
            if (_hasGraphQL) 'adapter',
            if (_hasGraphQL && _grammar.persistedQueriesUseGet) 'getAdapter',
            if (_grammar.hasUploadMutations) 'multipartAdapter',
            'encoder',
            'decoder',
            'null',
            if (_grammar.hasSubscriptions) 'wsAdapter',
          ], expr: 'restAdapter'))};',
        ],
        arguments: [
          _adapterDeclaration(false),
          if (_grammar.hasSubscriptions) 'GraphLinkWebSocketAdapter wsAdapter'
        ],
      ),
      codeGenUtils.createMethod(
        returnType: "public",
        methodName: clientName,
        arguments: [
          _adapterDeclaration(true),
          if (_grammar.hasSubscriptions) 'GraphLinkWebSocketAdapter wsAdapter'
        ],
        statements: [
          if (_restOnly) ...[
            'GraphLinkClientAdapter adapter = new GraphLinkNoGraphQL();',
            if (_grammar.persistedQueriesUseGet) 'GraphLinkClientAdapter getAdapter = adapter;',
          ],
          codeGenUtils.ifStatement(
            condition: 'store == null',
            ifBlockStatements: ['store = new InMemoryGraphLinkCacheStore();'],
          ),
          "Objects.requireNonNull(adapter);",
          if (hasRest) "Objects.requireNonNull(restAdapter);",
          "Objects.requireNonNull(encoder);",
          "Objects.requireNonNull(decoder);",
          if (_grammar.hasSubscriptions) "Objects.requireNonNull(wsAdapter);",
          if (_hasOperations(GLQueryType.query))
            "queries = new ${classNameFromType(GLQueryType.query)}(adapter, ${_getArg}${_restArg(GLQueryType.query)}$svFragmentMap, encoder, decoder, store);",
          if (_hasOperations(GLQueryType.mutation))
            "mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, ${_getArg}${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}${_restArg(GLQueryType.mutation)}$svFragmentMap, encoder, decoder, store);",
          if (_grammar.hasSubscriptions)
            "subscriptions = new ${classNameFromType(GLQueryType.subscription)}(adapter, wsAdapter, $svFragmentMap, encoder, decoder, store);",
          ..._grammar.usedFragments
              .where((value) => !oversizedFragmentNames.contains(value.tokenInfo.token))
              .map((value) =>
                  '$svFragmentMap.put("${value.tokenInfo}", "${gqlSerializer.serializeFragmentDefinitionBase(value)}");'),
        ],
      ),
      if (hasDefaultAdapters) ..._convenienceConstructors(),
    ]));
    if (_opSer.serializeSubscriptions().isNotEmpty) {
      bodyBuf.writeln(_opSer.serializeSubscriptions().ident());
    }

    return GLClassModel(
      imports: [
        ...container.imports,
      ],
      importDepencies: container.importDepencies,
      body: bodyBuf.toString(),
    );
  }

  String get _getArg => _grammar.persistedQueriesUseGet ? 'getAdapter, ' : '';

  String _restArg(GLQueryType type) => _restOperations(type).isEmpty ? '' : 'restAdapter, ';

  List<String> _getAdapterExpr(String urlArgs) => [
        if (_grammar.persistedQueriesUseGet) 'new DefaultGraphLinkGetAdapter($urlArgs, encoder, decoder)',
      ];

  List<String> _convenienceConstructors() {
    final encoderDecoderArgs = [
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
    ];
    final defaultCodec = jsonCodec == JavaJsonCodec.jackson
        ? 'new JacksonGraphLinkJsonCodec()'
        : jsonCodec == JavaJsonCodec.gson
            ? 'new GsonGraphLinkJsonCodec()'
            : null;

    if (_restOnly) return _restOnlyConvenienceConstructors(encoderDecoderArgs, defaultCodec);

    if (!_grammar.hasSubscriptions) {
      return [
        // When uploads are present, an intermediate constructor takes
        // DefaultGraphLinkClientAdapter (which implements both interfaces) so
        // the url+$svEncoder constructors can delegate with this() as the first
        // statement while only constructing one $svAdapter instance.
        if (_grammar.hasUploadMutations)
          codeGenUtils.createMethod(
            returnType: 'public',
            methodName: clientName,
            arguments: [
              'DefaultGraphLinkClientAdapter adapter',
              if (_grammar.persistedQueriesUseGet) 'GraphLinkClientAdapter getAdapter',
              if (hasRest) 'GLRestAdapter restAdapter',
              ...encoderDecoderArgs
            ],
            statements: ['${codeGenUtils.callExpression('this', _withRest(['adapter', if (_grammar.persistedQueriesUseGet) 'getAdapter', 'adapter', 'encoder', 'decoder', 'null'], expr: 'restAdapter'))};'],
          ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url', ..._restCtorParams, ...encoderDecoderArgs],
          statements: _grammar.hasUploadMutations
              ? [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder'], headers: false))};'
                ]
              : [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null'], headers: false))};'
                ],
        ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: [
            'String url',
            ..._restCtorParams,
            'Supplier<Map<String, String>> headersProvider',
            ...encoderDecoderArgs
          ],
          statements: _grammar.hasUploadMutations
              ? [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder'], headers: true))};'
                ]
              : [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null'], headers: true))};'
                ],
        ),
        if (defaultCodec != null)
          codeGenUtils.createMethod(
            returnType: 'public',
            methodName: clientName,
            arguments: ['String url', ..._restCtorParams],
            statements: ['${codeGenUtils.callExpression('this', ['url', ..._restNames, '$defaultCodec', '$defaultCodec'])};'],
          ),
      ];
    }

    return [
      // Intermediate constructor for upload case (no-subscription path above has its own)
      if (_grammar.hasUploadMutations)
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: [
            'DefaultGraphLinkClientAdapter adapter',
            if (_grammar.persistedQueriesUseGet) 'GraphLinkClientAdapter getAdapter',
            if (hasRest) 'GLRestAdapter restAdapter',
            ...encoderDecoderArgs,
            'GraphLinkWebSocketAdapter wsAdapter'
          ],
          statements: [
            '${codeGenUtils.callExpression('this', _withRest(['adapter', if (_grammar.persistedQueriesUseGet) 'getAdapter', 'adapter', 'encoder', 'decoder', 'null', 'wsAdapter'], expr: 'restAdapter'))};'
          ],
        ),
      //Single URL, ws derived by replacing http→ws
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String url', ..._restCtorParams, ...encoderDecoderArgs],
        statements: _grammar.hasUploadMutations
            ? [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"))'], headers: false))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"))'], headers: false))};'
              ],
      ),
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: [
          'String url',
          ..._restCtorParams,
          'Supplier<Map<String, String>> headersProvider',
          ...encoderDecoderArgs
        ],
        statements: _grammar.hasUploadMutations
            ? [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider)'], headers: true))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider)'], headers: true))};'
              ],
      ),
      // Option B — explicit wsUrl
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String url', ..._restCtorParams, 'String wsUrl', ...encoderDecoderArgs],
        statements: _grammar.hasUploadMutations
            ? [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(wsUrl)'], headers: false))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, decoder)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(wsUrl)'], headers: false))};'
              ],
      ),
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: [
          'String url',
          ..._restCtorParams,
          'String wsUrl',
          'Supplier<Map<String, String>> headersProvider',
          ...encoderDecoderArgs
        ],
        statements: _grammar.hasUploadMutations
            ? [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)'], headers: true))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider, decoder)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)'], headers: true))};'
              ],
      ),
      if (defaultCodec != null) ...[
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url', ..._restCtorParams],
          statements: ['${codeGenUtils.callExpression('this', ['url', ..._restNames, '$defaultCodec', '$defaultCodec'])};'],
        ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url', ..._restCtorParams, 'String wsUrl'],
          statements: ['${codeGenUtils.callExpression('this', ['url', ..._restNames, 'wsUrl', '$defaultCodec', '$defaultCodec'])};'],
        ),
      ],
    ];
  }

  List<String> _restOnlyConvenienceConstructors(List<String> encoderDecoderArgs, String? defaultCodec) {
    if (!generatesRestAdapter) return const [];
    return [
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String restBaseUrl', ...encoderDecoderArgs],
        statements: ['${codeGenUtils.callExpression('this', ['new DefaultGraphLinkRestAdapter(restBaseUrl)', 'encoder', 'decoder'])};'],
      ),
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String restBaseUrl', 'Supplier<Map<String, String>> headersProvider', ...encoderDecoderArgs],
        statements: ['${codeGenUtils.callExpression('this', ['new DefaultGraphLinkRestAdapter(restBaseUrl, headersProvider)', 'encoder', 'decoder'])};'],
      ),
      if (defaultCodec != null)
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String restBaseUrl'],
          statements: ['${codeGenUtils.callExpression('this', ['restBaseUrl', defaultCodec, defaultCodec])};'],
        ),
    ];
  }

  bool get needsWebClientContentType =>
      flavor.isReactive && reactiveHttpClient == JavaReactiveHttpClient.webclient && (restAdapterUsesWebClient || _hasGraphQL);

  Map<String, GLClassModel> generateWebClientFiles() => {
        if (needsWebClientContentType)
          'GLWebClientContentType.java': GLClassModel(
            imports: [
              'java.util.Arrays',
              'java.util.Locale',
              'java.util.stream.Collectors',
              'org.springframework.http.HttpHeaders',
              'org.springframework.http.InvalidMediaTypeException',
              'org.springframework.http.MediaType',
              'org.springframework.web.reactive.function.client.ClientResponse',
              'org.springframework.web.reactive.function.client.ExchangeFilterFunction',
            ],
            body: javaGLWebClientContentType(),
          ),
      };

  // ── REST files ──────────────────────────────────────────────────────────────

  Map<String, GLClassModel> generateRestFiles() {
    final reactiveImports = [...flavor.singleImports, ...flavor.optionalTypeImports];
    return {
      'RestBody.java': const GLClassModel(imports: [JavaImports.list, JavaImports.map], body: javaRestBody),
      'RestPart.java': const GLClassModel(body: javaRestPart),
      'RestRequest.java': const GLClassModel(imports: [JavaImports.list, JavaImports.map], body: javaRestRequest),
      'RestResponse.java': const GLClassModel(imports: [
        'java.io.ByteArrayInputStream',
        'java.io.Closeable',
        'java.io.IOException',
        'java.io.InputStream',
        'java.io.OutputStream',
        'java.io.UncheckedIOException',
        'java.nio.charset.StandardCharsets',
        JavaImports.collections,
        JavaImports.map,
      ], body: javaRestResponse),
      'RestError.java': const GLClassModel(imports: [JavaImports.map], body: javaRestError),
      'DownloadProgressCallback.java': const GLClassModel(body: javaDownloadProgressCallback),
      'GLDownload.java': const GLClassModel(imports: [
        'java.io.Closeable',
        'java.io.IOException',
        'java.io.InputStream',
        'java.io.UncheckedIOException',
        'java.net.URLDecoder',
        'java.nio.charset.StandardCharsets',
        JavaImports.map,
        'java.util.regex.Matcher',
        'java.util.regex.Pattern',
      ], body: javaGLDownload),
      'GLRestAdapter.java': GLClassModel(imports: flavor.singleImports, body: javaRestAdapterInterface(flavor)),
      'GraphLinkRestUtils.java': const GLClassModel(imports: [
        'java.nio.charset.StandardCharsets',
        JavaImports.arrayList,
        JavaImports.collections,
        JavaImports.linkedHashMap,
        JavaImports.list,
        JavaImports.map,
        JavaImports.treeMap,
        'java.util.StringJoiner',
      ], body: javaRestUtils),
      'GraphLinkRestResolver.java': GLClassModel(
        imports: [
          JavaImports.function,
          JavaImports.supplier,
          JavaImports.hashMap,
          JavaImports.list,
          JavaImports.map,
          JavaImports.optional,
          ...reactiveImports,
        ],
        importDepencies: [
          _grammar.getTokenByKey('GraphLinkClientAdapter')!,
          _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: javaRestResolver(flavor, withGetAdapter: _grammar.persistedQueriesUseGet),
      ),
      if (generatesRestAdapter)
        'DefaultGraphLinkRestAdapter.java': GLClassModel(
          imports: restAdapterUsesWebClient
              ? [
                  'java.io.ByteArrayInputStream',
                  'java.io.IOException',
                  'java.io.InputStream',
                  'java.io.UncheckedIOException',
                  'java.net.URI',
                  JavaImports.linkedHashMap,
                  JavaImports.list,
                  JavaImports.map,
                  JavaImports.supplier,
                  'java.util.Locale',
                  'java.util.StringJoiner',
                  'java.util.zip.GZIPInputStream',
                  'java.util.zip.InflaterInputStream',
                  'org.springframework.core.io.InputStreamResource',
                  'org.springframework.core.io.buffer.DataBuffer',
                  'org.springframework.core.io.buffer.DataBufferUtils',
                  'org.springframework.http.HttpHeaders',
                  'org.springframework.http.HttpMethod',
                  'org.springframework.http.client.reactive.ClientHttpRequest',
                  'org.springframework.http.client.reactive.ReactorClientHttpConnector',
                  'org.springframework.web.reactive.function.BodyInserter',
                  'org.springframework.web.reactive.function.BodyInserters',
                  'org.springframework.web.reactive.function.client.WebClient',
                  'reactor.core.scheduler.Schedulers',
                  ...flavor.singleImports,
                ]
              : [
            'java.io.ByteArrayInputStream',
            'java.io.IOException',
            'java.io.InputStream',
            'java.io.SequenceInputStream',
            'java.io.UncheckedIOException',
            'java.net.URI',
            'java.net.http.HttpClient',
            'java.net.http.HttpHeaders',
            'java.net.http.HttpRequest',
            'java.net.http.HttpResponse',
            'java.nio.charset.StandardCharsets',
            JavaImports.arrayList,
            JavaImports.collections,
            JavaImports.linkedHashMap,
            JavaImports.list,
            JavaImports.map,
            JavaImports.supplier,
            JavaImports.uuid,
            'java.util.Locale',
            'java.util.StringJoiner',
            'java.util.zip.GZIPInputStream',
            'java.util.zip.InflaterInputStream',
            ...flavor.singleImports,
          ],
          body: restAdapterUsesWebClient ? javaRestWebClientAdapter() : javaRestJdkAdapter(flavor),
        ),
      if (restAdapterUsesWebClient)
        'GLDataBufferInputStream.java': GLClassModel(
          imports: [
            'java.io.IOException',
            'java.io.InputStream',
            'java.io.InterruptedIOException',
            'java.util.concurrent.BlockingQueue',
            'java.util.concurrent.LinkedBlockingQueue',
            'org.reactivestreams.Subscription',
            'org.springframework.core.io.buffer.DataBuffer',
            'org.springframework.core.io.buffer.DataBufferUtils',
            'reactor.core.publisher.BaseSubscriber',
            'reactor.core.publisher.Flux',
          ],
          body: javaGLDataBufferInputStream(),
        ),
      if (!_hasGraphQL)
        'GraphLinkNoGraphQL.java': GLClassModel(
          imports: flavor.singleImports,
          importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
          body: javaNoGraphQLAdapter(flavor, operationName: _grammar.operationNameAsParameter),
        ),
    };
  }

  /// Wraps [inner] in the flavor's deferred-single type, or returns it bare
  /// for the blocking flavor. Routes through the same [GLType.wrapper] +
  /// `serializeType` mechanism used for schema types (mirrors
  /// [GLVoidType]'s pattern of building a synthetic, non-schema [GLType]).
  String wrapSingle(String inner) => serializer
      .serializeType(JavaCodeGenUtils.wrapReactive(inner.toToken(), flavor));


  String _adapterDeclaration(bool withStore) {
    return [
      if (_hasGraphQL) 'GraphLinkClientAdapter adapter',
      if (_hasGraphQL && _grammar.persistedQueriesUseGet) 'GraphLinkClientAdapter getAdapter',
      if (_grammar.hasUploadMutations)
        'GraphLinkMultipartAdapter multipartAdapter',
      if (hasRest) 'GLRestAdapter restAdapter',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
      if (withStore) 'GraphLinkCacheStore store',
    ].join(", ");
  }

  @override
  GLClassModel? getQueriesClass() =>
      _buildClassForType(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() =>
      _buildClassForType(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() =>
      _buildClassForType(GLQueryType.subscription);

  /// Kept for backwards compatibility — prefer [getQueriesClass],
  /// [getMutationsClass], or [getSubscriptionsClass] via the base-class API.
  GLClassModel? generateQueriesClassByType(
          GLQueryType type) =>
      _buildClassForType(type);

  GLClassModel? _buildClassForType(GLQueryType type) {
    final importContainer = GLImportContainer();
    _activeContainer = importContainer;

    importContainer.importDepencies
        .add(_grammar.getTypeByName("GraphLinkClientAdapter")!);
    importContainer.importDepencies.addAll([
      'GraphLinkJsonEncoder',
      'GraphLinkJsonDecoder'
    ].map((e) => _grammar.getTypeByName(e)!));

    final restOperations = _restOperations(type);
    final methods = [
      ...buildOperationMethods(type),
      ...restOperations.map((op) => _restSer.operationToMethod(op, importContainer)),
    ];
    if (methods.isEmpty) return null;

    final classBody = codeGenUtils.createClass(
        staticClass: false,
        className: "${classNameFromType(type)} extends ${restOperations.isEmpty ? 'GraphLinkResolverBase' : 'GraphLinkRestResolver'}",
        statements: [
          ...declareAdapter(type),
          codeGenUtils.createMethod(
              returnType: 'public',
              methodName: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              statements: [
                '${codeGenUtils.callExpression('super', [
                  'adapter',
                  if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet) 'getAdapter',
                  if (restOperations.isNotEmpty) 'restAdapter',
                  'fragmentMap',
                  'store',
                  'encoder',
                  'decoder',
                ])};',
                if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
                  'this.$svMultipartAdapter = multipartAdapter;',
                if (type == GLQueryType.subscription)
                  '$svHandler = new GraphLinkSubscriptionHandler(wsAdapter, decoder, encoder);',
              ]),
          ...methods,
        ]);

    return GLClassModel(
      importDepencies: {
        ..._getQueryImports(type),
        ..._restTokens(type),
        ...importContainer.importDepencies
      }.toList(),
      imports: [
        ...importContainer.imports,
        ...flavor.imports,
        ..._grammar.scalarImportsOfOperationType(type),
        if (restOperations.isNotEmpty) ...[...flavor.optionalTypeImports, if (flavor.isReactive) JavaImports.optional],
      ],
      body: classBody,
    );
  }

  Set<GLToken> _getQueryImports(GLQueryType type) =>
      schemaTokensFor(type).toSet();

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      'GraphLinkClientAdapter adapter',
      if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet)
        'GraphLinkClientAdapter getAdapter',
      if (type == GLQueryType.subscription)
        'GraphLinkWebSocketAdapter wsAdapter',
      if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
        'GraphLinkMultipartAdapter multipartAdapter',
      if (_restOperations(type).isNotEmpty) 'GLRestAdapter restAdapter',
      'Map<String, String> fragmentMap',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
      'GraphLinkCacheStore store',
    ];
  }

  List<String> declareAdapter(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
      case GLQueryType.mutation:
        return [
          if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
            'private final GraphLinkMultipartAdapter $svMultipartAdapter;',
        ];
      case GLQueryType.subscription:
        return [
          "private final GraphLinkSubscriptionHandler $svHandler;"
        ];
    }
  }


  GLClassModel? generateQueriesClassFile(
          GLQueryType type) =>
      generateQueriesClassByType(type);


  String get exceptionFileName => '$clientExceptionName.java';

  String get fileExtension => '.java';

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    // The client file only needs the shared GraphLink types and the Java
    // $svAdapter/codec interfaces. Query return types and input argument types
    // are imported in their respective class files (GLQueries, GLMutations,
    // GLSubscriptions) and don't need to appear in GraphLinkClient.java.
    return [
      'GraphLinkJsonEncoder',
      'GraphLinkJsonDecoder',
      'GraphLinkClientAdapter',
    ].map(g.getTokenByKey).whereType<GLToken>().toSet();
  }

  void requireGet() {
    if (!_grammar.persistedQueriesUseGet) {
      throw StateError('The GET runtime is only generated when persistedQueriesUseGet is enabled.');
    }
  }
}
