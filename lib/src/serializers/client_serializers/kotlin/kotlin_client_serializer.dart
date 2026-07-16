import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/kotlin_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/kotlin_imports.dart';

class KotlinClientSerializer extends GLClientSerializer {
  final GLParser _grammar;
  final KotlinCodeGenUtils codeGenUtils = KotlinCodeGenUtils();
  final KotlinWsAdapter wsAdapter;

  late final KotlinClientContext _ctx;
  late final KotlinClientOperationSerializer _opSer;
  GLImportContainer? _activeContainer;

  KotlinClientSerializer(
    this._grammar,
    GLSerializer serializer, {
    this.wsAdapter = KotlinWsAdapter.okhttp,
  }) : super(serializer, GLGraphqlSerializer(_grammar, false)) {
    _ctx = KotlinClientContext(_grammar, codeGenUtils, gqlSerializer, serializer);
    _opSer = KotlinClientOperationSerializer(_ctx);
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

  // ── Main client class ───────────────────────────────────────────────────────

  @override
  GLClassModel generateClient({bool hasDefaultAdapters = true}) {
    final container = GLImportContainer();
    container.importDepencies.addAll([
      _grammar.getTokenByKey('GraphLinkClientAdapter')!,
      _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
    ]);

    final fields = <String>[
      'private val fragmentMap = mutableMapOf<String, String>()',
      if (_grammar.hasQueries)
        'val queries: ${_classNameFor(GLQueryType.query)}',
      if (_grammar.hasMutations)
        'val mutations: ${_classNameFor(GLQueryType.mutation)}',
      if (_grammar.hasSubscriptions)
        'val subscriptions: ${_classNameFor(GLQueryType.subscription)}',
    ];

    final initBody = <String>[
      if (_grammar.hasQueries)
        'queries = ${_classNameFor(GLQueryType.query)}(adapter, fragmentMap, encoder, decoder, store)',
      if (_grammar.hasMutations)
        'mutations = ${_classNameFor(GLQueryType.mutation)}(adapter, ${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}fragmentMap, encoder, decoder, store)',
      if (_grammar.hasSubscriptions)
        'subscriptions = ${_classNameFor(GLQueryType.subscription)}(adapter, wsAdapter, fragmentMap, encoder, decoder, store)',
      ..._grammar.usedFragments
          .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
          .map((f) =>
              'fragmentMap["${f.tokenInfo}"] = "${gqlSerializer.serializeFragmentDefinitionBase(f).escapeForStringLiteral()}"'),
    ];

    final primaryCtorArgs = [
      'private val adapter: GraphLinkClientAdapter',
      if (_grammar.hasSubscriptions) 'private val wsAdapter: GraphLinkWebSocketAdapter',
      if (_grammar.hasUploadMutations) 'private val multipartAdapter: GraphLinkMultipartAdapter',
      'private val encoder: GraphLinkJsonEncoder',
      'private val decoder: GraphLinkJsonDecoder',
      'private val store: GraphLinkCacheStore = InMemoryGraphLinkCacheStore()',
    ];

    final body = StringBuffer();
    body.writeln(codeGenUtils.openClass(
      name: kotlinClientName,
      params: primaryCtorArgs,
      body: [
        ...fields,
        '',
        'init ${codeGenUtils.block(initBody)}',
        if (hasDefaultAdapters) ..._convenienceFactories(),
      ],
    ));

    return GLClassModel(
      importDepencies: container.importDepencies,
      imports: container.imports,
      body: body.toString(),
    );
  }

  List<String> _convenienceFactories() {
    const codec = 'KotlinxSerializationGraphLinkJsonCodec()';
    final hasSubs    = _grammar.hasSubscriptions;
    final hasUploads = _grammar.hasUploadMutations;

    // Builds the positional args for the primary constructor:
    //   adapter [, wsAdapter] [, multipartAdapter] encoder decoder
    // When uploads are present, DefaultGraphLinkClientAdapter implements both
    // GraphLinkClientAdapter and GraphLinkMultipartAdapter, so we reuse one
    // instance via a local val.
    String callArgs(String adapterExpr, String wsExpr) {
      if (hasUploads) {
        return '{ val a = $adapterExpr; return $kotlinClientName(a${hasSubs ? ', $wsExpr' : ''}, a, encoder, decoder) }';
      }
      return '= $kotlinClientName($adapterExpr${hasSubs ? ', $wsExpr' : ''}, encoder, decoder)';
    }

    if (!hasSubs) {
      return [
        '',
        'companion object {',
        '    fun create(url: String, encoder: GraphLinkJsonEncoder, decoder: GraphLinkJsonDecoder): $kotlinClientName ${callArgs('DefaultGraphLinkClientAdapter(url)', '')}',
        '    fun create(url: String, headersProvider: () -> Map<String, String>, encoder: GraphLinkJsonEncoder, decoder: GraphLinkJsonDecoder): $kotlinClientName ${callArgs('DefaultGraphLinkClientAdapter(url, headersProvider)', '')}',
        '    fun create(url: String): $kotlinClientName = create(url, $codec, $codec)',
        '}',
      ];
    }

    return [
      '',
      'companion object {',
      '    fun create(url: String, wsUrl: String, encoder: GraphLinkJsonEncoder, decoder: GraphLinkJsonDecoder): $kotlinClientName ${callArgs('DefaultGraphLinkClientAdapter(url)', 'DefaultGraphLinkWebSocketAdapter(wsUrl)')}',
      '    fun create(url: String, wsUrl: String, headersProvider: () -> Map<String, String>, encoder: GraphLinkJsonEncoder, decoder: GraphLinkJsonDecoder): $kotlinClientName ${callArgs('DefaultGraphLinkClientAdapter(url, headersProvider)', 'DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)')}',
      '    fun create(url: String): $kotlinClientName { val ws = url.replaceFirst("http", "ws"); return create(url, ws, $codec, $codec) }',
      '}',
    ];
  }

  // ── Resolver base ───────────────────────────────────────────────────────────

  GLClassModel generateGraphLinkResolverBaseFile(String packageName) {
    final allTags = _grammar.getAllCacheTags();
    final withOpName = _grammar.operationNameAsParameter;

    final body = codeGenUtils.openClass(
      name: 'GraphLinkResolverBase',
      params: [
        'private val adapter: GraphLinkClientAdapter',
        'protected val fragmentMap: Map<String, String>',
        'protected val store: GraphLinkCacheStore',
        'protected val encoder: GraphLinkJsonEncoder',
        'protected val decoder: GraphLinkJsonDecoder',
      ],
      body: [
        'private val tagLocks = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.locks.ReentrantLock>()',
        '',
        'init ${codeGenUtils.block([
          'val tags = listOf<String>(${allTags.map((t) => '"$t"').join(', ')})',
          codeGenUtils.forEachLoop(
            variable: 'tag',
            iterable: 'tags',
            statements: ['tagLocks[tag] = java.util.concurrent.locks.ReentrantLock()'],
          ),
        ])}',
        '',
        _glCallAdapterMethod(withOpName),
        '',
        _parseToObjectAndCacheMethod(),
        '',
        _executeFullMethod(),
        '',
        _executeDataMethod(),
        '',
        _executeCachedMethod(),
        '',
        _buildPayloadMethod(),
        '',
        _getFromCacheMethod(),
        '',
        _invalidateByTagsMethod(),
        '',
        _addKeyToTagsMethod(),
        '',
        _removeKeyFromTagsMethod(),
        '',
        "private fun tagKey(tag: String): String = \"__tag__\$tag\"",
        '',
        _assembleQueryMethod(),
      ],
    );

    return GLClassModel(
      imports: [KotlinImports.objects],
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkClientAdapter')!,
        _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        _grammar.getTokenByKey('GraphLinkPayload')!,
        _grammar.getTokenByKey('GraphLinkFullResponse')!,
      ],
      body: body,
    );
  }

  String _glCallAdapterMethod(bool withOpName) {
    final statements = withOpName
        ? [
            'val operationName = payload.operationName',
            'return adapter.execute(encoder.encode(payload.toJson()), operationName)',
          ]
        : ['return adapter.execute(encoder.encode(payload.toJson()))'];
    return codeGenUtils.suspendFun(
      name: 'glCallAdapter',
      arguments: ['payload: GraphLinkPayload'],
      returnType: 'String',
      statements: statements,
    );
  }

  String _parseToObjectAndCacheMethod() {
    return '''suspend fun <T : GraphLinkFullResponse> parseToObjectAndCache(
    data: String,
    cachedResponse: MutableMap<String, Any?>,
    parser: (Map<String, Any?>) -> T,
    remainingQueries: List<GraphLinkPartialQuery>,
    captureErrors: Boolean,
): T {
    val result = decoder.decode(data)
    val rawData = result["data"] as? Map<String, Any?>
    val dataMap = rawData?.toMutableMap() ?: mutableMapOf()
    for (q in remainingQueries) {
        if (q.ttl > 0 && dataMap[q.elementKey] != null) {
            val cacheWrap = mapOf("__gl_v__" to dataMap[q.elementKey])
            val entry = GraphLinkCacheEntry(encoder.encode(cacheWrap), System.currentTimeMillis() + q.ttl * 1000L)
            store.set(q.cacheKey, encoder.encode(entry.toJson()))
            if (q.tags.isNotEmpty()) addKeyToTags(q.cacheKey, q.tags)
        }
    }
    dataMap.putAll(cachedResponse)
    val fullResponse = mutableMapOf<String, Any?>("data" to if (rawData != null) dataMap else null)
    if (result.containsKey("errors")) fullResponse["errors"] = result["errors"]
    val parsed = parser(fullResponse)
    if (captureErrors) return parsed
    val errors = result["errors"] as? List<*>
    if (errors != null && errors.isNotEmpty()) throw $kotlinClientException(parsed.errors ?: emptyList())
    return parsed
}''';
  }

  String _executeFullMethod() {
    return '''suspend fun <T : GraphLinkFullResponse> executeFull(
    query: String,
    fragmentNames: Set<String>,
    operationName: String,
    variables: Map<String, Any?>,
    fromJson: (Map<String, Any?>) -> T,
): T {
    val fullQuery = assembleQuery(query, fragmentNames)
    val payload = GraphLinkPayload(query = fullQuery, operationName = operationName, variables = variables)
    val responseText = glCallAdapter(payload)
    return fromJson(decoder.decode(responseText))
}''';
  }

  String _executeDataMethod() {
    return '''suspend fun <T : GraphLinkFullResponse> executeData(
    query: String,
    fragmentNames: Set<String>,
    operationName: String,
    variables: Map<String, Any?>,
    fromJson: (Map<String, Any?>) -> T,
): T {
    val decoded = executeFull(query, fragmentNames, operationName, variables, fromJson)
    val errors = decoded.errors
    if (errors != null && errors.isNotEmpty()) throw $kotlinClientException(errors)
    return decoded
}''';
  }

  String _executeCachedMethod() {
    return '''suspend fun <T : GraphLinkFullResponse> executeCached(
    partialQueries: List<GraphLinkPartialQuery>,
    operationName: String,
    directives: String,
    fromJson: (Map<String, Any?>) -> T,
    captureErrors: Boolean,
): T {
    val responseMap = mutableMapOf<String, Any?>()
    val staleData = mutableMapOf<String, Any?>()
    for (partQuery in partialQueries) {
        if (partQuery.ttl > 0) {
            try {
                val entry = getFromCache(partQuery.cacheKey, partQuery.tags, partQuery.staleIfOffline)
                if (entry != null) {
                    if (entry.stale) {
                        staleData[partQuery.elementKey] = decoder.decode(entry.data)["__gl_v__"]
                    } else {
                        responseMap[partQuery.elementKey] = decoder.decode(entry.data)["__gl_v__"]
                    }
                }
            } catch (ignored: Exception) {}
        }
    }
    val remaining = partialQueries.filter { !responseMap.containsKey(it.elementKey) }.toMutableList()
    if (remaining.isEmpty()) {
        val wrappedResponse = mapOf("data" to responseMap)
        return fromJson(wrappedResponse)
    }
    val payload = buildPayload(remaining, operationName, directives)
    try {
        val responseText = glCallAdapter(payload)
        return parseToObjectAndCache(responseText, responseMap, fromJson, remaining, captureErrors)
    } catch (exception: Exception) {
        responseMap.putAll(staleData)
        val remainingCount = partialQueries.count { !responseMap.containsKey(it.elementKey) }
        if (remainingCount > 0) throw RuntimeException(exception)
        val wrappedResponse = mapOf("data" to responseMap)
        return fromJson(wrappedResponse)
    }
}''';
  }

  String _getFromCacheMethod() {
    return codeGenUtils.createMethod(
      methodName: 'getFromCache',
      returnType: 'GraphLinkCacheEntry?',
      arguments: ['key: String', 'tags: List<String>', 'staleIfOffline: Boolean'],
      statements: [
        'val result = store.get(key) ?: return null',
        'val entry = GraphLinkCacheEntry.fromJson(decoder.decode(result))',
        codeGenUtils.ifStatement(
          condition: 'entry.isExpired()',
          ifBlockStatements: [
            codeGenUtils.ifStatement(
              condition: 'staleIfOffline',
              ifBlockStatements: ['return entry.asStale()'],
            ),
            'store.invalidate(key)',
            codeGenUtils.ifStatement(
              condition: 'tags.isNotEmpty()',
              ifBlockStatements: ['removeKeyFromTags(key, tags)'],
            ),
            'return null',
          ],
        ),
        'return entry',
      ],
    );
  }

  String _invalidateByTagsMethod() {
    return codeGenUtils.createMethod(
      methodName: 'invalidateByTags',
      returnType: 'Unit',
      arguments: ['tags: List<String>'],
      statements: [
        codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            'val tKey = tagKey(tag)',
            'val lock = tagLocks[tag] ?: continue',
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                'val data = store.get(tKey)',
                codeGenUtils.ifStatement(
                  condition: 'data != null',
                  ifBlockStatements: [
                    'val entry = GraphLinkTagEntry.fromJson(decoder.decode(data))',
                    codeGenUtils.forEachLoop(
                      variable: 'k',
                      iterable: 'entry.keys',
                      statements: ['store.invalidate(k)'],
                    ),
                    'store.invalidate(tKey)',
                  ],
                ),
              ],
              finallyStatements: ['lock.unlock()'],
            ),
          ],
        ),
      ],
    );
  }

  String _addKeyToTagsMethod() {
    return codeGenUtils.createMethod(
      methodName: 'addKeyToTags',
      returnType: 'Unit',
      arguments: ['key: String', 'tags: List<String>'],
      statements: [
        codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            'val tKey = tagKey(tag)',
            'val lock = tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }',
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                'val data = store.get(tKey)',
                'val entry = if (data != null) GraphLinkTagEntry.fromJson(decoder.decode(data)) else GraphLinkTagEntry()',
                'entry.add(key)',
                'store.set(tKey, encoder.encode(entry.toJson()))',
              ],
              finallyStatements: ['lock.unlock()'],
            ),
          ],
        ),
      ],
    );
  }

  String _removeKeyFromTagsMethod() {
    return codeGenUtils.createMethod(
      methodName: 'removeKeyFromTags',
      returnType: 'Unit',
      arguments: ['key: String', 'tags: List<String>'],
      statements: [
        codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            'val tKey = tagKey(tag)',
            'val lock = tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }',
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                'val data = store.get(tKey) ?: continue',
                'val entry = GraphLinkTagEntry.fromJson(decoder.decode(data))',
                'entry.remove(key)',
                codeGenUtils.ifStatement(
                  condition: 'entry.keys.isEmpty()',
                  ifBlockStatements: ['store.invalidate(tKey)'],
                  elseBlockStatements: ['store.set(tKey, encoder.encode(entry.toJson()))'],
                ),
              ],
              finallyStatements: ['lock.unlock()'],
            ),
          ],
        ),
      ],
    );
  }

  // ── Operation classes ───────────────────────────────────────────────────────

  @override
  GLClassModel? getQueriesClass() => _buildClassForType(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() => _buildClassForType(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() => _buildClassForType(GLQueryType.subscription);

  GLClassModel? _buildClassForType(GLQueryType type) {
    final container = GLImportContainer();
    _activeContainer = container;

    container.importDepencies.addAll([
      _grammar.getTypeByName('GraphLinkClientAdapter')!,
      _grammar.getTypeByName('GraphLinkJsonEncoder')!,
      _grammar.getTypeByName('GraphLinkJsonDecoder')!,
    ]);

    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

    final ctorParams = _ctorParams(type);
    final extraFields = <String>[
      if (type == GLQueryType.subscription)
        'private lateinit var handler: GraphLinkSubscriptionHandler',
    ];

    final body = codeGenUtils.openClass(
      name: _classNameFor(type),
      params: ctorParams,
      interfaces: [_superCtorCall(type)],
      body: [
        ...extraFields,
        '',
        if (type == GLQueryType.subscription)
          'init ${codeGenUtils.block(['handler = GraphLinkSubscriptionHandler(wsAdapter, decoder, encoder)'])}',
        '',
        ...methods,
      ],
    );

    return GLClassModel(
      importDepencies: {
        ..._queryImports(type),
        ...container.importDepencies,
      }.toList(),
      imports: [...container.imports],
      body: body,
    );
  }

  List<String> _ctorParams(GLQueryType type) {
    return [
      'adapter: GraphLinkClientAdapter',
      if (type == GLQueryType.subscription) 'wsAdapter: GraphLinkWebSocketAdapter',
      if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
        'private val multipartAdapter: GraphLinkMultipartAdapter',
      'fragmentMap: Map<String, String>',
      'encoder: GraphLinkJsonEncoder',
      'decoder: GraphLinkJsonDecoder',
      'store: GraphLinkCacheStore',
    ];
  }

  String _superCtorCall(GLQueryType type) =>
      'GraphLinkResolverBase(adapter, fragmentMap, store, encoder, decoder)';


  String _buildPayloadMethod() {
    return codeGenUtils.createMethod(
      methodName: 'buildPayload',
      returnType: 'GraphLinkPayload',
      arguments: [
        'partQueries: List<GraphLinkPartialQuery>',
        'operationName: String',
        'directives: String',
      ],
      statements: [
        'val variables = mutableMapOf<String, Any?>()',
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['variables.putAll(q.variables)'],
        ),
        'val args = mutableSetOf<String>()',
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['args.addAll(q.argumentDeclarations)'],
        ),
        'val queryBuilder = StringBuilder("query \$operationName")',
        codeGenUtils.ifStatement(
          condition: 'args.isNotEmpty()',
          ifBlockStatements: [
            'queryBuilder.append("(")',
            'queryBuilder.append(args.joinToString(", "))',
            'queryBuilder.append(")")',
          ],
        ),
        codeGenUtils.ifStatement(
          condition: 'directives.isNotEmpty()',
          ifBlockStatements: ['queryBuilder.append(directives)'],
        ),
        'queryBuilder.append("{")',
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['queryBuilder.append(q.query)', 'queryBuilder.append(" ")'],
        ),
        'queryBuilder.append("}")',
        'val fragmentNames = mutableSetOf<String>()',
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['fragmentNames.addAll(q.fragmentNames)'],
        ),
        'val fragmentsBuilder = StringBuilder()',
        codeGenUtils.forEachLoop(
          variable: 'fragName',
          iterable: 'fragmentNames',
          statements: ['fragmentsBuilder.append(fragmentMap[fragName])'],
        ),
        'queryBuilder.append(fragmentsBuilder)',
        codeGenUtils.constructorCall('return GraphLinkPayload', [
          'query = queryBuilder.toString()',
          'operationName = operationName',
          'variables = variables',
        ]),
      ],
    );
  }

  String _assembleQueryMethod() {
    return codeGenUtils.createMethod(
      methodName: 'assembleQuery',
      returnType: 'String',
      arguments: [
        'query: String',
        'fragmentNames: Set<String>',
      ],
      statements: [
        'val buffer = StringBuilder(query)',
        codeGenUtils.forEachLoop(
          variable: 'name',
          iterable: 'fragmentNames',
          statements: [
            'val frag = fragmentMap[name]',
            codeGenUtils.ifStatement(
              condition: 'frag != null',
              ifBlockStatements: [
                'buffer.append("\\n")',
                'buffer.append(frag)',
              ],
            ),
          ],
        ),
        'return buffer.toString()',
      ],
    );
  }

  Set<GLToken> _queryImports(GLQueryType type) =>
      schemaTokensFor(type).toSet();

  // ── Boilerplate file models ─────────────────────────────────────────────────

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: kotlinGLUpload);

  GLClassModel generateUploadProgressCallbackFile() =>
      const GLClassModel(body: kotlinUploadProgressCallback);

  GLClassModel generateMultipartAdapterFile() =>
      const GLClassModel(body: kotlinGraphLinkMultipartAdapter);

  GLClassModel generateClientAdapterFile() => GLClassModel(
        body: _grammar.operationNameAsParameter
            ? kotlinGraphLinkClientAdapterWithOperationName
            : kotlinGraphLinkClientAdapter,
      );

  GLClassModel generateJsonEncoderFile() => const GLClassModel(body: kotlinGraphLinkJsonEncoder);

  GLClassModel generateJsonDecoderFile() => const GLClassModel(body: kotlinGraphLinkJsonDecoder);

  GLClassModel generateCacheStoreFile() => const GLClassModel(body: kotlinGraphLinkCacheStore);

  GLClassModel generateInMemoryCacheStoreFile() =>
      const GLClassModel(body: kotlinInMemoryGraphLinkCacheStore);

  GLClassModel generateCacheEntryFile() => const GLClassModel(body: kotlinGraphLinkCacheEntry);

  GLClassModel generateTagEntryFile() => const GLClassModel(body: kotlinGraphLinkTagEntry);

  GLClassModel generatePartialQueryFile() => GLClassModel(
        importDepencies: [_grammar.getTokenByKey('GraphLinkJsonEncoder')!],
        body: kotlinGraphLinkPartialQuery,
      );

  GLClassModel generateCodecFile() => GLClassModel(
        importDepencies: [
          _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: kotlinxSerializationCodec,
      );

  GLClassModel generateDefaultClientAdapterFile() => GLClassModel(
        importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
        body: _grammar.hasUploadMutations
            ? kotlinDefaultGraphLinkClientAdapterWithUpload(_grammar.operationNameAsParameter)
            : kotlinDefaultGraphLinkClientAdapter(_grammar.operationNameAsParameter),
      );

  GLClassModel generateWebSocketAdapterFile() =>
      const GLClassModel(body: kotlinGraphLinkWebSocketAdapter);

  GLClassModel generateDefaultWebSocketAdapterFile() =>
      const GLClassModel(body: kotlinDefaultGraphLinkWebSocketAdapter);

  GLClassModel generateAckStatusFile() => const GLClassModel(body: kotlinGraphLinkAckStatus);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: kotlinGraphlinkWsMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() => GLClassModel(
        importDepencies: [
          _grammar.getTokenByKey('GraphLinkPayload')!,
          _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: kotlinGraphLinkSubscriptionHandler,
      );

  GLClassModel generateExceptionFile() {
    final errorToken = _grammar.getTokenByKey('GraphLinkError');
    final body = codeGenUtils.openClass(
      name: '$kotlinClientException(val errors: List<GraphLinkError>) : Exception',
      params: [],
    );
    return GLClassModel(
      importDepencies: [if (errorToken != null) errorToken],
      body: body,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _classNameFor(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return 'GraphLinkQueries';
      case GLQueryType.mutation:
        return 'GraphLinkMutations';
      case GLQueryType.subscription:
        return 'GraphLinkSubscriptions';
    }
  }

  String get fileExtension => '.kt';

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    return ['GraphLinkJsonEncoder', 'GraphLinkJsonDecoder', 'GraphLinkClientAdapter']
        .map(g.getTokenByKey)
        .whereType<GLToken>()
        .toSet();
  }
}
