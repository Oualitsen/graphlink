import 'package:graphlink/src/cache_store_java.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_rest_operation_serializer.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';




class JavaClientSerializer extends GLClientSerializer {
  final GLParser _grammar;
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
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder'], headers: false))};'
                ]
              : [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null'], headers: false))};'
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
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder'], headers: true))};'
                ]
              : [
                  '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null'], headers: true))};'
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
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"))'], headers: false))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"))'], headers: false))};'
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
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider)'], headers: true))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider)'], headers: true))};'
              ],
      ),
      // Option B — explicit wsUrl
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String url', ..._restCtorParams, 'String wsUrl', ...encoderDecoderArgs],
        statements: _grammar.hasUploadMutations
            ? [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(wsUrl)'], headers: false))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url)', ..._getAdapterExpr('url'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(wsUrl)'], headers: false))};'
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
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)'], headers: true))};'
              ]
            : [
                '${codeGenUtils.callExpression('this', _withRest(['new DefaultGraphLinkClientAdapter(url, headersProvider)', ..._getAdapterExpr('url, headersProvider'), 'encoder', 'decoder', 'null', 'new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)'], headers: true))};'
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
  String _wrapSingle(String inner) => serializer
      .serializeType(JavaCodeGenUtils.wrapReactive(inner.toToken(), flavor));

  /// Splices [statements] under a reactive-lambda opener (e.g.
  /// [JavaReactiveFlavor.mapOpen]/`onErrorResumeOpen`, which return only
  /// `"src.map(param -> {"` — an opening fragment `codeGenUtils.block` can't
  /// express since it always emits a bare `{`) and a matching `});` closer.
  String _reactiveOpenBlock({required String header, required List<String> statements}) {
    final body = statements.join('\n').ident();
    return '$header\n$body\n});';
  }

  String _glHashMethod() {
    return codeGenUtils.createMethod(
      returnType: 'public String',
      methodName: 'glHash',
      arguments: ['String query'],
      statements: [
        'String cached = $svHashes.get(query);',
        codeGenUtils.ifStatement(
          condition: 'cached != null',
          ifBlockStatements: ['return cached;'],
        ),
        'String hash = GraphLinkSha256.hex(query);',
        '$svHashes.put(query, hash);',
        'return hash;',
      ],
    );
  }

  String get _opNameParam => _grammar.operationNameAsParameter ? ', String operationName' : '';
  String get _opNameArg => _grammar.operationNameAsParameter ? ', operationName' : '';

  String _glSendMethod() {
    return codeGenUtils.createMethod(
      returnType: 'private ${_wrapSingle('String')}',
      methodName: 'glSend',
      arguments: ['Object body${_opNameParam}'],
      statements: ['return $svAdapter.execute($svEncoder.encode(body)$_opNameArg);'],
    );
  }

  String _glSendHashOnlyMethod() {
    final send = 'glSend(body$_opNameArg)';
    final getCall = '$svGetAdapter.execute($svEncoder.encode(body)$_opNameArg)';
    final guard = codeGenUtils.ifStatement(
      condition: '$svGetAdapter == null || $svGetUnsupported || payload.getQuery().startsWith("mutation")',
      ifBlockStatements: ['return $send;'],
    );
    final fallback = flavor.isReactive
        ? _reactiveOpenBlock(
            header: 'return ${flavor.onErrorResumeOpen(getCall, 'e')}',
            statements: [
              'Throwable cause = e instanceof CompletionException && e.getCause() != null ? e.getCause() : e;',
              codeGenUtils.ifStatement(
                condition: '!(cause instanceof GraphLinkGetNotSupported)',
                ifBlockStatements: ['return ${flavor.error('e')};'],
              ),
              '$svGetUnsupported = true;',
              'return $send;',
            ],
          )
        : codeGenUtils.tryCatchFinally(
            tryStatements: ['return $getCall;'],
            catchVariable: 'e',
            catchStatements: [
              codeGenUtils.ifStatement(
                condition: '!(e instanceof GraphLinkGetNotSupported)',
                ifBlockStatements: ['throw e;'],
              ),
              '$svGetUnsupported = true;',
              'return $send;',
            ],
          );
    return codeGenUtils.createMethod(
      returnType: 'private ${_wrapSingle('String')}',
      methodName: 'glSendHashOnly',
      arguments: ['GraphLinkPayload payload', 'Map<String, Object> body${_opNameParam}'],
      statements: [guard, fallback],
    );
  }

  List<String> _persistedCallAdapterStatements() {
    final hashOnlyCall = _grammar.persistedQueriesUseGet
        ? 'glSendHashOnly(payload, hashOnly$_opNameArg)'
        : 'glSend(hashOnly$_opNameArg)';
    final retry = <String>[
      'String failure = GraphLinkPersistedQueries.failure(response, $svDecoder);',
      codeGenUtils.ifStatement(
        condition: 'failure == null',
        ifBlockStatements: ['return ${flavor.wrapValue('response')};'],
      ),
      codeGenUtils.ifStatement(
        condition: 'GraphLinkPersistedQueries.NOT_SUPPORTED.equals(failure)',
        ifBlockStatements: [
          '$svPersistedUnsupported = true;',
          'return glSend(payload$_opNameArg);',
        ],
      ),
      'Map<String, Object> body = new HashMap<>();',
      'body.put("query", payload.getQuery());',
      'body.put("operationName", payload.getOperationName());',
      'body.put("variables", payload.getVariables());',
      'body.put("extensions", extensions);',
      'return glSend(body$_opNameArg);',
    ];
    return [
      if (_grammar.operationNameAsParameter) 'String operationName = payload.getOperationName();',
      codeGenUtils.ifStatement(
        condition:
            '$svPersistedUnsupported || payload.getQuery().length() <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH',
        ifBlockStatements: ['return glSend(payload$_opNameArg);'],
      ),
      'Map<String, Object> extensions = GraphLinkPersistedQueries.extensions(glHash(payload.getQuery()));',
      'Map<String, Object> hashOnly = new HashMap<>();',
      'hashOnly.put("operationName", payload.getOperationName());',
      'hashOnly.put("variables", payload.getVariables());',
      'hashOnly.put("extensions", extensions);',
      if (flavor.isReactive)
        _reactiveOpenBlock(
          header: 'return ${flavor.flatMapOpen(hashOnlyCall, 'response')}',
          statements: retry,
        )
      else ...[
        'String response = $hashOnlyCall;',
        ...retry,
      ],
    ];
  }

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

  String _buildPayloadMethod() {
    return codeGenUtils.createMethod(
      returnType: 'private GraphLinkPayload',
      methodName: 'buildPayload',
      arguments: [
        'List<GraphLinkPartialQuery> partQueries',
        'String operationName',
        'String directives'
      ],
      statements: [
        'Map<String, Object> variables = new HashMap<>();',
        codeGenUtils.forEachLoop(
            variable: 'partQuery',
            iterable: 'partQueries',
            statements: [
              'variables.putAll(partQuery.variables);',
            ]),
        'StringBuilder queryBuilder = new StringBuilder("query " + operationName);',
        'Set<String> args = new HashSet<>();',
        codeGenUtils.forEachLoop(
            variable: 'partQuery',
            iterable: 'partQueries',
            statements: [
              'args.addAll(partQuery.argumentDeclarations);',
            ]),
        codeGenUtils.ifStatement(
            condition: '!args.isEmpty()',
            ifBlockStatements: [
              'queryBuilder.append("(");',
              'queryBuilder.append(String.join(", ", args));',
              'queryBuilder.append(")");',
            ]),
        codeGenUtils.ifStatement(
            condition: '!directives.isEmpty()',
            ifBlockStatements: [
              'queryBuilder.append(directives);',
            ]),
        'queryBuilder.append("{");',
        codeGenUtils.forEachLoop(
            variable: 'partQuery',
            iterable: 'partQueries',
            statements: [
              'queryBuilder.append(partQuery.query);',
              'queryBuilder.append(" ");',
            ]),
        'queryBuilder.append("}");',
        'Set<String> fragmentNames = new HashSet<>();',
        codeGenUtils.forEachLoop(
            variable: 'partQuery',
            iterable: 'partQueries',
            statements: [
              'fragmentNames.addAll(partQuery.fragmentNames);',
            ]),
        'StringBuilder fragmentsBuilder = new StringBuilder();',
        codeGenUtils.forEachLoop(
            variable: 'fragName',
            iterable: 'fragmentNames',
            statements: [
              'fragmentsBuilder.append(${svFragmentMap}.get(fragName));',
            ]),
        'queryBuilder.append(fragmentsBuilder);',
        'return GraphLinkPayload.builder().query(queryBuilder.toString()).operationName(operationName).variables(variables).build();',
      ],
    );
  }

  GLClassModel generateGraphLinkResolverBaseFile(String importPrefix) {
    final allTags = _grammar.getAllCacheTags();

    final classBody = codeGenUtils.createClass(
      className: 'GraphLinkResolverBase',
      statements: [
        'protected final Map<String, String> ${svFragmentMap};',
        'protected final GraphLinkCacheStore $svStore;',
        'protected final GraphLinkJsonEncoder $svEncoder;',
        'protected final GraphLinkJsonDecoder $svDecoder;',
        'private final Map<String, ReentrantLock> $svTagLocks = new HashMap<>();',
        'private final GraphLinkClientAdapter $svAdapter;',
        if (_grammar.persistedQueries) ...[
          'private final Map<String, String> $svHashes = new ConcurrentHashMap<>();',
          'private volatile boolean $svPersistedUnsupported = false;',
        ],
        if (_grammar.persistedQueriesUseGet) ...[
          'private final GraphLinkClientAdapter $svGetAdapter;',
          'private volatile boolean $svGetUnsupported = false;',
          codeGenUtils.createMethod(
            methodName: 'GraphLinkResolverBase',
            arguments: [
              'GraphLinkClientAdapter adapter',
              'Map<String, String> fragmentMap',
              'GraphLinkCacheStore store',
              'GraphLinkJsonEncoder encoder',
              'GraphLinkJsonDecoder decoder',
            ],
            statements: ['this(adapter, null, fragmentMap, store, encoder, decoder);'],
          ),
        ],
        codeGenUtils.createMethod(
          methodName: 'GraphLinkResolverBase',
          arguments: [
            'GraphLinkClientAdapter adapter',
            if (_grammar.persistedQueriesUseGet) 'GraphLinkClientAdapter getAdapter',
            'Map<String, String> fragmentMap',
            'GraphLinkCacheStore store',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: [
            'this.$svAdapter = adapter;',
            if (_grammar.persistedQueriesUseGet) 'this.$svGetAdapter = getAdapter;',
            'this.${svFragmentMap} = fragmentMap;',
            'this.$svStore = store;',
            'this.$svEncoder = encoder;',
            'this.$svDecoder = decoder;',
            'String[] tags = {${allTags.map((t) => '"$t"').join(', ')}};',
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              '$svTagLocks.put(tag, new ReentrantLock());',
            ]),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> T',
          methodName: 'parseToObjectAndCache',
          arguments: [
            'String data',
            'Map<String, Object> cachedResponse',
            'Function<Map<String, Object>, T> parser',
            'List<GraphLinkPartialQuery> remainingQueries',
            'boolean captureErrors'
          ],
          statements: [
            'Map<String, Object> result = $svDecoder.decode(data);',
            'Map<String, Object> $svRawData = (Map<String, Object>) result.get("data");',
            'Map<String, Object> dataMap = $svRawData != null ? $svRawData : new HashMap<>();',
            codeGenUtils.forEachLoop(
                variable: 'q',
                iterable: 'remainingQueries',
                statements: [
                  codeGenUtils.ifStatement(
                      condition:
                          'q.ttl > 0 && dataMap.get(q.elementKey) != null',
                      ifBlockStatements: [
                        'Map<String, Object> $svCacheWrap = new HashMap<>();',
                        '$svCacheWrap.put("__gl_v__", dataMap.get(q.elementKey));',
                        'GraphLinkCacheEntry entry = new GraphLinkCacheEntry($svEncoder.encode($svCacheWrap), System.currentTimeMillis() + q.ttl * 1000L);',
                        '$svStore.set(q.cacheKey, $svEncoder.encode(entry.toJson()));',
                        codeGenUtils.ifStatement(
                            condition: '!q.tags.isEmpty()',
                            ifBlockStatements: [
                              'addKeyToTags(q.cacheKey, q.tags);',
                            ]),
                      ]),
                ]),
            'dataMap.putAll(cachedResponse);',
            'Map<String, Object> fullResponse = new HashMap<>();',
            'fullResponse.put("data", $svRawData != null ? dataMap : null);',
            codeGenUtils.ifStatement(
                condition: 'result.containsKey("errors")',
                ifBlockStatements: [
                  'fullResponse.put("errors", result.get("errors"));',
                ]),
            'T parsed = parser.apply(fullResponse);',
            codeGenUtils.ifStatement(
                condition: 'captureErrors',
                ifBlockStatements: ['return parsed;']),
            codeGenUtils.ifStatement(
                condition: 'result.containsKey("errors") && !((List<?>) result.get("errors")).isEmpty()',
                ifBlockStatements: [
                  'throw ${clientExceptionName}.of(parsed.getErrors());',
                ]),
            'return parsed;',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> ${_wrapSingle('T')}',
          methodName: 'executeFull',
          arguments: [
            'String query',
            'Set<String> fragmentNames',
            'String operationName',
            'Map<String, Object> variables',
            'Function<Map<String, Object>, T> fromJson',
          ],
          statements: [
            'String $svFullQuery = assembleQuery(query, fragmentNames);',
            'GraphLinkPayload $svPayload = GraphLinkPayload.builder().query($svFullQuery).operationName(operationName).variables(variables).build();',
            if (!flavor.isReactive) ...[
              'String $svResponseText = glCallAdapter($svPayload);',
              'return fromJson.apply($svDecoder.decode($svResponseText));',
            ] else
              'return ${flavor.mapTo('glCallAdapter($svPayload)', '$svResponseText -> fromJson.apply($svDecoder.decode($svResponseText))')};',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> ${_wrapSingle('T')}',
          methodName: 'executeData',
          arguments: [
            'String query',
            'Set<String> fragmentNames',
            'String operationName',
            'Map<String, Object> variables',
            'Function<Map<String, Object>, T> fromJson',
          ],
          statements: !flavor.isReactive
              ? [
                  'T $svDecodedResponse = executeFull(query, fragmentNames, operationName, variables, fromJson);',
                  codeGenUtils.ifStatement(
                      condition:
                          '$svDecodedResponse.getErrors() != null && !$svDecodedResponse.getErrors().isEmpty()',
                      ifBlockStatements: [
                        'throw ${clientExceptionName}.of($svDecodedResponse.getErrors());',
                      ]),
                  'return $svDecodedResponse;',
                ]
              : [
                  _reactiveOpenBlock(
                    header: 'return ${flavor.mapOpen('executeFull(query, fragmentNames, operationName, variables, fromJson)', svDecodedResponse)}',
                    statements: [
                      codeGenUtils.ifStatement(
                        condition: '$svDecodedResponse.getErrors() != null && !$svDecodedResponse.getErrors().isEmpty()',
                        ifBlockStatements: ['throw ${clientExceptionName}.of($svDecodedResponse.getErrors());'],
                      ),
                      'return $svDecodedResponse;',
                    ],
                  ),
                ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> ${_wrapSingle('T')}',
          methodName: 'executeCached',
          arguments: [
            'List<GraphLinkPartialQuery> $svPartialQueries',
            'String operationName',
            'String directives',
            'Function<Map<String, Object>, T> fromJson',
            'boolean captureErrors',
          ],
          statements: [
            'Map<String, Object> $svResponseMap = new HashMap<>();',
            'Map<String, Object> $svStaleData = new HashMap<>();',
            codeGenUtils.forEachLoop(
                variable: 'partQuery',
                iterable: '$svPartialQueries',
                statements: [
                  codeGenUtils.ifStatement(
                      condition: 'partQuery.ttl > 0',
                      ifBlockStatements: [
                        codeGenUtils.tryCatchFinally(
                          tryStatements: [
                            'GraphLinkCacheEntry entry = getFromCache(partQuery.cacheKey, partQuery.tags, partQuery.staleIfOffline);',
                            codeGenUtils.ifStatement(
                                condition: 'entry != null',
                                ifBlockStatements: [
                                  codeGenUtils.ifStatement(
                                    condition: 'entry.stale',
                                    ifBlockStatements: [
                                      '$svStaleData.put(partQuery.elementKey, $svDecoder.decode(entry.data).get("__gl_v__"));'
                                    ],
                                    elseBlockStatements: [
                                      '$svResponseMap.put(partQuery.elementKey, $svDecoder.decode(entry.data).get("__gl_v__"));'
                                    ],
                                  ),
                                ]),
                          ],
                          catchStatements: [],
                          catchVariable: 'ignored',
                        ),
                      ]),
                ]),
            'List<GraphLinkPartialQuery> $svRemaining = new ArrayList<>();',
            codeGenUtils.forEachLoop(
                variable: 'partQuery',
                iterable: '$svPartialQueries',
                statements: [
                  codeGenUtils.ifStatement(
                      condition:
                          '!$svResponseMap.containsKey(partQuery.elementKey)',
                      ifBlockStatements: [
                        '$svRemaining.add(partQuery);',
                      ]),
                ]),
            codeGenUtils.ifStatement(
                condition: '$svRemaining.isEmpty()',
                ifBlockStatements: [
                  'Map<String, Object> $svWrappedResponse = new HashMap<>();',
                  '$svWrappedResponse.put("data", $svResponseMap);',
                  if (!flavor.isReactive)
                    'return fromJson.apply($svWrappedResponse);'
                  else
                    'return ${flavor.wrapValue('fromJson.apply($svWrappedResponse)')};',
                ]),
            'GraphLinkPayload $svPayload = buildPayload($svRemaining, operationName, directives);',
            // The network call + cache-write composes asynchronously for the
            // reactive flavors; the stale-fallback try/catch becomes
            // onErrorResume. Cache reads above stay imperative (sync store).
            if (!flavor.isReactive)
              codeGenUtils.tryCatchFinally(
                tryStatements: [
                  'String $svResponseText = glCallAdapter($svPayload);',
                  'return ${codeGenUtils.callExpression('parseToObjectAndCache', ['$svResponseText', '$svResponseMap', 'fromJson', '$svRemaining', 'captureErrors'])};',
                ],
                catchStatements: [
                  '$svResponseMap.putAll($svStaleData);',
                  'long remainingCount = $svPartialQueries.stream().filter(e -> !$svResponseMap.containsKey(e.elementKey)).count();',
                  codeGenUtils.ifStatement(
                      condition: 'remainingCount > 0',
                      ifBlockStatements: [
                        'throw new RuntimeException(exception);',
                      ]),
                  'Map<String, Object> $svWrappedResponse = new HashMap<>();',
                  '$svWrappedResponse.put("data", $svResponseMap);',
                  'return fromJson.apply($svWrappedResponse);',
                ],
                catchVariable: 'exception',
              )
            else
              _reactiveOpenBlock(
                header: 'return ${flavor.onErrorResumeOpen(flavor.mapTo('glCallAdapter($svPayload)', '$svResponseText -> parseToObjectAndCache($svResponseText, $svResponseMap, fromJson, $svRemaining, captureErrors)'), 'exception')}',
                statements: [
                  '$svResponseMap.putAll($svStaleData);',
                  'long remainingCount = $svPartialQueries.stream().filter(e -> !$svResponseMap.containsKey(e.elementKey)).count();',
                  codeGenUtils.ifStatement(
                    condition: 'remainingCount > 0',
                    ifBlockStatements: ['return ${flavor.error('new RuntimeException(exception)')};'],
                  ),
                  'Map<String, Object> $svWrappedResponse = new HashMap<>();',
                  '$svWrappedResponse.put("data", $svResponseMap);',
                  'return ${flavor.wrapValue('fromJson.apply($svWrappedResponse)')};',
                ],
              ),
          ],
        ),
        _buildPayloadMethod(),
        codeGenUtils.createMethod(
          returnType: 'private String',
          methodName: 'tagKey',
          arguments: ['String tag'],
          statements: ['return "__tag__" + tag;'],
        ),
        if (_grammar.persistedQueries) ...[
          _glHashMethod(),
          _glSendMethod(),
          if (_grammar.persistedQueriesUseGet) _glSendHashOnlyMethod(),
        ],
        codeGenUtils.createMethod(methodName: 'glCallAdapter', returnType: 'protected ${_wrapSingle('String')}', arguments: [
          'GraphLinkPayload payload',
        ], statements: _grammar.persistedQueries
            ? _persistedCallAdapterStatements()
            : [
                if (_grammar.operationNameAsParameter)
                  ...[
                    'String operationName = payload.getOperationName();',
                    'return $svAdapter.execute($svEncoder.encode(payload), operationName);']
                else
                  'return $svAdapter.execute($svEncoder.encode(payload));'
              ]),
        codeGenUtils.createMethod(
          returnType: 'GraphLinkCacheEntry',
          methodName: 'getFromCache',
          arguments: [
            'String key',
            'List<String> tags',
            'boolean staleIfOffline'
          ],
          statements: [
            'String result = $svStore.get(key);',
            codeGenUtils
                .ifStatement(condition: 'result != null', ifBlockStatements: [
              'Map<String, Object> entryMap = $svDecoder.decode(result);',
              'GraphLinkCacheEntry entry = GraphLinkCacheEntry.fromJson(entryMap);',
              codeGenUtils.ifStatement(
                  condition: 'entry.isExpired()',
                  ifBlockStatements: [
                    codeGenUtils.ifStatement(
                        condition: 'staleIfOffline',
                        ifBlockStatements: ['return entry.asStale();']),
                    '$svStore.invalidate(key);',
                    codeGenUtils.ifStatement(
                        condition: '!tags.isEmpty()',
                        ifBlockStatements: ['removeKeyFromTags(key, tags);']),
                    'return null;',
                  ],
                  elseBlockStatements: [
                    'return entry;',
                  ]),
            ]),
            'return null;',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'void',
          methodName: 'invalidateByTags',
          arguments: ['List<String> tags'],
          statements: [
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'String tKey = tagKey(tag);',
              'ReentrantLock lock = $svTagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $svStore.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson($svDecoder.decode(data));',
                  codeGenUtils.forEachLoop(
                      variable: 'k',
                      iterable: 'entry.keys',
                      statements: ['$svStore.invalidate(k);']),
                  '$svStore.invalidate(tKey);',
                ]),
              ], finallyStatements: [
                'lock.unlock();',
              ]),
            ]),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'void',
          methodName: 'addKeyToTags',
          arguments: ['String key', 'List<String> tags'],
          statements: [
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'String tKey = tagKey(tag);',
              'ReentrantLock lock = $svTagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $svStore.get(tKey);',
                'GraphLinkTagEntry entry = data != null ? GraphLinkTagEntry.fromJson($svDecoder.decode(data)) : new GraphLinkTagEntry(new HashSet<>());',
                'entry.add(key);',
                '$svStore.set(tKey, $svEncoder.encode(entry.toJson()));',
              ], finallyStatements: [
                'lock.unlock();',
              ]),
            ]),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'void',
          methodName: 'removeKeyFromTags',
          arguments: ['String key', 'List<String> tags'],
          statements: [
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'String tKey = tagKey(tag);',
              'ReentrantLock lock = $svTagLocks.computeIfAbsent(tag, k -> new ReentrantLock());',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $svStore.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson($svDecoder.decode(data));',
                  'entry.remove(key);',
                  codeGenUtils.ifStatement(
                    condition: 'entry.keys.isEmpty()',
                    ifBlockStatements: ['$svStore.invalidate(tKey);'],
                    elseBlockStatements: [
                      '$svStore.set(tKey, $svEncoder.encode(entry.toJson()));'
                    ],
                  ),
                ]),
              ], finallyStatements: [
                'lock.unlock();',
              ]),
            ]),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'public String',
          methodName: 'assembleQuery',
          arguments: [
            'String query',
            'Set<String> fragmentNames',
          ],
          statements: [
            'StringBuilder buffer = new StringBuilder(query);',
            codeGenUtils.forEachLoop(
                variable: 'name',
                iterable: 'fragmentNames',
                statements: [
                  'String frag = ${svFragmentMap}.get(name);',
                  codeGenUtils.ifStatement(
                      condition: 'frag != null',
                      ifBlockStatements: [
                        'buffer.append("\\n");',
                        'buffer.append(frag);',
                      ]),
                ]),
            'return buffer.toString();',
          ],
        ),
      ],
    );

    return GLClassModel(
      imports: [
        JavaImports.map,
        JavaImports.list,
        JavaImports.arrayList,
        JavaImports.set,
        JavaImports.hashMap,
        JavaImports.hashSet,
        JavaImports.reentrantLock,
        JavaImports.function,
        if (_grammar.persistedQueries) JavaImports.concurrentHashMap,
        if (_grammar.persistedQueriesUseGet && flavor.isReactive) 'java.util.concurrent.CompletionException',
        ...flavor.imports,
      ],
      importDepencies: [
        _grammar.getTokenByKey("GraphLinkJsonEncoder")!,
        _grammar.getTokenByKey("GraphLinkJsonDecoder")!,
        _grammar.getTokenByKey("GraphLinkPayload")!,
        _grammar.getTokenByKey("GraphLinkClientAdapter")!,
        _grammar.getTokenByKey("GraphLinkFullResponse")!,
      ],
      body: classBody,
    );
  }

  GLClassModel? generateQueriesClassFile(
          GLQueryType type) =>
      generateQueriesClassByType(type);

  GLClassModel generateGraphLinkCacheEntryFile() => const GLClassModel(
        imports: [JavaImports.map, JavaImports.hashMap],
        body: cacheEntry,
      );

  GLClassModel generateGraphLinkTagEntryFile() => const GLClassModel(
        imports: [
          JavaImports.map,
          JavaImports.hashMap,
          JavaImports.set,
          JavaImports.hashSet,
          JavaImports.list,
          JavaImports.arrayList,
        ],
        body: tagEntry,
      );

  GLClassModel generateGraphLinkPartialQueryFile(String importPrefix) =>
      GLClassModel(
        importDepencies: [_grammar.getTokenByKey('GraphLinkJsonEncoder')!],
        imports: [
          JavaImports.map,
          JavaImports.list,
          JavaImports.set,
          JavaImports.treeMap,
        ],
        body: partialQuery,
      );

  GLClassModel generateGraphLinkCacheStoreFile() =>
      const GLClassModel(body: graphLinkCacheStore);

  GLClassModel generateInMemoryGraphLinkCacheStoreFile() => const GLClassModel(
        imports: [JavaImports.concurrentHashMap],
        body: inMemoryGraphLinkCacheStore,
      );

  GLClassModel generateSubscriptionListenerFile() {
    return const GLClassModel(body: gqSubscriptionListener);
  }

  GLClassModel generateGraphqlWsMessageTypesFile() {
    return const GLClassModel(body: graphqlWsMessageTypesClass);
  }

  GLClassModel generateGraphLinkSubscriptionHandlerFile(String importPrefix) {
    return GLClassModel(
      imports: [
        JavaImports.map,
        JavaImports.hashMap,
        JavaImports.list,
        JavaImports.arrayList,
        JavaImports.collections,
        JavaImports.uuid,
      ],
      importDepencies: [
        ...[
          'GraphLinkJsonDecoder',
          'GraphLinkJsonEncoder',
          'GraphLinkAckStatus',
          'GraphLinkPayload',
          'GraphLinkSubscriptionMessage',
          'GraphLinkSubscriptionPayload',
          'GraphLinkSubscriptionErrorMessageBase',
          'GraphLinkSubscriptionErrorMessage'
        ].map((e) => _grammar.getTokenByKey(e)!)
      ],
      body: subscriptionHandlerClass,
    );
  }

  String get exceptionFileName => '$clientExceptionName.java';

  GLClassModel generateGraphLinkExceptionFile(String importPrefix) {
    final errorToken = _grammar.getTokenByKey('GraphLinkError');

    final classBody = codeGenUtils.createClass(
      className: '$clientExceptionName extends RuntimeException',
      statements: [
        'private final List<GraphLinkError> errors;',
        codeGenUtils.createMethod(
            returnType: 'public',
            methodName: clientExceptionName,
            arguments: [
              'List<GraphLinkError> errors',
            ],
            statements: [
              'this.errors = errors;'
            ]),
        codeGenUtils.createMethod(
            returnType: 'private',
            methodName: clientExceptionName,
            arguments: ['Exception ex'],
            statements: ['super(ex);', 'errors = Collections.emptyList();']),
        codeGenUtils.createMethod(
            returnType: 'public List<GraphLinkError>',
            methodName: 'getErrors',
            arguments: [],
            statements: ['return errors;']),
        codeGenUtils.createMethod(
            returnType: 'static $clientExceptionName',
            methodName: 'of',
            arguments: [
              'List<?> errors'
            ],
            statements: [
              // Callers pass either raw error maps (a caught Throwable) or an
              // already-decoded List<GraphLinkError> (a response's own
              // `getErrors()`) — only re-parse elements that aren't already typed.
              'return new $clientExceptionName(errors.stream().map(e -> e instanceof GraphLinkError ? (GraphLinkError) e : GraphLinkError.fromJson((Map<String, Object>)e)).collect(Collectors.toList()));'
            ]),
      ],
    );

    return GLClassModel(
      importDepencies: [if (errorToken != null) errorToken],
      imports: [
        JavaImports.list,
        JavaImports.collections,
        JavaImports.collectors,
        JavaImports.map,
      ],
      body: classBody,
    );
  }

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

  GLClassModel generateUploadProgressCallbackFile() {
    return const GLClassModel(body: javaUploadProgressCallback);
  }

  GLClassModel generateMultipartAdapterFile(String importPrefix) {
    if (!flavor.isReactive) {
      return const GLClassModel(
        imports: [JavaImports.map],
        body: javaGraphLinkMultipartAdapter,
      );
    }
    // Reactive variant: executeMultipart returns the deferred-single carrying
    // the body (or failure), so no checked IOException.
    final ret = '${flavor.single}<String>';
    final body = codeGenUtils.createInterface(
      interfaceName: 'GraphLinkMultipartAdapter',
      statements: [
        '$ret executeMultipart(String operations, String mapJson, Map<String, GLUpload> files, UploadProgressCallback onProgress);',
        '',
        'default $ret executeMultipart(String operations, String mapJson, Map<String, GLUpload> files) ${codeGenUtils.block([
              'return executeMultipart(operations, mapJson, files, null);',
            ])}',
      ],
    );
    return GLClassModel(
      imports: [JavaImports.map, ...flavor.singleImports],
      body: body,
    );
  }



  GLClassModel generateSha256File() {
    if (!_grammar.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(
      imports: ['java.nio.charset.StandardCharsets', 'java.security.MessageDigest', 'java.security.NoSuchAlgorithmException'],
      body: javaSha256,
    );
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!_grammar.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      imports: [JavaImports.map, JavaImports.hashMap, JavaImports.list],
      importDepencies: [_grammar.getTokenByKey('GraphLinkJsonDecoder')!],
      body: javaPersistedQueries,
    );
  }

  GLClassModel generateGetNotSupportedFile() {
    _requireGet();
    return const GLClassModel(body: javaGetNotSupported);
  }

  GLClassModel generateGetRequestFile() {
    _requireGet();
    return GLClassModel(
      imports: [
        JavaImports.map,
        JavaImports.list,
        JavaImports.arrayList,
        'java.net.URLEncoder',
        'java.nio.charset.StandardCharsets',
      ],
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      ],
      body: javaGetRequest,
    );
  }

  void _requireGet() {
    if (!_grammar.persistedQueriesUseGet) {
      throw StateError('The GET runtime is only generated when persistedQueriesUseGet is enabled.');
    }
  }

  GLClassModel generateDefaultGetAdapterFile(String flavor) {
    _requireGet();
    final okhttp = flavor == 'okhttp';
    return GLClassModel(
      imports: [
        ...(okhttp
            ? ['okhttp3.OkHttpClient', 'okhttp3.Request', 'okhttp3.Response']
            : ['java.net.URI', 'java.net.http.HttpClient', 'java.net.http.HttpRequest', 'java.net.http.HttpResponse']),
        JavaImports.map,
        JavaImports.supplier,
      ],
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkClientAdapter')!,
        _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
      ],
      body: okhttp
          ? defaultGetAdapterOkHttp(_grammar.operationNameAsParameter)
          : defaultGetAdapterJava11(_grammar.operationNameAsParameter),
    );
  }

  GLClassModel generateWebSocketAdapterFile() =>
      const GLClassModel(body: javaWebSocketAdapter);

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

