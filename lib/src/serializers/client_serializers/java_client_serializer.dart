import 'package:graphlink/src/cache_store_java.dart';
import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/gl_client_serilaizer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';

const clientName = 'GraphLinkClient';
const clientExceptionName = 'GraphLinkException';
const clientExceptionNameRef = clientExceptionName;
const _subscriptionListenerName = 'GraphLinkSubscriptionListener';
const _subscriptionListenerRef = _subscriptionListenerName;

class JavaClientSerializer extends GLClientSerilaizer {
  final GLParser _grammar;
  final codeGenUtils = JavaCodeGenUtils();

  final GLGraphqSerializer gqlSerializer;

  JavaClientSerializer(this._grammar, GLSerializer serializer)
      : gqlSerializer = GLGraphqSerializer(_grammar, false),
        super(serializer);

  @override
  String generateClient(String importPrefix) {
    var imports = serializeImports(_grammar, importPrefix);

    var buffer = StringBuffer();
    for (var i in [
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.objects,
    ]) {
      buffer.writeln('import ${i};');
    }
    buffer.writeln(imports);

    buffer.writeln(codeGenUtils.createClass(className: clientName, statements: [
      'final Map<String, String> _fragmMap = new HashMap<>();',
      if (_grammar.hasQueries)
        'public final ${classNameFromType(GLQueryType.query)} queries;',
      if (_grammar.hasMutations)
        'public final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_grammar.hasSubscriptions)
        'public final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      codeGenUtils.createMethod(
        methodName: clientName,
        returnType: 'public',
        statements: [
          if (_grammar.hasSubscriptions)
            'this(adapter, encoder, decoder, null, wsAdapter);'
          else
            'this(adapter, encoder, decoder, null);',
        ],
        arguments: [
          _adapterDeclaration(false),
          if (_grammar.hasSubscriptions)
            'GraphLinkGraphLinkWebSocketAdapter wsAdapter'
        ],
      ),
      codeGenUtils.createMethod(
        returnType: "public",
        methodName: clientName,
        arguments: [
          _adapterDeclaration(true),
          if (_grammar.hasSubscriptions)
            'GraphLinkGraphLinkWebSocketAdapter wsAdapter'
        ],
        statements: [
          codeGenUtils.ifStatement(
            condition: 'store == null',
            ifBlockStatements: ['store = new InMemoryGraphLinkCacheStore();'],
          ),
          "Objects.requireNonNull(adapter);",
          "Objects.requireNonNull(encoder);",
          "Objects.requireNonNull(decoder);",
          if (_grammar.hasSubscriptions) "Objects.requireNonNull(wsAdapter);",
          if (_grammar.hasQueries)
            "queries = new ${classNameFromType(GLQueryType.query)}(adapter, _fragmMap, encoder, decoder, store);",
          if (_grammar.hasMutations)
            "mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, _fragmMap, encoder, decoder, store);",
          if (_grammar.hasSubscriptions)
            "subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, _fragmMap, encoder, decoder, store);",
          ..._grammar.fragments.values.map((value) =>
              '_fragmMap.put("${value.tokenInfo}", "${gqlSerializer.serializeFragmentDefinitionBase(value)}");'),
        ],
      ),
    ]));

    buffer.writeln(serializeSubscriptions().ident());
    return buffer.toString();
  }

  String _adapterDeclaration(bool withStore) {
    return [
      'GraphLinkClientAdapter adapter',
      'GraphLinkJsonEncoder encoder',
      'GraphLinkJsonDecoder decoder',
      if (withStore) 'GraphLinkCacheStore store',
    ].join(", ");
  }

  String? generateQueriesClassByType(GLQueryType type) {
    var queries = _grammar.queries.values;
    var queryList = queries
        .where((element) => element.type == type && _grammar.hasQueryType(type))
        .toList();
    if (queryList.isEmpty) {
      return null;
    }

    return codeGenUtils.createClass(
        staticClass: false,
        className: "${classNameFromType(type)} extends ResolverBase",
        statements: [
          ...declareAdapter(type),
          codeGenUtils.createMethod(
              returnType: 'public',
              methodName: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              statements: [
                'super(fragmentMap, store, encoder, decoder);',
                'this.adapter = adapter;',
                if (type == GLQueryType.subscription)
                  '_handler = new SubscriptionHandler(adapter, decoder, encoder);',
              ]),
          ...queryList
              .where((e) =>
                  e.type == GLQueryType.query ||
                  e.type == GLQueryType.subscription)
              .map(queryToMethod),
          ...queryList
              .where((e) => e.type == GLQueryType.mutation)
              .map(mutationToMethod),
          if (type == GLQueryType.query)
            codeGenUtils.createMethod(
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
                      'fragmentsBuilder.append(fragmentMap.get(fragName));',
                    ]),
                'queryBuilder.append(fragmentsBuilder);',
                'return GraphLinkPayload.builder().query(queryBuilder.toString()).operationName(operationName).variables(variables).build();',
              ],
            ),
        ]);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      if (type == GLQueryType.subscription)
        'GraphLinkGraphLinkWebSocketAdapter adapter'
      else
        'GraphLinkClientAdapter adapter',
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
        return ["private final GraphLinkClientAdapter adapter;"];
      case GLQueryType.subscription:
        return [
          "private final SubscriptionHandler _handler;",
          "private final GraphLinkGraphLinkWebSocketAdapter adapter;"
        ];
    }
  }

  String queryToMethod(GLQueryDefinition def) {
    final dividedQueries = gqlSerializer.divideQueryDefinition(def, _grammar);
    final directives = gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final returnType = def.getGeneratedTypeDefinition().tokenInfo.token;

    return codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String operationName = "${def.tokenInfo}";',
          generateVariables(def),
          'List<GraphLinkPartialQuery> partialQueries = new ArrayList<>();',
          ...dividedQueries.map(serializePartialQueryJava),
          'Map<String, Object> responseMap = new HashMap<>();',
          'Map<String, Object> staleData = new HashMap<>();',
          codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: 'partialQueries',
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
                                    'staleData.put(partQuery.elementKey, decoder.decode(entry.data));'
                                  ],
                                  elseBlockStatements: [
                                    'responseMap.put(partQuery.elementKey, decoder.decode(entry.data));'
                                  ],
                                ),
                              ]),
                        ],
                        catchStatements: [],
                        catchVariable: 'ignored',
                      ),
                    ]),
              ]),
          'List<GraphLinkPartialQuery> remaining = new ArrayList<>();',
          codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: 'partialQueries',
              statements: [
                codeGenUtils.ifStatement(
                    condition: '!responseMap.containsKey(partQuery.elementKey)',
                    ifBlockStatements: [
                      'remaining.add(partQuery);',
                    ]),
              ]),
          codeGenUtils.ifStatement(
              condition: 'remaining.isEmpty()',
              ifBlockStatements: [
                'return $returnType.fromJson(responseMap);',
              ]),
          'GraphLinkPayload payload = buildPayload(remaining, operationName, "$directives");',
          codeGenUtils.tryCatchFinally(
            tryStatements: [
              'String responseText = adapter.execute(encoder.encode(payload));',
              'return parseToObjectAndCache(responseText, responseMap, $returnType::fromJson, remaining);',
            ],
            catchStatements: [
              'responseMap.putAll(staleData);',
              'long remainingCount = partialQueries.stream().filter(e -> !responseMap.containsKey(e.elementKey)).count();',
              codeGenUtils.ifStatement(
                  condition: 'remainingCount > 0',
                  ifBlockStatements: [
                    'if (exception instanceof RuntimeException) throw (RuntimeException) exception;',
                    'throw new RuntimeException(exception);',
                  ]),
              'return $returnType.fromJson(responseMap);',
            ],
            catchVariable: 'exception',
          ),
        ]);
  }

  String serializePartialQueryJava(DividedQuery e) {
    final tagsStr = e.tags.isEmpty
        ? 'new ArrayList<>()'
        : 'Arrays.asList(${e.tags.map((t) => '"$t"').join(', ')})';
    final fragNamesStr = e.fragmentNames.isEmpty
        ? 'new HashSet<>()'
        : 'new HashSet<>(Arrays.asList(${e.fragmentNames.map((f) => '"$f"').join(', ')}))';
    final argDeclsStr = e.argumentDeclarations.isEmpty
        ? 'new ArrayList<>()'
        : 'Arrays.asList(${e.argumentDeclarations.map((a) => '"$a"').join(', ')})';
    final queryStr = e.query.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  Map<String, Object> pqVars = new HashMap<>();');
    for (var v in e.variables) {
      final argName = v.substring(1);
      buffer.writeln('  pqVars.put("$argName", variables.get("$argName"));');
    }
    buffer.writeln('  partialQueries.add(new GraphLinkPartialQuery(');
    buffer.writeln('    "$queryStr",');
    buffer.writeln('    pqVars,');
    buffer.writeln('    ${e.cacheTTL},');
    buffer.writeln('    $tagsStr,');
    buffer.writeln('    "${e.operationName}",');
    buffer.writeln('    "${e.elementKey}",');
    buffer.writeln('    $fragNamesStr,');
    buffer.writeln('    $argDeclsStr,');
    buffer.writeln('    ${e.staleIfOffline},');
    buffer.writeln('    encoder');
    buffer.writeln('  ));');
    buffer.write('}');
    return buffer.toString();
  }

  String mutationToMethod(GLQueryDefinition def) {
    final frags = def.fragments(_grammar);
    return codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String operationName = "${def.tokenInfo}";',
          if (frags.isNotEmpty) ...[
            'List<String> fragsValues = Arrays.asList(${frags.map((e) => 'fragmentMap.get("${e.token}")').join(", ")});',
            'String query = "${gqlSerializer.serializeQueryDefinition(def)} " + String.join(" ", fragsValues);',
          ] else
            'String query = "${gqlSerializer.serializeQueryDefinition(def)}";',
          generateVariables(def),
          "GraphLinkPayload payload = GraphLinkPayload.builder().query(query).operationName(operationName).variables(variables).build();",
          _serializeAdapterCall(def)
        ]);
  }

  String generateVariables(GLQueryDefinition def) {
    var buffer =
        StringBuffer("Map<String, Object> variables = new HashMap<>();");
    buffer.writeln();
    def.arguments
        .map((e) =>
            'variables.put("${e.dartArgumentName}", ${_serializeArgumentValue(def, e.token)});')
        .forEach(buffer.writeln);

    return buffer.toString();
  }

  String _serializeAdapterCall(GLQueryDefinition def) {
    switch (def.type) {
      case GLQueryType.query:
        return _serializeQueryAdapterCall(def);
      case GLQueryType.mutation:
        return _serializeMutationAdapterCall(def);
      case GLQueryType.subscription:
        return _serializeSubscriptionAdapterCall(def);
    }
  }

  String _serializeQueryAdapterCall(GLQueryDefinition def) {
    return [
      "String encodedPayload = encoder.encode(payload);",
      "String responseText = adapter.execute(encodedPayload);",
      "Map<String, Object> decodedResponse = decoder.decode(responseText);",
      codeGenUtils.ifStatement(
          condition: 'decodedResponse.containsKey("errors")',
          ifBlockStatements: [
            'throw ${clientExceptionName}.of((List)decodedResponse.get("errors"));'
          ],
          elseBlockStatements: [
            'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson((Map<String, Object>)decodedResponse.get("data"));'
          ])
    ].join("\n");
  }

  String _serializeMutationAdapterCall(GLQueryDefinition def) {
    return [
      "String encodedPayload = encoder.encode(payload);",
      "String responseText = adapter.execute(encodedPayload);",
      "Map<String, Object> decodedResponse = decoder.decode(responseText);",
      codeGenUtils.ifStatement(
          condition: 'decodedResponse.containsKey("errors")',
          ifBlockStatements: [
            'throw ${clientExceptionName}.of((List)decodedResponse.get("errors"));',
          ]),
      'Map<String, Object> data = (Map<String, Object>) decodedResponse.get("data");',
      _serializeInvalidationCall(def),
      'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson(data);',
    ].join("\n");
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return 'store.invalidateAll();';
      }
    }
    final tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'invalidateByTags(Arrays.asList(${tags.map((e) => '"$e"').join(', ')}));';
    }
    return '// no tag to invalidate';
  }

  String _serializeSubscriptionAdapterCall(GLQueryDefinition def) {
    var method = codeGenUtils.createMethod(
        methodName:
            '${_subscriptionListenerRef}<Map<String, Object>> rawListener = new ${_subscriptionListenerRef}<Map<String, Object>>',
        statements: [
          '@Override',
          codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onMessage',
            arguments: ['Map<String, Object> response'],
            statements: [
              'listener.onMessage(${def.typeDefinition?.token}.fromJson(response));'
            ],
          ),
          '@Override',
          codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onComplete',
            arguments: [],
            statements: ['listener.onComplete();'],
          ),
          '@Override',
          codeGenUtils.createMethod(
            returnType: 'public void',
            methodName: 'onError',
            arguments: ['${clientExceptionNameRef} error'],
            statements: ['listener.onError(error);'],
          )
        ]);
    return ['${method};', '_handler.handlePayload(payload, rawListener);']
        .join('\n');
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GLType type) {
    if (_grammar.inputTypeRequiresProjection(type)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    }
    if (_grammar.isEnum(type.token)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    } else {
      return argName;
    }
  }

  String _getNullableText(GLType type) {
    if (type.nullable) {
      return "?";
    }
    return "";
  }

  List<String> getArguments(GLQueryDefinition def) {
    List<String> result;
    if (def.arguments.isEmpty) {
      result = [];
    }
    result = def.arguments
        .map((e) =>
            "${serializer.serializeType(e.type, false)} ${e.dartArgumentName}")
        .toList();
    if (def.type == GLQueryType.subscription) {
      result.add(
          '${_subscriptionListenerRef}<${def.typeDefinition?.token}> listener');
    }
    return result;
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GLQueryType.subscription) {
      return "void";
    }
    return gen.tokenInfo.token;
  }

  String serializeSubscriptions() {
    return "";
  }

  String generateResolverBaseFile(String importPrefix) {
    final buffer = StringBuffer();
    for (var i in [
      JavaImports.map,
      JavaImports.list,
      JavaImports.hashMap,
      JavaImports.hashSet,
      JavaImports.reentrantLock,
      JavaImports.function,
    ]) {
      buffer.writeln('import $i;');
    }
    buffer.writeln(serializeImports(_grammar, importPrefix));

    final allTags = _grammar.getAllCacheTags();

    buffer.writeln(codeGenUtils.createClass(
      className: 'ResolverBase',
      statements: [
        'protected final Map<String, String> fragmentMap;',
        'protected final GraphLinkCacheStore store;',
        'protected final GraphLinkJsonEncoder encoder;',
        'protected final GraphLinkJsonDecoder decoder;',
        'private final Map<String, ReentrantLock> tagLocks = new HashMap<>();',
        codeGenUtils.createMethod(
          methodName: 'ResolverBase',
          arguments: [
            'Map<String, String> fragmentMap',
            'GraphLinkCacheStore store',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: [
            'this.fragmentMap = fragmentMap;',
            'this.store = store;',
            'this.encoder = encoder;',
            'this.decoder = decoder;',
            'String[] tags = {${allTags.map((t) => '"$t"').join(', ')}};',
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'tagLocks.put(tag, new ReentrantLock());',
            ]),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T> T',
          methodName: 'parseToObjectAndCache',
          arguments: [
            'String data',
            'Map<String, Object> cachedResponse',
            'Function<Map<String, Object>, T> parser',
            'List<GraphLinkPartialQuery> remainingQueries',
          ],
          statements: [
            'Map<String, Object> result = decoder.decode(data);',
            codeGenUtils.ifStatement(
                condition: 'result.containsKey("errors")',
                ifBlockStatements: [
                  'throw ${clientExceptionName}.of((List) result.get("errors"));',
                ]),
            'Map<String, Object> dataMap = (Map<String, Object>) result.get("data");',
            codeGenUtils.forEachLoop(
                variable: 'q',
                iterable: 'remainingQueries',
                statements: [
                  codeGenUtils.ifStatement(
                      condition:
                          'q.ttl > 0 && dataMap.get(q.elementKey) != null',
                      ifBlockStatements: [
                        'GraphLinkCacheEntry entry = new GraphLinkCacheEntry(encoder.encode(dataMap.get(q.elementKey)), System.currentTimeMillis() + q.ttl * 1000L);',
                        'store.set(q.cacheKey, encoder.encode(entry.toJson()));',
                        codeGenUtils.ifStatement(
                            condition: '!q.tags.isEmpty()',
                            ifBlockStatements: [
                              'addKeyToTags(q.cacheKey, q.tags);',
                            ]),
                      ]),
                ]),
            'dataMap.putAll(cachedResponse);',
            'return parser.apply(dataMap);',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'private String',
          methodName: 'tagKey',
          arguments: ['String tag'],
          statements: ['return "__tag__" + tag;'],
        ),
        codeGenUtils.createMethod(
          returnType: 'GraphLinkCacheEntry',
          methodName: 'getFromCache',
          arguments: [
            'String key',
            'List<String> tags',
            'boolean staleIfOffline'
          ],
          statements: [
            'String result = store.get(key);',
            codeGenUtils
                .ifStatement(condition: 'result != null', ifBlockStatements: [
              'Map<String, Object> entryMap = decoder.decode(result);',
              'GraphLinkCacheEntry entry = GraphLinkCacheEntry.fromJson(entryMap);',
              codeGenUtils.ifStatement(
                  condition: 'entry.isExpired()',
                  ifBlockStatements: [
                    codeGenUtils.ifStatement(
                        condition: 'staleIfOffline',
                        ifBlockStatements: ['return entry.asStale();']),
                    'store.invalidate(key);',
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
              'ReentrantLock lock = tagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = store.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson(decoder.decode(data));',
                  codeGenUtils.forEachLoop(
                      variable: 'k',
                      iterable: 'entry.keys',
                      statements: ['store.invalidate(k);']),
                  'store.invalidate(tKey);',
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
              'ReentrantLock lock = tagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = store.get(tKey);',
                'GraphLinkTagEntry entry = data != null ? GraphLinkTagEntry.fromJson(decoder.decode(data)) : new GraphLinkTagEntry(new HashSet<>());',
                'entry.add(key);',
                'store.set(tKey, encoder.encode(entry.toJson()));',
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
              'ReentrantLock lock = tagLocks.computeIfAbsent(tag, k -> new ReentrantLock());',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = store.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson(decoder.decode(data));',
                  'entry.remove(key);',
                  codeGenUtils.ifStatement(
                    condition: 'entry.keys.isEmpty()',
                    ifBlockStatements: ['store.invalidate(tKey);'],
                    elseBlockStatements: [
                      'store.set(tKey, encoder.encode(entry.toJson()));'
                    ],
                  ),
                ]),
              ], finallyStatements: [
                'lock.unlock();',
              ]),
            ]),
          ],
        ),
      ],
    ));
    return buffer.toString();
  }

  String? generateQueriesClassFile(GLQueryType type, String importPrefix) {
    final classBody = generateQueriesClassByType(type);
    if (classBody == null) return null;
    final buffer = StringBuffer();
    for (var i in [
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.list,
      JavaImports.arrayList,
      JavaImports.arrays,
      if (type == GLQueryType.query) ...[
        JavaImports.set,
        JavaImports.hashSet,
      ],
      if (type == GLQueryType.subscription) ...[
        JavaImports.uuid,
      ],
    ]) {
      buffer.writeln('import $i;');
    }
    buffer.writeln(serializeImports(_grammar, importPrefix));
    buffer.writeln(classBody);
    return buffer.toString();
  }

  String generateGraphLinkCacheEntryFile() {
    return '${[
      'import ${JavaImports.map};',
      'import ${JavaImports.hashMap};'
    ].join('\n')}\n\n${cacheEntry.trim()}';
  }

  String generateGraphLinkTagEntryFile() {
    return '${[
      'import ${JavaImports.map};',
      'import ${JavaImports.hashMap};',
      'import ${JavaImports.set};',
      'import ${JavaImports.hashSet};',
      'import ${JavaImports.list};',
      'import ${JavaImports.arrayList};'
    ].join('\n')}\n\n${tagEntry.trim()}';
  }

  String generateGraphLinkPartialQueryFile(String importPrefix) {
    return '${[
      'import ${JavaImports.map};',
      'import ${JavaImports.hashMap};',
      'import ${JavaImports.list};',
      'import ${JavaImports.set};',
      'import ${JavaImports.treeMap};',
    ].join('\n')}\n${serializeImports(_grammar, importPrefix)}\n${partialQuery.trim()}';
  }

  String generateGraphLinkCacheStoreFile() {
    return graphLinkCacheStore.trim();
  }

  String generateInMemoryGraphLinkCacheStoreFile() {
    return 'import ${JavaImports.concurrentHashMap};\n\n${inMemoryGraphLinkCacheStore.trim()}';
  }

  String generateSubscriptionListenerFile() {
    return _gqSubscriptionListener.trim();
  }

  String generateGraphqlWsMessageTypesFile() {
    return _graphqlWsMessageTypesClass.trim();
  }

  String generateSubscriptionHandlerFile(String importPrefix) {
    final buffer = StringBuffer();
    for (var i in [
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.list,
      JavaImports.arrayList,
      JavaImports.uuid,
    ]) {
      buffer.writeln('import $i;');
    }
    buffer.writeln(serializeImports(_grammar, importPrefix));
    buffer.writeln(serializer.serializeImportToken(
        _grammar.enums['GraphLinkAckStatus']!, importPrefix));
    buffer.writeln(_subscriptionHandlerClass.trim());
    return buffer.toString();
  }

  String get exceptionFileName => '$clientExceptionName.java';

  String generateGraphLinkExceptionFile(String importPrefix) {
    final buffer = StringBuffer();
    for (var i in [
      JavaImports.list,
      JavaImports.collections,
      JavaImports.collectors,
      JavaImports.map
    ]) {
      buffer.writeln('import $i;');
    }
    final errorToken = _grammar.getTokenByKey('GraphLinkError');
    if (errorToken != null) {
      buffer.writeln(serializer.serializeImportToken(errorToken, importPrefix));
    }
    buffer.writeln();
    buffer.writeln(codeGenUtils.createClass(
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
            arguments: [
              'Exception ex',
            ],
            statements: [
              'super(ex);',
              'errors = Collections.emptyList();'
            ]),
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
              'return new $clientExceptionName(errors.stream().map(e -> GraphLinkError.fromJson((Map<String, Object>)e)).collect(Collectors.toList()));'
            ]),
      ],
    ));
    return buffer.toString();
  }

  String get fileExtension => '.java';

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    result.addAll([
      'GraphLinkJsonEncoder',
      'GraphLinkJsonDecoder',
      'GraphLinkClientAdapter'
    ].map((e) => g.getTypeByName(e)!));
    var adapter = g.getTokenByKey('GraphLinkGraphLinkWebSocketAdapter');
    if (adapter != null) {
      result.add(adapter);
    }
    return result;
  }
}

const _gqSubscriptionListener = '''
public interface ${_subscriptionListenerName}<T> {
  void onMessage(T response) ;
  default void  onComplete(){}
  default void  onError(${clientExceptionNameRef} error) {}
}
''';

const _graphqlWsMessageTypesClass = '''
public class GraphqlWsMessageTypes {
  /// Client initializes connection.
  /// Example: { "type": "connection_init", "payload": { "authToken": "abc123" } }
  public static final String connectionInit = "connection_init";

  /// Server acknowledges connection.
  /// Example: { "type": "connection_ack" }
  public static final String connectionAck = "connection_ack";

  /// Client subscribes to an operation.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "subscribe",
  ///   "payload": { "query": "...", "variables": {} }
  /// }
  public static final String subscribe = "subscribe";

  /// Client or server pings for keep-alive.
  /// Example: { "type": "ping", "payload": {} }
  public static final String ping = "ping";

  /// Response to ping.
  /// Example: { "type": "pong" }
  public static final String pong = "pong";

  /// Server sends subscription data.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "next",
  ///   "payload": { "data": { "newMessage": { "id": "42", "content": "Hi" } } }
  /// }
  public static final String next = "next";

  /// Server sends a fatal error for a subscription.
  /// Example: { "id": "1", "type": "error", "payload": { "message": "Validation failed" } }
  public static final String error = "error";

  /// Client or server completes subscription.
  /// Example: { "id": "1", "type": "complete" }
  public static final String complete = "complete";
}
''';

const _subscriptionHandlerClass = '''
public class SubscriptionHandler {

  // we have to think about synchronization here
  private final Map<String, ${_subscriptionListenerRef}<Map<String, Object>>> listeners = new HashMap<>();
  private final Map<String, GraphLinkPayload> payloadsToHandle = new HashMap<>();

  private final GraphLinkGraphLinkWebSocketAdapter adapter;
  private final GraphLinkJsonDecoder decoder;
  private final GraphLinkJsonEncoder encoder;
  private GraphLinkAckStatus ackStatus = GraphLinkAckStatus.none;


  SubscriptionHandler(GraphLinkGraphLinkWebSocketAdapter adapter, GraphLinkJsonDecoder decoder, GraphLinkJsonEncoder encoder) {
    this.adapter = adapter;
    this.decoder = decoder;
    this.encoder = encoder;
    adapter.onMessage(this::onMessage);
  }

  String getConnectionInit(String id) {
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.connectionInit)
        .id(id)
        .build());
  }

  String getPongMessage(String id) {
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.pong)
        .id(id)
        .build());
  }

  String getSubscriptionMessage(String id) {
    GraphLinkPayload payload = payloadsToHandle.get(id);
    GraphLinkSubscriptionPayload subscriptionPayload = GraphLinkSubscriptionPayload.builder()
        .query(payload.getQuery())
        .operationName(payload.getOperationName())
        .variables(payload.getVariables())

        .build();
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.subscribe)
        .payload(subscriptionPayload)
        .id(id)
        .build());
  }


  public synchronized void initConnection(String id, GraphLinkPayload payload) {
    switch (ackStatus) {
      case none:
        addPayload(id, payload);
        ackStatus = GraphLinkAckStatus.progress;
        adapter.connect((obj) -> {
          String connectionInit = getConnectionInit(id);
          System.out.println("Sending connectionInit = " + connectionInit);
          adapter.sendMessage(connectionInit);
        }, (t) -> {
          System.out.println("Connection failed!");
        });
        //
        break;
      case progress:
        System.out.println("in progress ....");
        addPayload(id, payload);
        break;
      case acknoledged:
        adapter.sendMessage(getSubscriptionMessage(id));
        break;
    }
  }

  private void addPayload(String id, GraphLinkPayload payload) {
    synchronized (payloadsToHandle) {
      payloadsToHandle.put(id, payload);
    }
  }

  GraphLinkPayload getPayload(String id) {
    return payloadsToHandle.get(id);
  }


  private GraphLinkSubscriptionErrorMessageBase parseEvent(String event) {
    Map<String, Object> map = decoder.decode(event);
    Object payload = map.get("payload");
    GraphLinkSubscriptionErrorMessageBase result;
    if (payload instanceof Map) {
      result = GraphLinkSubscriptionMessage.fromJson(map);
    } else {
      result = GraphLinkSubscriptionErrorMessage.fromJson(map);
    }
    return result;
  }


  public void handlePayload(GraphLinkPayload payload, ${_subscriptionListenerRef}<Map<String, Object>> listener) {
    String uuid = UUID.randomUUID().toString();
    synchronized (listeners) {
      listeners.put(uuid, listener);
    }
    initConnection(uuid, payload);
  }


  public void onMessage(String message) {
    GraphLinkSubscriptionErrorMessageBase event = parseEvent(message);
    String type = event.getType();
    switch (type) {
      case GraphqlWsMessageTypes.connectionAck:
        handleConnectionAck();
        break;
      case GraphqlWsMessageTypes.subscribe:
        System.out.println("handle subscription here " + event.getId());
        break;
      case GraphqlWsMessageTypes.ping:
        adapter.sendMessage(getPongMessage(event.getId()));
        break;
      case GraphqlWsMessageTypes.next:
        handleNextMessage((GraphLinkSubscriptionMessage) event);
        break;
      case GraphqlWsMessageTypes.error:
        System.out.println("Evenet class = "+ event.getClass());
        handleError((GraphLinkSubscriptionErrorMessage)event);
        break;
      case GraphqlWsMessageTypes.complete:
        handleComplete(event.getId());
        break;
    }
  }

  void handleError(GraphLinkSubscriptionErrorMessage error) {
    ${_subscriptionListenerRef}<Map<String, Object>> listener;
    synchronized (listeners) {
      listener = listeners.remove(error.getId());
    }

    if (listener != null) {
      listener.onError(new ${clientExceptionNameRef}(error.getPayload()));
    }
  }

  void handleComplete(String id) {
    ${_subscriptionListenerRef}<Map<String, Object>> removedListener;
    synchronized (listeners) {
      removedListener = listeners.remove(id);
    }
    if(removedListener != null) {
      removedListener.onComplete();
    }
  }

  synchronized void  handleConnectionAck() {
    this.ackStatus = GraphLinkAckStatus.acknoledged;
    List<String> handledPayloadIds = new ArrayList<>(payloadsToHandle.size());
    this.payloadsToHandle.forEach((uuid, payload) -> {
      adapter.sendMessage(getSubscriptionMessage(uuid));
      handledPayloadIds.add(uuid);
    });

    handledPayloadIds.forEach(payloadsToHandle::remove);

  }

  private void handleNextMessage(GraphLinkSubscriptionMessage message) {
    String id = message.getId();
    // no need for synchronization!
    ${_subscriptionListenerRef}<Map<String, Object>> listener = listeners.get(id);
    if (listener != null) {

      System.out.println(
          "Should call the lister here with data = " + message.getPayload().getData());
      listener.onMessage(message.getPayload().getData());
    }
  }


}
''';
