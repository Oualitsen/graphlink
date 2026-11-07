import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_rest_constants.dart';
import 'package:graphlink/src/serializers/kotlin/kotlin_imports.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_serializer.dart';

class KotlinClientRuntimeSerializer {
  final KotlinClientSerializer _client;
  KotlinClientRuntimeSerializer(this._client);

  GLClassModel generateGraphLinkResolverBaseFile(String packageName) {
    final allTags = _client.grammar.getAllCacheTags();
    final withOpName = _client.grammar.operationNameAsParameter;

    final body = _client.codeGenUtils.openClass(
      name: 'GraphLinkResolverBase',
      params: [
        'private val adapter: GraphLinkClientAdapter',
        'protected val fragmentMap: Map<String, String>',
        'protected val store: GraphLinkCacheStore',
        'protected val encoder: GraphLinkJsonEncoder',
        'protected val decoder: GraphLinkJsonDecoder',
        if (_client.grammar.persistedQueriesUseGet) 'private val getAdapter: GraphLinkClientAdapter? = null',
      ],
      body: [
        if (_client.grammar.persistedQueries) ...[
          'private val hashes = java.util.concurrent.ConcurrentHashMap<String, String>()',
          '@Volatile private var persistedUnsupported = false',
          if (_client.grammar.persistedQueriesUseGet) '@Volatile private var getUnsupported = false',
          '',
          _glHashMethod(),
          '',
          _glSendMethod(withOpName),
          '',
          if (_client.grammar.persistedQueriesUseGet) ...[_glSendHashOnlyMethod(withOpName), ''],
        ],
        'private val tagLocks = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.locks.ReentrantLock>()',
        '',
        'init ${_client.codeGenUtils.block([
          'val tags = listOf<String>(${allTags.map((t) => '"$t"').join(', ')})',
          _client.codeGenUtils.forEachLoop(
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
        _client.grammar.getTokenByKey('GraphLinkClientAdapter')!,
        _client.grammar.getTokenByKey('GraphLinkJsonEncoder')!,
        _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        _client.grammar.getTokenByKey('GraphLinkPayload')!,
        _client.grammar.getTokenByKey('GraphLinkFullResponse')!,
      ],
      body: body,
    );
  }

  String _glCallAdapterMethod(bool withOpName) {
    if (_client.grammar.persistedQueries) {
      return _client.codeGenUtils.suspendFun(
        name: 'glCallAdapter',
        arguments: ['payload: GraphLinkPayload'],
        returnType: 'String',
        statements: _persistedCallAdapterStatements(),
      );
    }
    final statements = withOpName
        ? [
            _client.codeGenUtils.constDecl('operationName', 'payload.operationName'),
            'return adapter.execute(encoder.encode(payload.toJson()), operationName)',
          ]
        : ['return adapter.execute(encoder.encode(payload.toJson()))'];
    return _client.codeGenUtils.suspendFun(
      name: 'glCallAdapter',
      arguments: ['payload: GraphLinkPayload'],
      returnType: 'String',
      statements: statements,
    );
  }

  String _glHashMethod() {
    return _client.codeGenUtils.createMethod(
      methodName: 'glHash',
      returnType: 'String',
      arguments: ['query: String'],
      statements: [
        _client.codeGenUtils.constDecl('cached', 'hashes[query]'),
        _client.codeGenUtils.ifStatement(
          condition: 'cached != null',
          ifBlockStatements: ['return cached'],
        ),
        _client.codeGenUtils.constDecl('hash', 'GraphLinkSha256.hex(query)'),
        'hashes[query] = hash',
        'return hash',
      ],
    );
  }

  String _glSendMethod(bool withOpName) {
    return 'private ${_client.codeGenUtils.suspendFun(
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
    return 'private ${_client.codeGenUtils.suspendFun(
      name: 'glSendHashOnly',
      arguments: ['payload: GraphLinkPayload', 'body: Map<String, Any?>'],
      returnType: 'String',
      statements: [
        _client.codeGenUtils.constDecl('target', 'getAdapter'),
        _client.codeGenUtils.ifStatement(
          condition: 'target == null || getUnsupported || payload.query.startsWith("mutation")',
          ifBlockStatements: ['return glSend(body)'],
        ),
        _client.codeGenUtils.tryCatchFinally(
          tryStatements: ['return $call'],
          catchVariable: 'e',
          catchStatements: [
            _client.codeGenUtils.ifStatement(
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
      _client.codeGenUtils.ifStatement(
        condition:
            'persistedUnsupported || payload.query.length <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH',
        ifBlockStatements: ['return glSend(payload.toJson())'],
      ),
      _client.codeGenUtils.constDecl('extensions', 'GraphLinkPersistedQueries.extensions(glHash(payload.query))'),
      _client.codeGenUtils.constDecl('hashOnly',
          'mapOf("operationName" to payload.operationName, "variables" to payload.variables, "extensions" to extensions)'),
      _client.codeGenUtils.constDecl(
        'response',
        _client.grammar.persistedQueriesUseGet ? 'glSendHashOnly(payload, hashOnly)' : 'glSend(hashOnly)',
      ),
      _client.codeGenUtils.constDecl('failure', 'GraphLinkPersistedQueries.failure(response, decoder)'),
      _client.codeGenUtils.ifStatement(condition: 'failure == null', ifBlockStatements: ['return response']),
      _client.codeGenUtils.constDecl('body', 'payload.toJson().toMutableMap()'),
      _client.codeGenUtils.ifStatement(
        condition: 'failure == GraphLinkPersistedQueries.NOT_SUPPORTED',
        ifBlockStatements: ['persistedUnsupported = true'],
        elseBlockStatements: ['body["extensions"] = extensions'],
      ),
      'return glSend(body)',
    ];
  }

  String _parseToObjectAndCacheMethod() {
    return _client.codeGenUtils.suspendFun(
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
        _client.codeGenUtils.constDecl('result', 'decoder.decode(data)'),
        _client.codeGenUtils.constDecl('rawData', 'result["data"] as? Map<String, Any?>'),
        _client.codeGenUtils.constDecl('dataMap', 'rawData?.toMutableMap() ?: mutableMapOf()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'remainingQueries',
          statements: [
            _client.codeGenUtils.ifStatement(
              condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
              ifBlockStatements: [
                _client.codeGenUtils.constDecl('cacheWrap', 'mapOf("__gl_v__" to dataMap[q.elementKey])'),
                _client.codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry(encoder.encode(cacheWrap), System.currentTimeMillis() + q.ttl * 1000L)'),
                'store.set(q.cacheKey, encoder.encode(entry.toJson()))',
                _client.codeGenUtils.ifStatement(
                  condition: 'q.tags.isNotEmpty()',
                  ifBlockStatements: ['addKeyToTags(q.cacheKey, q.tags)'],
                ),
              ],
            ),
          ],
        ),
        'dataMap.putAll(cachedResponse)',
        _client.codeGenUtils.constDecl('fullResponse', 'mutableMapOf<String, Any?>("data" to ${_client.codeGenUtils.ternaryOp(
          condition: 'rawData != null',
          positiveStatement: 'dataMap',
          negativeStatement: 'null',
        )})'),
        _client.codeGenUtils.ifStatement(
          condition: 'result.containsKey("errors")',
          ifBlockStatements: ['fullResponse["errors"] = result["errors"]'],
        ),
        _client.codeGenUtils.constDecl('parsed', 'parser(fullResponse)'),
        _client.codeGenUtils.ifStatement(condition: 'captureErrors', ifBlockStatements: ['return parsed']),
        _client.codeGenUtils.constDecl('errors', 'result["errors"] as? List<*>'),
        _client.codeGenUtils.ifStatement(
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
    return _client.codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> executeFull',
      arguments: _executeArguments,
      returnType: 'T',
      statements: [
        _client.codeGenUtils.constDecl('fullQuery', 'assembleQuery(query, fragmentNames)'),
        _client.codeGenUtils.constDecl('payload', _client.codeGenUtils.callExpression('GraphLinkPayload', ['query = fullQuery', 'operationName = operationName', 'variables = variables'])),
        _client.codeGenUtils.constDecl('responseText', 'glCallAdapter(payload)'),
        'return fromJson(decoder.decode(responseText))',
      ],
    );
  }

  String _executeDataMethod() {
    return _client.codeGenUtils.suspendFun(
      name: '<T : GraphLinkFullResponse> executeData',
      arguments: _executeArguments,
      returnType: 'T',
      statements: [
        _client.codeGenUtils.constDecl('decoded', _client.codeGenUtils.callExpression('executeFull', ['query', 'fragmentNames', 'operationName', 'variables', 'fromJson'])),
        _client.codeGenUtils.constDecl('errors', 'decoded.errors'),
        _client.codeGenUtils.ifStatement(
          condition: 'errors != null && errors.isNotEmpty()',
          ifBlockStatements: ['throw $kotlinClientException(errors)'],
        ),
        'return decoded',
      ],
    );
  }

  String _executeCachedMethod() {
    const cacheValue = 'decoder.decode(entry.data)["__gl_v__"]';
    return _client.codeGenUtils.suspendFun(
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
        _client.codeGenUtils.constDecl('responseMap', 'mutableMapOf<String, Any?>()'),
        _client.codeGenUtils.constDecl('staleData', 'mutableMapOf<String, Any?>()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'partQuery',
          iterable: 'partialQueries',
          statements: [
            _client.codeGenUtils.ifStatement(
              condition: 'partQuery.ttl > 0',
              ifBlockStatements: [
                _client.codeGenUtils.tryCatchFinally(
                  tryStatements: [
                    _client.codeGenUtils.constDecl('entry', _client.codeGenUtils.callExpression('getFromCache', ['partQuery.cacheKey', 'partQuery.tags', 'partQuery.staleIfOffline'])),
                    _client.codeGenUtils.ifStatement(
                      condition: 'entry != null',
                      ifBlockStatements: [
                        _client.codeGenUtils.ifStatement(
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
        _client.codeGenUtils.constDecl('remaining', 'partialQueries.filter { !responseMap.containsKey(it.elementKey) }.toMutableList()'),
        _client.codeGenUtils.ifStatement(
          condition: 'remaining.isEmpty()',
          ifBlockStatements: [
            _client.codeGenUtils.constDecl('wrappedResponse', 'mapOf("data" to responseMap)'),
            'return fromJson(wrappedResponse)',
          ],
        ),
        _client.codeGenUtils.constDecl('payload', _client.codeGenUtils.callExpression('buildPayload', ['remaining', 'operationName', 'directives'])),
        _client.codeGenUtils.tryCatchFinally(
          tryStatements: [
            _client.codeGenUtils.constDecl('responseText', 'glCallAdapter(payload)'),
            'return ${_client.codeGenUtils.callExpression('parseToObjectAndCache', ['responseText', 'responseMap', 'fromJson', 'remaining', 'captureErrors'])}',
          ],
          catchVariable: 'exception',
          catchStatements: [
            'responseMap.putAll(staleData)',
            _client.codeGenUtils.constDecl('remainingCount', 'partialQueries.count { !responseMap.containsKey(it.elementKey) }'),
            _client.codeGenUtils.ifStatement(
              condition: 'remainingCount > 0',
              ifBlockStatements: ['throw RuntimeException(exception)'],
            ),
            _client.codeGenUtils.constDecl('wrappedResponse', 'mapOf("data" to responseMap)'),
            'return fromJson(wrappedResponse)',
          ],
        ),
      ],
    );
  }

  String _getFromCacheMethod() {
    return _client.codeGenUtils.createMethod(
      methodName: 'getFromCache',
      returnType: 'GraphLinkCacheEntry?',
      arguments: ['key: String', 'tags: List<String>', 'staleIfOffline: Boolean'],
      statements: [
        _client.codeGenUtils.constDecl('result', 'store.get(key) ?: return null'),
        _client.codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry.fromJson(decoder.decode(result))'),
        _client.codeGenUtils.ifStatement(
          condition: 'entry.isExpired()',
          ifBlockStatements: [
            _client.codeGenUtils.ifStatement(
              condition: 'staleIfOffline',
              ifBlockStatements: ['return entry.asStale()'],
            ),
            'store.invalidate(key)',
            _client.codeGenUtils.ifStatement(
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
    return _client.codeGenUtils.createMethod(
      methodName: 'invalidateByTags',
      returnType: 'Unit',
      arguments: ['tags: List<String>'],
      statements: [
        _client.codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            _client.codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            _client.codeGenUtils.constDecl('lock', 'tagLocks[tag] ?: continue'),
            'lock.lock()',
            _client.codeGenUtils.tryCatchFinally(
              tryStatements: [
                _client.codeGenUtils.constDecl('data', 'store.get(tKey)'),
                _client.codeGenUtils.ifStatement(
                  condition: 'data != null',
                  ifBlockStatements: [
                    _client.codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.fromJson(decoder.decode(data))'),
                    _client.codeGenUtils.forEachLoop(
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
    return _client.codeGenUtils.createMethod(
      methodName: 'addKeyToTags',
      returnType: 'Unit',
      arguments: ['key: String', 'tags: List<String>'],
      statements: [
        _client.codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            _client.codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            _client.codeGenUtils.constDecl('lock', 'tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }'),
            'lock.lock()',
            _client.codeGenUtils.tryCatchFinally(
              tryStatements: [
                _client.codeGenUtils.constDecl('data', 'store.get(tKey)'),
                _client.codeGenUtils.constDecl('entry', _client.codeGenUtils.ternaryOp(
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
    return _client.codeGenUtils.createMethod(
      methodName: 'removeKeyFromTags',
      returnType: 'Unit',
      arguments: ['key: String', 'tags: List<String>'],
      statements: [
        _client.codeGenUtils.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            _client.codeGenUtils.constDecl('tKey', 'tagKey(tag)'),
            _client.codeGenUtils.constDecl('lock', 'tagLocks.getOrPut(tag) { java.util.concurrent.locks.ReentrantLock() }'),
            'lock.lock()',
            _client.codeGenUtils.tryCatchFinally(
              tryStatements: [
                _client.codeGenUtils.constDecl('data', 'store.get(tKey) ?: continue'),
                _client.codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.fromJson(decoder.decode(data))'),
                'entry.remove(key)',
                _client.codeGenUtils.ifStatement(
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

  String _buildPayloadMethod() {
    return _client.codeGenUtils.createMethod(
      methodName: 'buildPayload',
      returnType: 'GraphLinkPayload',
      arguments: [
        'partQueries: List<GraphLinkPartialQuery>',
        'operationName: String',
        'directives: String',
      ],
      statements: [
        _client.codeGenUtils.constDecl('variables', 'mutableMapOf<String, Any?>()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['variables.putAll(q.variables)'],
        ),
        _client.codeGenUtils.constDecl('args', 'mutableSetOf<String>()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['args.addAll(q.argumentDeclarations)'],
        ),
        _client.codeGenUtils.constDecl('queryBuilder', 'StringBuilder("query \$operationName")'),
        _client.codeGenUtils.ifStatement(
          condition: 'args.isNotEmpty()',
          ifBlockStatements: [
            'queryBuilder.append("(")',
            'queryBuilder.append(args.joinToString(", "))',
            'queryBuilder.append(")")',
          ],
        ),
        _client.codeGenUtils.ifStatement(
          condition: 'directives.isNotEmpty()',
          ifBlockStatements: ['queryBuilder.append(directives)'],
        ),
        'queryBuilder.append("{")',
        _client.codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['queryBuilder.append(q.query)', 'queryBuilder.append(" ")'],
        ),
        'queryBuilder.append("}")',
        _client.codeGenUtils.constDecl('fragmentNames', 'mutableSetOf<String>()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'q',
          iterable: 'partQueries',
          statements: ['fragmentNames.addAll(q.fragmentNames)'],
        ),
        _client.codeGenUtils.constDecl('fragmentsBuilder', 'StringBuilder()'),
        _client.codeGenUtils.forEachLoop(
          variable: 'fragName',
          iterable: 'fragmentNames',
          statements: ['fragmentsBuilder.append(fragmentMap[fragName])'],
        ),
        'queryBuilder.append(fragmentsBuilder)',
        _client.codeGenUtils.constructorCall('return GraphLinkPayload', [
          'query = queryBuilder.toString()',
          'operationName = operationName',
          'variables = variables',
        ]),
      ],
    );
  }

  String _assembleQueryMethod() {
    return _client.codeGenUtils.createMethod(
      methodName: 'assembleQuery',
      returnType: 'String',
      arguments: [
        'query: String',
        'fragmentNames: Set<String>',
      ],
      statements: [
        _client.codeGenUtils.constDecl('buffer', 'StringBuilder(query)'),
        _client.codeGenUtils.forEachLoop(
          variable: 'name',
          iterable: 'fragmentNames',
          statements: [
            _client.codeGenUtils.constDecl('frag', 'fragmentMap[name]'),
            _client.codeGenUtils.ifStatement(
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

  GLClassModel generateRestFile() => GLClassModel(
        importDepencies: [_client.grammar.getTokenByKey('GraphLinkClientAdapter')!],
        body: '$kotlinRestFile\n${kotlinNoGraphQLAdapter(_client.grammar.operationNameAsParameter)}',
      );

  GLClassModel generateRestResolverFile() => GLClassModel(
        importDepencies: [
          _client.grammar.getTokenByKey('GraphLinkClientAdapter')!,
          _client.grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: kotlinRestResolver(withGetAdapter: _client.grammar.persistedQueriesUseGet),
      );

  GLClassModel generateUploadProgressCallbackFile() =>
      const GLClassModel(body: kotlinUploadProgressCallback);

  GLClassModel generateMultipartAdapterFile() =>
      const GLClassModel(body: kotlinGraphLinkMultipartAdapter);

  GLClassModel generateClientAdapterFile() => GLClassModel(
        body: _client.grammar.operationNameAsParameter
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
        importDepencies: [_client.grammar.getTokenByKey('GraphLinkJsonEncoder')!],
        body: kotlinGraphLinkPartialQuery,
      );

  GLClassModel generateCodecFile() => GLClassModel(
        importDepencies: [
          _client.grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        ],
        body: kotlinxSerializationCodec,
      );

  GLClassModel generateSha256File() {
    if (!_client.grammar.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(body: kotlinSha256);
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!_client.grammar.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      importDepencies: [
        _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
        if (_client.grammar.persistedQueriesUseGet) _client.grammar.getTokenByKey('GraphLinkJsonEncoder')!,
      ],
      body: _client.grammar.persistedQueriesUseGet
          ? '$kotlinPersistedQueries\n$kotlinPersistedQueriesGet'
          : kotlinPersistedQueries,
    );
  }

  GLClassModel generateWebSocketAdapterFile() =>
      const GLClassModel(body: kotlinGraphLinkWebSocketAdapter);

  GLClassModel generateAckStatusFile() => const GLClassModel(body: kotlinGraphLinkAckStatus);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: kotlinGraphlinkWsMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() => GLClassModel(
        importDepencies: [
          _client.grammar.getTokenByKey('GraphLinkPayload')!,
          _client.grammar.getTokenByKey('GraphLinkJsonEncoder')!,
          _client.grammar.getTokenByKey('GraphLinkJsonDecoder')!,
          _client.grammar.getTokenByKey('GraphLinkError')!,
        ],
        body: kotlinGraphLinkSubscriptionHandler,
      );

  GLClassModel generateExceptionFile() {
    final errorToken = _client.grammar.getTokenByKey('GraphLinkError');
    final body = _client.codeGenUtils.openClass(
      name: '$kotlinClientException(val errors: List<GraphLinkError>) : Exception',
      params: [],
    );
    return GLClassModel(
      importDepencies: [if (errorToken != null) errorToken],
      body: body,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
}
