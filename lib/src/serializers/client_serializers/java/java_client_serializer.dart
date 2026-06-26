import 'package:graphlink/src/cache_store_java.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/serializers/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_context.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_operation_serializer.dart';




class JavaClientSerializer extends GLClientSerializer {
  final GLParser _grammar;
  final codeGenUtils = JavaCodeGenUtils();
  final JavaJsonCodec jsonCodec;

  late final JavaClientContext _ctx;
  late final JavaClientOperationSerializer _opSer;
  GLImportContainer? _activeContainer;

  JavaClientSerializer(this._grammar, GLSerializer serializer,
      {this.jsonCodec = JavaJsonCodec.jackson})
      : super(serializer, GLGraphqlSerializer(_grammar, false)) {
    _ctx = JavaClientContext(_grammar, codeGenUtils, gqlSerializer, serializer);
    _opSer = JavaClientOperationSerializer(_ctx);
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
            'this(adapter, ${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}encoder, decoder, null, wsAdapter);'
          else
            'this(adapter, ${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}encoder, decoder, null);',
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
          codeGenUtils.ifStatement(
            condition: 'store == null',
            ifBlockStatements: ['store = new InMemoryGraphLinkCacheStore();'],
          ),
          "Objects.requireNonNull(adapter);",
          "Objects.requireNonNull(encoder);",
          "Objects.requireNonNull(decoder);",
          if (_grammar.hasSubscriptions) "Objects.requireNonNull(wsAdapter);",
          if (_grammar.hasQueries)
            "queries = new ${classNameFromType(GLQueryType.query)}(adapter, $svFragmentMap, encoder, decoder, store);",
          if (_grammar.hasMutations)
            "mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, ${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}$svFragmentMap, encoder, decoder, store);",
          if (_grammar.hasSubscriptions)
            "subscriptions = new ${classNameFromType(GLQueryType.subscription)}(adapter, wsAdapter, $svFragmentMap, encoder, decoder, store);",
          ..._grammar.fragments.values.map((value) =>
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
              ...encoderDecoderArgs
            ],
            statements: ['this(adapter, adapter, encoder, decoder, null);'],
          ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url', ...encoderDecoderArgs],
          statements: _grammar.hasUploadMutations
              ? [
                  'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder);'
                ]
              : [
                  'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder, null);'
                ],
        ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: [
            'String url',
            'Supplier<Map<String, String>> headersProvider',
            ...encoderDecoderArgs
          ],
          statements: _grammar.hasUploadMutations
              ? [
                  'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder);'
                ]
              : [
                  'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder, null);'
                ],
        ),
        if (defaultCodec != null)
          codeGenUtils.createMethod(
            returnType: 'public',
            methodName: clientName,
            arguments: ['String url'],
            statements: ['this(url, $defaultCodec, $defaultCodec);'],
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
            ...encoderDecoderArgs,
            'GraphLinkWebSocketAdapter wsAdapter'
          ],
          statements: [
            'this(adapter, adapter, encoder, decoder, null, wsAdapter);'
          ],
        ),
      //Single URL, ws derived by replacing http→ws
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String url', ...encoderDecoderArgs],
        statements: _grammar.hasUploadMutations
            ? [
                'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder, new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws")));'
              ]
            : [
                'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder, null, new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws")));'
              ],
      ),
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: [
          'String url',
          'Supplier<Map<String, String>> headersProvider',
          ...encoderDecoderArgs
        ],
        statements: _grammar.hasUploadMutations
            ? [
                'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder, new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider));'
              ]
            : [
                'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder, null, new DefaultGraphLinkWebSocketAdapter(url.replaceFirst("http", "ws"), headersProvider));'
              ],
      ),
      // Option B — explicit wsUrl
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: ['String url', 'String wsUrl', ...encoderDecoderArgs],
        statements: _grammar.hasUploadMutations
            ? [
                'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder, new DefaultGraphLinkWebSocketAdapter(wsUrl));'
              ]
            : [
                'this(new DefaultGraphLinkClientAdapter(url), encoder, decoder, null, new DefaultGraphLinkWebSocketAdapter(wsUrl));'
              ],
      ),
      codeGenUtils.createMethod(
        returnType: 'public',
        methodName: clientName,
        arguments: [
          'String url',
          'String wsUrl',
          'Supplier<Map<String, String>> headersProvider',
          ...encoderDecoderArgs
        ],
        statements: _grammar.hasUploadMutations
            ? [
                'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder, new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider));'
              ]
            : [
                'this(new DefaultGraphLinkClientAdapter(url, headersProvider), encoder, decoder, null, new DefaultGraphLinkWebSocketAdapter(wsUrl, headersProvider));'
              ],
      ),
      if (defaultCodec != null) ...[
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url'],
          statements: ['this(url, $defaultCodec, $defaultCodec);'],
        ),
        codeGenUtils.createMethod(
          returnType: 'public',
          methodName: clientName,
          arguments: ['String url', 'String wsUrl'],
          statements: ['this(url, wsUrl, $defaultCodec, $defaultCodec);'],
        ),
      ],
    ];
  }

  String _adapterDeclaration(bool withStore) {
    return [
      'GraphLinkClientAdapter adapter',
      if (_grammar.hasUploadMutations)
        'GraphLinkMultipartAdapter multipartAdapter',
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

    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

    final classBody = codeGenUtils.createClass(
        staticClass: false,
        className: "${classNameFromType(type)} extends GraphLinkResolverBase",
        statements: [
          ...declareAdapter(type),
          codeGenUtils.createMethod(
              returnType: 'public',
              methodName: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              statements: [
                'super(adapter, fragmentMap, store, encoder, decoder);',
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
        ...importContainer.importDepencies
      }.toList(),
      imports: [...importContainer.imports],
      body: classBody,
    );
  }

  Set<GLToken> _getQueryImports(GLQueryType type) =>
      schemaTokensFor(type).toSet();

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      'GraphLinkClientAdapter adapter',
      if (type == GLQueryType.subscription)
        'GraphLinkWebSocketAdapter wsAdapter',
      if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
        'GraphLinkMultipartAdapter multipartAdapter',
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
        codeGenUtils.createMethod(
          methodName: 'GraphLinkResolverBase',
          arguments: [
            'GraphLinkClientAdapter adapter',
            'Map<String, String> fragmentMap',
            'GraphLinkCacheStore store',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: [
            'this.$svAdapter = adapter;'
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
          returnType: 'protected <T extends GraphLinkFullResponse> T',
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
            'String $svResponseText = glCallAdapter($svPayload);',
            'return fromJson.apply($svDecoder.decode($svResponseText));',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> T',
          methodName: 'executeData',
          arguments: [
            'String query',
            'Set<String> fragmentNames',
            'String operationName',
            'Map<String, Object> variables',
            'Function<Map<String, Object>, T> fromJson',
          ],
          statements: [
            'T $svDecodedResponse = executeFull(query, fragmentNames, operationName, variables, fromJson);',
            codeGenUtils.ifStatement(
                condition:
                    '$svDecodedResponse.getErrors() != null && !$svDecodedResponse.getErrors().isEmpty()',
                ifBlockStatements: [
                  'throw ${clientExceptionName}.of($svDecodedResponse.getErrors());',
                ]),
            'return $svDecodedResponse;',
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'protected <T extends GraphLinkFullResponse> T',
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
                  'return fromJson.apply($svWrappedResponse);',
                ]),
            'GraphLinkPayload $svPayload = buildPayload($svRemaining, operationName, directives);',
            codeGenUtils.tryCatchFinally(
              tryStatements: [
                'String $svResponseText = glCallAdapter($svPayload);',
                'return parseToObjectAndCache($svResponseText, $svResponseMap, fromJson, $svRemaining, captureErrors);',
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
        codeGenUtils.createMethod(methodName: 'glCallAdapter', returnType: 'protected String', arguments: [
          'GraphLinkPayload payload',
        ], statements: [
            if(_grammar.operationNameAsParameter)
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
              'return new $clientExceptionName(errors.stream().map(e -> GraphLinkError.fromJson((Map<String, Object>)e)).collect(Collectors.toList()));'
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

  GLClassModel generateMultipartAdapterFile(String importPrefix) =>
      const GLClassModel(
        imports: [JavaImports.map],
        body: javaGraphLinkMultipartAdapter,
      );



  GLClassModel generateWebSocketAdapterFile() =>
      const GLClassModel(body: javaWebSocketAdapter);

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

