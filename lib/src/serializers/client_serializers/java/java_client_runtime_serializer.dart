import 'package:graphlink/src/cache_store_java.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_vars.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_reactive_flavor.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_serializer.dart';

class JavaClientRuntimeSerializer {
  final JavaClientSerializer _client;
  JavaClientRuntimeSerializer(this._client);

  GLParser get _grammar => _client.grammar;
  JavaCodeGenUtils get codeGenUtils => _client.codeGenUtils;
  JavaReactiveFlavor get flavor => _client.flavor;
  GLSerializer get serializer => _client.serializer;
  String _wrapSingle(String inner) => _client.wrapSingle(inner);
  void _requireGet() => _client.requireGet();

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
}
