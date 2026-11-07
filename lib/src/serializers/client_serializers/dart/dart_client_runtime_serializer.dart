import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_vars.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_serializer.dart';

class DartClientRuntimeSerializer {
  final DartClientSerializer _client;
  DartClientRuntimeSerializer(this._client);

  /// Returns the standalone [GraphLinkCacheEntry] file.
  GLClassModel generateCacheEntryFile() {
    return const GLClassModel(
      imports: ["import 'dart:convert';"],
      body: cacheEntry,
    );
  }

  /// Returns the standalone [GraphLinkLock] file.
  GLClassModel generateLockFile() => const GLClassModel(body: glLock);

  /// Returns the standalone [GraphLinkTagEntry] file.
  GLClassModel generateTagEntryFile() => const GLClassModel(
        imports: ["import 'dart:convert';"],
        body: tagEntry,
      );

  /// Returns the standalone [GraphLinkPartialQuery] file.
  GLClassModel generatePartialQueryFile() => const GLClassModel(
        imports: ["import 'dart:convert';"],
        body: partialQuery,
      );

  /// Returns the standalone [GraphLinkCacheStore] file.
  GLClassModel generateCacheStoreFile() => const GLClassModel(
        imports: ["import 'dart:async';"],
        body: graphLinkCacheStore,
      );

  /// Returns the standalone [InMemoryGraphLinkCacheStore] file.
  GLClassModel generateInMemoryCacheStoreFile() => const GLClassModel(
        imports: ["import 'graph_link_cache_store.dart';"],
        body: inMemoryGraphLinkCacheStore,
      );

  /// Returns the standalone [GraphLinkSha256] file, only needed by persisted queries.
  GLClassModel generateSha256File() {
    if (!_client.parser.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(
      imports: ["import 'dart:convert';"],
      body: dartSha256,
    );
  }

  /// Returns the standalone [GraphLinkPersistedQueries] file, only needed by persisted queries.
  GLClassModel generatePersistedQueriesFile() {
    if (!_client.parser.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      imports: const ["import 'dart:convert';"],
      body: _client.parser.persistedQueriesUseGet ? '$dartPersistedQueries\n$dartPersistedQueriesGet' : dartPersistedQueries,
    );
  }

  /// Returns the resolver base file: tag prefix constant + [GraphLinkResolverBase].
  GLClassModel generateResolverBaseFile() {
    final payloadImport = _client.serializer.serializeImportToken(
        _client.parser.getTokenByKey('GraphLinkPayload')!);
    final errorImport = _client.serializer.serializeImportToken(
        _client.parser.getTokenByKey('GraphLinkError')!);
    return GLClassModel(
      imports: [
        "import 'dart:convert';",
        "import 'dart:async';",
        if (payloadImport.isNotEmpty) payloadImport,
        if (errorImport.isNotEmpty) errorImport,
        "import 'graph_link_cache_entry.dart';",
        "import 'graph_link_lock.dart';",
        "import 'graph_link_tag_entry.dart';",
        "import 'graph_link_cache_store.dart';",
        "import 'graph_link_partial_query.dart';",
        if (_client.parser.persistedQueries) ...[
          "import 'graph_link_sha256.dart';",
          "import 'graph_link_persisted_queries.dart';",
        ],
        _client.serializer.serializeImportToken(
            _client.parser.getTokenByKey('GraphLinkFullResponse')!),
      ],
      body: "const tagKeyPrefix = '__tag__';\n\n${buildResolverBaseClass()}",
    );
  }

  String _buildGlSendMethod() {
    final call = _client.parser.operationNameAsParameter
        ? "$svAdapter(json.encode(body), body['operationName'] as String)"
        : '$svAdapter(json.encode(body))';
    return _client.codeGenUtils.createMethod(
        returnType: 'Future<String>',
        methodName: 'glSend__',
        async: true,
        namedArguments: false,
        arguments: ['Map<String, dynamic> body'],
        statements: ['return await $call;']);
  }

  String _buildGlSendHashOnlyMethod() {
    final call = _client.parser.operationNameAsParameter
        ? "glGetAdapter__(json.encode(body), body['operationName'] as String)"
        : 'glGetAdapter__(json.encode(body))';
    return _client.codeGenUtils.createMethod(
        returnType: 'Future<String>',
        methodName: 'glSendHashOnly__',
        async: true,
        namedArguments: false,
        arguments: ['GraphLinkPayload payload', 'Map<String, dynamic> body'],
        statements: [
          _client.codeGenUtils.ifStatement(
              condition: "glGetUnsupported__ || payload.query.startsWith('mutation')",
              ifBlockStatements: ['return await glSend__(body);']),
          _client.codeGenUtils.tryCatchFinally(
              tryStatements: ['return await $call;'],
              catchVariable: 'e',
              catchStatements: [
                _client.codeGenUtils.ifStatement(
                    condition: 'e is! GraphLinkGetNotSupported', ifBlockStatements: ['rethrow;']),
                'glGetUnsupported__ = true;',
                'return await glSend__(body);',
              ]),
        ]);
  }

  List<String> _persistedCallAdapterStatements() {
    return [
      _client.codeGenUtils.ifStatement(
          condition:
              'glPersistedUnsupported__ || payload.query.length <= GraphLinkPersistedQueries.minQueryLength',
          ifBlockStatements: ['return await glSend__(payload.toJson());']),
      _client.codeGenUtils.constDecl(
          'glExtensions__', 'GraphLinkPersistedQueries.extensions(glHash(payload.query))'),
      _client.codeGenUtils.constDecl(
          'glHashOnly__',
          "{'operationName': payload.operationName, 'variables': payload.variables, 'extensions': glExtensions__}"),
      _client.codeGenUtils.constDecl(
          'glResponse__',
          _client.parser.persistedQueriesUseGet
              ? 'await glSendHashOnly__(payload, glHashOnly__)'
              : 'await glSend__(glHashOnly__)'),
      _client.codeGenUtils.constDecl('glFailure__', 'GraphLinkPersistedQueries.failure(glResponse__)'),
      _client.codeGenUtils.ifStatement(condition: 'glFailure__ == null', ifBlockStatements: ['return glResponse__;']),
      _client.codeGenUtils.constDecl('glBody__', 'payload.toJson()'),
      _client.codeGenUtils.ifStatement(
          condition: 'glFailure__ == GraphLinkPersistedQueries.notSupported',
          ifBlockStatements: ['glPersistedUnsupported__ = true;'],
          elseBlockStatements: ["glBody__['extensions'] = glExtensions__;"]),
      'return await glSend__(glBody__);',
    ];
  }

  String _buildGlHashMethod() {
    return _client.codeGenUtils.createMethod(
        returnType: 'String',
        methodName: 'glHash',
        namedArguments: false,
        arguments: ['String query'],
        statements: [
          _client.codeGenUtils.constDecl('cached', '_glHashes[query]'),
          _client.codeGenUtils.ifStatement(
              condition: 'cached != null',
              ifBlockStatements: ['return cached;']),
          _client.codeGenUtils.constDecl('hash', 'GraphLinkSha256.hex(query)'),
          '_glHashes[query] = hash;',
          'return hash;',
        ]);
  }

  String buildResolverBaseClass() {
    return _client.codeGenUtils.createClass(
        className: resolverBaseClassName,
        statements: [
          'late final $cacheStoreClassName $svStore;',
          'late final Map<String, GraphLinkLock> $svTagLocks;',
                    'late final Map<String, String> $svFragMap;',
          _client.declareHttpAdapter(),
          if (_client.parser.persistedQueries) ...[
            'final Map<String, String> _glHashes = {};',
            'bool glPersistedUnsupported__ = false;',
            _buildGlHashMethod(),
            _buildGlSendMethod(),
          ],
          if (_client.parser.persistedQueriesUseGet) ...[
            'final ${_client.delcareHttpAdapterFunction()} glGetAdapter__;',
            'bool glGetUnsupported__ = false;',
            _buildGlSendHashOnlyMethod(),
          ],
          _client.codeGenUtils.createMethod(
              methodName: resolverBaseClassName,
              namedArguments: false,
              arguments: [
                '$cacheStoreClassName store',
                'Map<String, GraphLinkLock> locks',
                'this.$svAdapter',
                if (_client.parser.persistedQueriesUseGet) 'this.glGetAdapter__',
                'Map<String, String> fragmentMap',
              ],
              statements: [
                '$svStore = store;',
                '$svTagLocks = locks;',
                '$svFragMap = fragmentMap;',
              ]),
          _client.codeGenUtils.createMethod(
              methodName: "assembleQuery",
              namedArguments: false,
              arguments: [
                "String query",
                "Set<String> fragmentNames",
              ],
              returnType: "String",
              statements: [
                _client.codeGenUtils.constDecl('buffer', 'StringBuffer(query)'),
                _client.codeGenUtils.forEachLoop(
                    variable: 'name',
                    iterable: 'fragmentNames',
                    statements: [
                      _client.codeGenUtils.constDecl('frag', '$svFragMap[name]'),
                      _client.codeGenUtils.ifStatement(
                          condition: 'frag != null',
                          ifBlockStatements: [
                            'buffer.write(" ");',
                            'buffer.write(frag);',
                          ]),
                    ]),
                'return buffer.toString();',
              ]),
          _client.codeGenUtils.createMethod(
              returnType: 'Future<String>',
              methodName: "glCallAdapter",
              async: true,
              namedArguments: false,
              arguments: ['GraphLinkPayload payload'],
              statements: _client.parser.persistedQueries
                  ? _persistedCallAdapterStatements()
                  : [
                      if (_client.parser.operationNameAsParameter)
                        'return await $svAdapter(json.encode(payload.toJson()), payload.operationName);'
                      else
                        'return await $svAdapter(json.encode(payload.toJson()));'
                    ]),
          _client.codeGenUtils.createMethod(
              returnType: 'Future<TFull>',
              methodName: 'executeFull<TFull extends GraphLinkFullResponse>',
              async: true,
              namedArguments: false,
              arguments: [
                'String query',
                'Set<String> fragmentNames',
                'String operationName',
                'Map<String, dynamic> variables',
                'TFull Function(Map<String, dynamic> json) fromJson',
              ],
              statements: [
                _client.codeGenUtils.constDecl('fullQuery', 'assembleQuery(query, fragmentNames)'),
                _client.codeGenUtils.constDecl(svPayload, _client.codeGenUtils.callExpression('GraphLinkPayload', ['query: fullQuery', 'operationName: operationName', 'variables: variables'])),
                _client.codeGenUtils.constDecl(svResponse, 'await glCallAdapter($svPayload)'),
                _client.codeGenUtils.constDecl('json', 'jsonDecode($svResponse)'),
                _client.codeGenUtils.ifStatement(
                    condition: "json is! Map<String, dynamic> || (json['data'] is! Map && !(json['errors'] is List && (json['errors'] as List).isNotEmpty))",
                    ifBlockStatements: ["throw [GraphLinkError(message: 'GraphQL response has no data', body: $svResponse)];"]),
                _client.codeGenUtils.ifStatement(
                    condition: "json['errors'] is List && (json['errors'] as List).isEmpty",
                    ifBlockStatements: ["json['errors'] = null;"]),
                'return fromJson(json);',
              ]),
          _client.codeGenUtils.createMethod(
              returnType: 'Future<TFull>',
              methodName: 'executeData<TFull extends GraphLinkFullResponse>',
              async: true,
              namedArguments: false,
              arguments: [
                'String query',
                'Set<String> fragmentNames',
                'String operationName',
                'Map<String, dynamic> variables',
                'TFull Function(Map<String, dynamic> json) fromJson',
              ],
              statements: [
                _client.codeGenUtils.constDecl(svResult, 'await ${_client.codeGenUtils.callExpression('executeFull<TFull>', ['query', 'fragmentNames', 'operationName', 'variables', 'fromJson'])}'),
                _client.codeGenUtils.ifStatement(
                    condition: '$svResult.errors != null',
                    ifBlockStatements: ['throw $svResult.errors!;']),
                'return $svResult;',
              ]),
          _client.codeGenUtils.createMethod(
              returnType: 'Future<TFull>',
              methodName: 'executeCached<TFull extends GraphLinkFullResponse>',
              async: true,
              namedArguments: false,
              arguments: [
                'List<GraphLinkPartialQuery> partialQueries',
                'String operationName',
                'String directives',
                'TFull Function(Map<String, dynamic> json) fromJson',
                'bool captureErrors',
              ],
              statements: [
                _client.codeGenUtils.constDecl(svResponseMap, '<String, dynamic>{}'),
                _client.codeGenUtils.constDecl(svStaleData, '<String, dynamic>{}'),
                _client.codeGenUtils.constDecl(svCacheFetchFutures, '<Future>[]'),
                _client.codeGenUtils.forEachLoop(
                    variable: "partQuery",
                    iterable: "partialQueries.where((e) => e.ttl > 0)",
                    statements: [
                      "$svCacheFetchFutures.add(getFromCache(partQuery.cacheKey!, partQuery.tags, partQuery.staleIfOffline)",
                      ".asStream().where((e) => e != null).map((e) => e!).first.then((entry) ${_client.codeGenUtils.block([
                            _client.codeGenUtils.ifStatement(
                                condition: 'entry.stale',
                                ifBlockStatements: [
                                  '$svStaleData[partQuery.elementKey] = jsonDecode(entry.data);'
                                ],
                                elseBlockStatements: [
                                  '$svResponseMap[partQuery.elementKey] = jsonDecode(entry.data);'
                                ])
                          ])}));"
                    ]),
                'await Future.wait($svCacheFetchFutures.map((f) => f.catchError((_) => null)));',
                'var $svRemaining = partialQueries.where((e) => !$svResponseMap.containsKey(e.elementKey)).toSet();',
                _client.codeGenUtils.ifStatement(
                    condition: '$svRemaining.isEmpty',
                    ifBlockStatements: [
                      "return fromJson({'data': $svResponseMap});"
                    ]),
                _client.codeGenUtils.constDecl(svRemainingQueries, "partialQueries.where((e) => !$svResponseMap.containsKey(e.elementKey)).toList()"),
                _client.codeGenUtils.constDecl(svPayload, _client.codeGenUtils.callExpression("_buildPayload", ["$svRemainingQueries", "operationName", "directives"])),
                _client.codeGenUtils.tryCatchFinally(tryStatements: [
                  _client.codeGenUtils.constDecl(svResponseText, 'await glCallAdapter($svPayload)'),
                  'return ${_client.codeGenUtils.callExpression('_parseToObjectAndCache', ['$svResponseText', '$svResponseMap', 'fromJson', '$svRemaining', 'captureErrors'])};',
                ], catchStatements: [
                  "$svResponseMap.addAll($svStaleData);",
                  _client.codeGenUtils.constDecl('remainingCount', 'partialQueries.where((e) => !$svResponseMap.containsKey(e.elementKey)).length'),
                  _client.codeGenUtils.ifStatement(
                      condition: 'remainingCount > 0',
                      ifBlockStatements: ["rethrow;"]),
                  "return fromJson({'data': $svResponseMap});",
                ], catchVariable: 'exception'),
              ]),
          _client.codeGenUtils.createMethod(
              returnType: "GraphLinkPayload",
              namedArguments: false,
              methodName: "_buildPayload",
              arguments: [
                "List<GraphLinkPartialQuery> partQueries",
                "String operationName",
                "String directives"
              ],
              statements: [
                _client.codeGenUtils.constDecl("variables", "{}", type: "Map<String, dynamic>"),
                _client.codeGenUtils.forEachLoop(
                    variable: "partQuery",
                    iterable: "partQueries",
                    statements: ["variables.addAll(partQuery.variables);"]),
                _client.codeGenUtils.constDecl('queryBuilder', 'StringBuffer("query \${operationName}")'),
                _client.codeGenUtils.constDecl('args', 'partQueries.expand((e) => e.argumentDeclarations).toSet()'),
                _client.codeGenUtils.ifStatement(
                    condition: 'args.isNotEmpty',
                    ifBlockStatements: [
                      'queryBuilder.write("(");',
                      'queryBuilder.writeAll(args, ", ");',
                      'queryBuilder.write(")");'
                    ]),
                _client.codeGenUtils.ifStatement(
                    condition: 'directives.isNotEmpty',
                    ifBlockStatements: ['queryBuilder.write(directives);']),
                'queryBuilder.write("{");',
                _client.codeGenUtils.forEachLoop(
                    variable: 'partQuery',
                    iterable: 'partQueries',
                    statements: [
                      'queryBuilder.write(partQuery.query);',
                      'queryBuilder.write(" ");',
                    ]),
                'queryBuilder.write("}");',
                _client.codeGenUtils.constDecl('fragments', 'partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => $svFragMap[fragName]!).join()'),
                'queryBuilder.write(fragments);',
                'return ${_client.codeGenUtils.callExpression('GraphLinkPayload', ['query: queryBuilder.toString()', 'operationName: operationName', 'variables: variables'])};',
              ]),
          _client.codeGenUtils.createMethod(
              methodName:
                  '_parseToObjectAndCache<T extends GraphLinkFullResponse>',
              arguments: [
                'String data',
                'Map<String, dynamic> cachedResponse',
                'T Function(Map<String, dynamic> json) parser',
                'Set<GraphLinkPartialQuery> remainingQueries',
                'bool captureErrors',
              ],
              returnType: 'T',
              namedArguments: false,
              statements: [
                _client.codeGenUtils.constDecl('result', 'jsonDecode(data) as Map<String, dynamic>'),
                _client.codeGenUtils.constDecl('rawData', 'result["data"]'),
                _client.codeGenUtils.constDecl('dataMap', 'rawData as Map<String, dynamic>? ?? <String, dynamic>{}'),
                _client.codeGenUtils.forEachLoop(
                    variable: 'q',
                    iterable: 'remainingQueries',
                    statements: [
                      _client.codeGenUtils.ifStatement(
                          condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
                          ifBlockStatements: [
                            _client.codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry(jsonEncode(dataMap[q.elementKey]), DateTime.now().millisecondsSinceEpoch + q.ttl * 1000)'),
                            '$svStore.set(q.cacheKey!, jsonEncode(entry.toJson()));',
                            _client.codeGenUtils.ifStatement(
                                condition: 'q.tags.isNotEmpty',
                                ifBlockStatements: [
                                  'addKeyToTags(q.cacheKey!, q.tags);',
                                ]),
                          ])
                    ]),
                'dataMap.addAll(cachedResponse);',
                _client.codeGenUtils.constDecl("fullResponse", "<String, dynamic>{'data': rawData != null ? dataMap : null}"),
                _client.codeGenUtils.ifStatement(
                    condition: 'result["errors"] is List && (result["errors"] as List).isNotEmpty',
                    ifBlockStatements: [
                      'fullResponse["errors"] = result["errors"];',
                    ]),
                _client.codeGenUtils.constDecl('parsed', 'parser.call(fullResponse)'),
                _client.codeGenUtils.ifStatement(
                    condition: 'captureErrors',
                    ifBlockStatements: ['return parsed;']),
                _client.codeGenUtils.constDecl('errors', 'result["errors"] as List?'),
                _client.codeGenUtils.ifStatement(
                    condition: 'errors != null && errors.isNotEmpty',
                    ifBlockStatements: ['throw parsed.errors!;']),
                'return parsed;',
              ]),
          _client.codeGenUtils.createMethod(
              methodName: "getFromCache",
              async: true,
              namedArguments: false,
              arguments: [
                'String key',
                'List<String> tags',
                'bool staleIfOffline'
              ],
              returnType: 'Future<GraphLinkCacheEntry?>',
              statements: [
                'var result = await $svStore.get(key);',
                _client.codeGenUtils
                    .ifStatement(condition: 'result != null', ifBlockStatements: [
                  'var entryMap = jsonDecode(result);',
                  'var entry = GraphLinkCacheEntry.fromJson(entryMap);',
                  _client.codeGenUtils.ifStatement(
                      condition: 'entry.isExpired',
                      ifBlockStatements: [
                        _client.codeGenUtils.ifStatement(
                            condition: 'staleIfOffline',
                            ifBlockStatements: ['return entry.asStale();']),
                        '$svStore.invalidate(key);',
                        _client.codeGenUtils.ifStatement(
                            condition: 'tags.isNotEmpty',
                            ifBlockStatements: ['_removeKeyFromTags(key, tags);']),
                        'return null;',
                      ],
                      elseBlockStatements: ['return entry;']),
                ]),
                'return null;'
              ]),
          _client.codeGenUtils.createMethod(
              methodName: "invalidateByTags",
              namedArguments: false,
              arguments: ["List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                _client.codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      _client.codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      _client.codeGenUtils.constDecl('lock', '$svTagLocks[tag]!'),
                      'await lock.synchronized(() async',
                      _client.codeGenUtils.block([
                        _client.codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        _client.codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              _client.codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
                              _client.codeGenUtils.forEachLoop(
                                  variable: 'key',
                                  iterable: 'entry.keys',
                                  statements: ['await $svStore.invalidate(key);']),
                              'await $svStore.invalidate(tagKey);'
                            ]),
                      ]),
                      ');'
                    ])
              ]),
          _client.codeGenUtils.createMethod(
              methodName: "addKeyToTags",
              namedArguments: false,
              arguments: ["String key", "List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                _client.codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      _client.codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      _client.codeGenUtils.constDecl('lock', '$svTagLocks[tag]!'),
                      'await lock.synchronized(() async',
                      _client.codeGenUtils.block([
                        _client.codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        _client.codeGenUtils.constDecl('entry', 'data != null ? GraphLinkTagEntry.decode(data) : GraphLinkTagEntry({})'),
                        'entry.add(key);',
                        'await $svStore.set(tagKey, entry.encode());'
                      ]),
                      ');'
                    ])
              ]),
          _client.codeGenUtils.createMethod(
              methodName: "_removeKeyFromTags",
              namedArguments: false,
              arguments: ["String key", "List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                _client.codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      _client.codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      _client.codeGenUtils.constDecl('lock', '$svTagLocks.putIfAbsent(tag, () => GraphLinkLock())'),
                      'await lock.synchronized(() async',
                      _client.codeGenUtils.block([
                        _client.codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        _client.codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              _client.codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
                              'entry.remove(key);',
                              _client.codeGenUtils.ifStatement(
                                  condition: 'entry.keys.isEmpty',
                                  ifBlockStatements: [
                                    'await $svStore.invalidate(tagKey);'
                                  ],
                                  elseBlockStatements: [
                                    'await $svStore.set(tagKey, entry.encode());'
                                  ])
                            ]),
                      ]),
                      ');'
                    ])
              ]),
        ]);
  }

  GLClassModel generateHandshakeStatusFile() =>
      const GLClassModel(body: handshakeStatus);

  GLClassModel generateStreamSinkFile() =>
      const GLClassModel(imports: ["import 'dart:async';"], body: dartStreamSink);

  GLClassModel generateWsAdapterFile() =>
      const GLClassModel(imports: ["import 'dart:async';"], body: webSocketAdapter);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: dartGraphqlMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() {
    final payloadImport = _client.serializer.serializeImportToken(
        _client.parser.getTokenByKey('GraphLinkPayload')!);
    final imports = <String>[
      "import 'dart:async';",
      "import 'dart:convert';",
      "import 'dart:math';",
      if (payloadImport.isNotEmpty) payloadImport,
      "import 'graph_link_handshake_status.dart';",
      "import 'graph_link_stream_sink.dart';",
      "import 'graph_link_websocket_adapter.dart';",
      "import 'graph_link_ws_message_types.dart';",
    ];
    // include schema token imports for subscription message types
    for (final name in [
      'GraphLinkSubscriptionPayload',
      'GraphLinkSubscriptionMessage',
      'GraphLinkSubscriptionErrorMessageBase',
      'GraphLinkSubscriptionErrorMessage',
      'GraphqlWsMessageTypes',
    ]) {
      final token = _client.parser.getTokenByKey(name);
      if (token != null) {
        final imp = _client.serializer.serializeImportToken(token);
        if (imp.isNotEmpty) imports.add(imp);
      }
    }
    return GLClassModel(imports: imports, body: subscriptionHandler);
  }

  // ── Adapter / upload file generators ──────────────────────────────────────

  GLClassModel generateUploadConverterFile() => const GLClassModel(
        imports: ["import 'graph_link_uploads.dart';"],
        body: dartUploadDefaultConverter,
      );

  GLClassModel generateRestResolverFile() {
    return const GLClassModel(
      imports: [
        "import 'dart:convert';",
        "import 'graph_link_cache_entry.dart';",
        "import 'graph_link_partial_query.dart';",
        "import 'graph_link_resolver_base.dart';",
        "import 'graph_link_rest.dart';",
      ],
      body: dartRestResolver,
    );
  }

  GLClassModel generateRestFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:convert';",
          "import 'dart:typed_data';",
          "import 'graph_link_uploads.dart';",
        ],
        body: dartRestFile,
      );

  GLClassModel generateDefaultWebSocketAdapterFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:math';",
          "import 'package:web_socket_channel/web_socket_channel.dart';",
          "import 'graph_link_websocket_adapter.dart';",
        ],
        body: defaultWebSocketAdapter,
      );
}
