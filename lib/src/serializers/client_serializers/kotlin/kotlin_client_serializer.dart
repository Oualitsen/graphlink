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
        'queries = ${_classNameFor(GLQueryType.query)}(adapter, ${_getAdapterArg}fragmentMap, encoder, decoder, store)',
      if (_grammar.hasMutations)
        'mutations = ${_classNameFor(GLQueryType.mutation)}(adapter, $_getAdapterArg${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}fragmentMap, encoder, decoder, store)',
      if (_grammar.hasSubscriptions)
        'subscriptions = ${_classNameFor(GLQueryType.subscription)}(adapter, wsAdapter, fragmentMap, encoder, decoder, store)',
      ..._grammar.usedFragments
          .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
          .map((f) =>
              'fragmentMap["${f.tokenInfo}"] = "${gqlSerializer.serializeFragmentDefinitionBase(f).escapeForStringLiteral()}"'),
    ];

    final primaryCtorArgs = [
      'private val adapter: GraphLinkClientAdapter',
      if (_grammar.persistedQueriesUseGet) 'private val getAdapter: GraphLinkClientAdapter',
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
    List<String> callArgs(String adapterExpr, String wsExpr, {String getArgs = ''}) {
      final getExpr = _grammar.persistedQueriesUseGet ? ', DefaultGraphLinkGetAdapter(url$getArgs)' : '';
      if (hasUploads) {
        return [
          codeGenUtils.constDecl('a', '$adapterExpr'),
          'return ${codeGenUtils.callExpression('$kotlinClientName', ['a$getExpr${hasSubs ? ', $wsExpr' : ''}', 'a', 'encoder', 'decoder'])}',
        ];
      }
      return ['return ${codeGenUtils.callExpression('$kotlinClientName', ['$adapterExpr$getExpr${hasSubs ? ', $wsExpr' : ''}', 'encoder', 'decoder'])}'];
    }

    String factory(List<String> arguments, List<String> statements) => codeGenUtils.createMethod(
          methodName: 'create',
          returnType: kotlinClientName,
          arguments: arguments,
          statements: statements,
        );

    const codecArgs = ['encoder: GraphLinkJsonEncoder', 'decoder: GraphLinkJsonDecoder'];
    const headersArg = 'headersProvider: () -> Map<String, String>';

    if (!hasSubs) {
      return [
        '',
        codeGenUtils.companionObject([
          factory(['url: String', ...codecArgs], callArgs('DefaultGraphLinkClientAdapter(url)', '')),
          factory(['url: String', headersArg, ...codecArgs], callArgs('DefaultGraphLinkClientAdapter(url, headersProvider)', '', getArgs: ', headersProvider')),
          factory(['url: String'], ['return ${codeGenUtils.callExpression('create', ['url', '$codec', '$codec'])}']),
        ]),
      ];
    }

    return [
      '',
      codeGenUtils.companionObject([
        factory(['url: String', 'wsUrl: String', ...codecArgs],
            callArgs('DefaultGraphLinkClientAdapter(url)', 'DefaultGraphLinkWebSocketAdapter(wsUrl)')),
        factory(['url: String', 'wsUrl: String', headersArg, ...codecArgs],
            callArgs('DefaultGraphLinkClientAdapter(url, headersProvider)', 'DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider)', getArgs: ', headersProvider')),
        factory(['url: String'], [
          codeGenUtils.constDecl('ws', 'url.replaceFirst("http", "ws")'),
          'return ${codeGenUtils.callExpression('create', ['url', 'ws', '$codec', '$codec'])}',
        ]),
      ]),
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
        if (_grammar.persistedQueriesUseGet) 'private val getAdapter: GraphLinkClientAdapter? = null',
      ],
      body: [
        if (_grammar.persistedQueries) ...[
          'private val hashes = java.util.concurrent.ConcurrentHashMap<String, String>()',
          '@Volatile private var persistedUnsupported = false',
          if (_grammar.persistedQueriesUseGet) '@Volatile private var getUnsupported = false',
          '',
          _glHashMethod(),
          '',
          _glSendMethod(withOpName),
          '',
          if (_grammar.persistedQueriesUseGet) ...[_glSendHashOnlyMethod(withOpName), ''],
        ],
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
    if (_grammar.persistedQueries) {
      return codeGenUtils.suspendFun(
        name: 'glCallAdapter',
        arguments: ['payload: GraphLinkPayload'],
        returnType: 'String',
        statements: _persistedCallAdapterStatements(),
      );
    }
    final statements = withOpName
        ? [
            codeGenUtils.constDecl('operationName', 'payload.operationName'),
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

  String get _getAdapterArg => _grammar.persistedQueriesUseGet ? 'getAdapter, ' : '';

  String _glHashMethod() {
    return codeGenUtils.createMethod(
      methodName: 'glHash',
      returnType: 'String',
      arguments: ['query: String'],
      statements: [
        codeGenUtils.constDecl('cached', 'hashes[query]'),
        codeGenUtils.ifStatement(
          condition: 'cached != null',
          ifBlockStatements: ['return cached'],
        ),
        codeGenUtils.constDecl('hash', 'GraphLinkSha256.hex(query)'),
        'hashes[query] = hash',
        'return hash',
      ],
    );
  }

  String _glSendMethod(bool withOpName) {
    return 'private ${codeGenUtils.suspendFun(
      name: 'glSend',
      arguments: ['body: Map<String, Any?>'],
      returnType: 'String',
      statements: [
        if (withOpName) 'return adapter.execute(encoder.encode(body), body["operationName"] as String)'
        else 'return adapter.execute(encoder.encode(body))',
      ],
    )}';
  }

  String _glSendHashOnlyMethod(bool withOpName) {
    final call = withOpName
        ? 'target.execute(encoder.encode(body), body["operationName"] as String)'
        : 'target.execute(encoder.encode(body))';
    return 'private ${codeGenUtils.suspendFun(
      name: 'glSendHashOnly',
      arguments: ['payload: GraphLinkPayload', 'body: Map<String, Any?>'],
      returnType: 'String',
      statements: [
        codeGenUtils.constDecl('target', 'getAdapter'),
        codeGenUtils.ifStatement(
          condition: 'target == null || getUnsupported || payload.query.startsWith("mutation")',
          ifBlockStatements: ['return glSend(body)'],
        ),
        codeGenUtils.tryCatchFinally(
          tryStatements: ['return $call'],
          catchVariable: 'e',
          catchStatements: [
            codeGenUtils.ifStatement(
              condition: 'e !is GraphLinkGetNotSupported',
              ifBlockStatements: ['throw e'],
            ),
            'getUnsupported = true',
            'return glSend(body)',
          ],
        ),
      ],
    )}';
  }

  List<String> _persistedCallAdapterStatements() {
    return [
      codeGenUtils.ifStatement(
        condition:
            'persistedUnsupported || payload.query.length <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH',
        ifBlockStatements: ['return glSend(payload.toJson())'],
      ),
      codeGenUtils.constDecl('extensions', 'GraphLinkPersistedQueries.extensions(glHash(payload.query))'),
      codeGenUtils.constDecl('hashOnly',
          'mapOf("operationName" to payload.operationName, "variables" to payload.variables, "extensions" to extensions)'),
      codeGenUtils.constDecl(
        'response',
        _grammar.persistedQueriesUseGet ? 'glSendHashOnly(payload, hashOnly)' : 'glSend(hashOnly)',
      ),
      codeGenUtils.constDecl('failure', 'GraphLinkPersistedQueries.failure(response, decoder)'),
      codeGenUtils.ifStatement(condition: 'failure == null', ifBlockStatements: ['return response']),
      codeGenUtils.constDecl('body', 'payload.toJson().toMutableMap()'),
      codeGenUtils.ifStatement(
        condition: 'failure == GraphLinkPersistedQueries.NOT_SUPPORTED',
        ifBlockStatements: ['persistedUnsupported = true'],
        elseBlockStatements: ['body["extensions"] = extensions'],
      ),
      'return glSend(body)',
    ];
  }

  String _parseToObjectAndCacheMethod() {
    return codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> parseToObjectAndCache',
      arguments: [
        'data: String',
        'cachedResponse: MutableMap<String, Any?>',
        'parser: (Map<String, Any?>) -> T',
        'remainingQueries: List<GraphLinkPartialQuery>',
        'captureErrors: Boolean',
      ],
      returnType: 'T',
      statements: [
        codeGenUtils.constDecl('result', 'decoder.decode(data)'),
        codeGenUtils.constDecl('rawData', 'result["data"] as? Map<String, Any?>'),
        codeGenUtils.constDecl('dataMap', 'rawData?.toMutableMap() ?: mutableMapOf()'),
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'remainingQueries',
          statements: [
            codeGenUtils.ifStatement(
              condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
              ifBlockStatements: [
                codeGenUtils.constDecl('cacheWrap', 'mapOf("__gl_v__" to dataMap[q.elementKey])'),
                codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry(encoder.encode(cacheWrap), System.currentTimeMillis() + q.ttl * 1000L)'),
                'store.set(q.cacheKey, encoder.encode(entry.toJson()))',
                codeGenUtils.ifStatement(
                  condition: 'q.tags.isNotEmpty()',
                  ifBlockStatements: ['addKeyToTags(q.cacheKey, q.tags)'],
                ),
              ],
            ),
          ],
        ),
        'dataMap.putAll(cachedResponse)',
        codeGenUtils.constDecl('fullResponse', 'mutableMapOf<String, Any?>("data" to ${codeGenUtils.ternaryOp(
          condition: 'rawData != null',
          positiveStatement: 'dataMap',
          negativeStatement: 'null',
        )})'),
        codeGenUtils.ifStatement(
          condition: 'result.containsKey("errors")',
          ifBlockStatements: ['fullResponse["errors"] = result["errors"]'],
        ),
        codeGenUtils.constDecl('parsed', 'parser(fullResponse)'),
        codeGenUtils.ifStatement(condition: 'captureErrors', ifBlockStatements: ['return parsed']),
        codeGenUtils.constDecl('errors', 'result["errors"] as? List<*>'),
        codeGenUtils.ifStatement(
          condition: 'errors != null && errors.isNotEmpty()',
          ifBlockStatements: ['throw $kotlinClientException(parsed.errors ?: emptyList())'],
        ),
        'return parsed',
      ],
    );
  }

  List<String> get _executeArguments => [
        'query: String',
        'fragmentNames: Set<String>',
        'operationName: String',
        'variables: Map<String, Any?>',
        'fromJson: (Map<String, Any?>) -> T',
      ];

  String _executeFullMethod() {
    return codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> executeFull',
      arguments: _executeArguments,
      returnType: 'T',
      statements: [
        codeGenUtils.constDecl('fullQuery', 'assembleQuery(query, fragmentNames)'),
        codeGenUtils.constDecl('payload', codeGenUtils.callExpression('GraphLinkPayload', ['query = fullQuery', 'operationName = operationName', 'variables = variables'])),
        codeGenUtils.constDecl('responseText', 'glCallAdapter(payload)'),
        'return fromJson(decoder.decode(responseText))',
      ],
    );
  }

  String _executeDataMethod() {
    return codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> executeData',
      arguments: _executeArguments,
      returnType: 'T',
      statements: [
        codeGenUtils.constDecl('decoded', codeGenUtils.callExpression('executeFull', ['query', 'fragmentNames', 'operationName', 'variables', 'fromJson'])),
        codeGenUtils.constDecl('errors', 'decoded.errors'),
        codeGenUtils.ifStatement(
          condition: 'errors != null && errors.isNotEmpty()',
          ifBlockStatements: ['throw $kotlinClientException(errors)'],
        ),
        'return decoded',
      ],
    );
  }

  String _executeCachedMethod() {
    const cacheValue = 'decoder.decode(entry.data)["__gl_v__"]';
    return codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> executeCached',
      arguments: [
        'partialQueries: List<GraphLinkPartialQuery>',
        'operationName: String',
        'directives: String',
        'fromJson: (Map<String, Any?>) -> T',
        'captureErrors: Boolean',
      ],
      returnType: 'T',
      statements: [
        codeGenUtils.constDecl('responseMap', 'mutableMapOf<String, Any?>()'),
        codeGenUtils.constDecl('staleData', 'mutableMapOf<String, Any?>()'),
        codeGenUtils.forEachLoop(
          variable: 'partQuery',
          iterable: 'partialQueries',
          statements: [
            codeGenUtils.ifStatement(
              condition: 'partQuery.ttl > 0',
              ifBlockStatements: [
                codeGenUtils.tryCatchFinally(
                  tryStatements: [
                    codeGenUtils.constDecl('entry', codeGenUtils.callExpression('getFromCache', ['partQuery.cacheKey', 'partQuery.tags', 'partQuery.staleIfOffline'])),
                    codeGenUtils.ifStatement(
                      condition: 'entry != null',
                      ifBlockStatements: [
                        codeGenUtils.ifStatement(
                          condition: 'entry.stale',
                          ifBlockStatements: ['staleData[partQuery.elementKey] = $cacheValue'],
                          elseBlockStatements: ['responseMap[partQuery.elementKey] = $cacheValue'],
                        ),
                      ],
                    ),
                  ],
                  catchVariable: 'ignored',
                  catchStatements: [],
                ),
              ],
            ),
          ],
        ),
        codeGenUtils.constDecl('remaining', 'partialQueries.filter { !responseMap.containsKey(it.elementKey) }.toMutableList()'),
        codeGenUtils.ifStatement(
          condition: 'remaining.isEmpty()',
          ifBlockStatements: [
            codeGenUtils.constDecl('wrappedResponse', 'mapOf("data" to responseMap)'),
            'return fromJson(wrappedResponse)',
          ],
        ),
        codeGenUtils.constDecl('payload', codeGenUtils.callExpression('buildPayload', ['remaining', 'operationName', 'directives'])),
        codeGenUtils.tryCatchFinally(
          tryStatements: [
            codeGenUtils.constDecl('responseText', 'glCallAdapter(payload)'),
            'return ${codeGenUtils.callExpression('parseToObjectAndCache', ['responseText', 'responseMap', 'fromJson', 'remaining', 'captureErrors'])}',
          ],
          catchVariable: 'exception',
          catchStatements: [
            'responseMap.putAll(staleData)',
            codeGenUtils.constDecl('remainingCount', 'partialQueries.count { !responseMap.containsKey(it.elementKey) }'),
            codeGenUtils.ifStatement(
              condition: 'remainingCount > 0',
              ifBlockStatements: ['throw RuntimeException(exception)'],
            ),
            codeGenUtils.constDecl('wrappedResponse', 'mapOf("data" to responseMap)'),
            'return fromJson(wrappedResponse)',
          ],
        ),
      ],
    );
  }

  String _getFromCacheMethod() {
    return codeGenUtils.createMethod(
      methodName: 'getFromCache',
      returnType: 'GraphLinkCacheEntry?',
      arguments: ['key: String', 'tags: List<String>', 'staleIfOffline: Boolean'],
      statements: [
        codeGenUtils.constDecl('result', 'store.get(key) ?: return null'),
        codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry.fromJson(decoder.decode(result))'),
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
            codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            codeGenUtils.constDecl('lock', 'tagLocks[tag] ?: continue'),
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                codeGenUtils.constDecl('data', 'store.get(tKey)'),
                codeGenUtils.ifStatement(
                  condition: 'data != null',
                  ifBlockStatements: [
                    codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.fromJson(decoder.decode(data))'),
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
            codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            codeGenUtils.constDecl('lock', 'tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }'),
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                codeGenUtils.constDecl('data', 'store.get(tKey)'),
                codeGenUtils.constDecl('entry', codeGenUtils.ternaryOp(
                  condition: 'data != null',
                  positiveStatement: 'GraphLinkTagEntry.fromJson(decoder.decode(data))',
                  negativeStatement: 'GraphLinkTagEntry()',
                )),
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
            codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            codeGenUtils.constDecl('lock', 'tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }'),
            'lock.lock()',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                codeGenUtils.constDecl('data', 'store.get(tKey) ?: continue'),
                codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.fromJson(decoder.decode(data))'),
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
      if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet)
        'getAdapter: GraphLinkClientAdapter',
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
      codeGenUtils.callExpression('GraphLinkResolverBase', [
        'adapter',
        'fragmentMap',
        'store',
        'encoder',
        'decoder',
        if (type != GLQueryType.subscription && _grammar.persistedQueriesUseGet) 'getAdapter',
      ]);


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
        codeGenUtils.constDecl('variables', 'mutableMapOf<String, Any?>()'),
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['variables.putAll(q.variables)'],
        ),
        codeGenUtils.constDecl('args', 'mutableSetOf<String>()'),
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['args.addAll(q.argumentDeclarations)'],
        ),
        codeGenUtils.constDecl('queryBuilder', 'StringBuilder("query \$operationName")'),
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
        codeGenUtils.constDecl('fragmentNames', 'mutableSetOf<String>()'),
        codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['fragmentNames.addAll(q.fragmentNames)'],
        ),
        codeGenUtils.constDecl('fragmentsBuilder', 'StringBuilder()'),
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
        codeGenUtils.constDecl('buffer', 'StringBuilder(query)'),
        codeGenUtils.forEachLoop(
          variable: 'name',
          iterable: 'fragmentNames',
          statements: [
            codeGenUtils.constDecl('frag', 'fragmentMap[name]'),
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

  GLClassModel generateSha256File() {
    if (!_grammar.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(body: kotlinSha256);
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!_grammar.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      importDepencies: [
        _grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        if (_grammar.persistedQueriesUseGet) _grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      ],
      body: _grammar.persistedQueriesUseGet
          ? '$kotlinPersistedQueries\n$kotlinPersistedQueriesGet'
          : kotlinPersistedQueries,
    );
  }

  GLClassModel generateDefaultGetAdapterFile() {
    if (!_grammar.persistedQueriesUseGet) {
      throw StateError('The GET adapter is only generated when persistedQueriesUseGet is enabled.');
    }
    return GLClassModel(
      importDepencies: [_grammar.getTokenByKey('GraphLinkClientAdapter')!],
      body: kotlinDefaultGraphLinkGetAdapter(_grammar.operationNameAsParameter),
    );
  }

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
