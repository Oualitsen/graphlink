import 'package:graphlink/src/cache_store_java.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/client_serializers/java_client_constants.dart';
import 'package:graphlink/src/serializers/gl_client_serilaizer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';




class JavaClientSerializer extends GLClientSerilaizer {
  final GLParser _grammar;
  final codeGenUtils = JavaCodeGenUtils();
  final JavaJsonCodec jsonCodec;

  final GLGraphqSerializer gqlSerializer;

  JavaClientSerializer(this._grammar, GLSerializer serializer,
      {this.jsonCodec = JavaJsonCodec.jackson})
      : gqlSerializer = GLGraphqSerializer(_grammar, false),
        super(serializer);

  // Safe generated local variable names — avoids clashing with user-defined method arguments.
  String get _svOperationName => codeGenUtils.safeLocalVar('operationName');
  String get _svFragsValues => codeGenUtils.safeLocalVar('fragsValues');
  String get _svQuery => codeGenUtils.safeLocalVar('query');
  String get _svPayload => codeGenUtils.safeLocalVar('payload');
  String get _svVariables => codeGenUtils.safeLocalVar('variables');
  String get _svEncodedPayload => codeGenUtils.safeLocalVar('encodedPayload');
  String get _svResponseText => codeGenUtils.safeLocalVar('responseText');
  String get _svDecodedResponse => codeGenUtils.safeLocalVar('decodedResponse');
  String get _svData => codeGenUtils.safeLocalVar('data');
  String get _svPartialQueries => codeGenUtils.safeLocalVar('partialQueries');
  String get _svResponseMap => codeGenUtils.safeLocalVar('responseMap');
  String get _svStaleData => codeGenUtils.safeLocalVar('staleData');
  String get _svRemaining => codeGenUtils.safeLocalVar('remaining');
  String get _svRawListener => codeGenUtils.safeLocalVar('rawListener');
  String get _svHandler => codeGenUtils.safeLocalVar('handler');
  String get _svFragmentNap => codeGenUtils.safeLocalVar('fragmentMap');
  String get _svTagLocks => codeGenUtils.safeLocalVar('tagLocks');
  String get _svMultipartAdapter => codeGenUtils.safeLocalVar('multipartAdapter');
  String get _svAdapter => codeGenUtils.safeLocalVar('adapter');
  String get _svStore => codeGenUtils.safeLocalVar('store');
  String get _svEncoder => codeGenUtils.safeLocalVar('encoder');
  String get _svDecoder => codeGenUtils.safeLocalVar('decoder');
  String get _svFiles => codeGenUtils.safeLocalVar('files');
  String get _svFileMap => codeGenUtils.safeLocalVar('fileMap');
  String get _svOperationsMap => codeGenUtils.safeLocalVar('operationsMap');
  String get _svOperations => codeGenUtils.safeLocalVar('operations');
  String get _svMapJson => codeGenUtils.safeLocalVar('mapJson');

  @override
  GLClassModel generateClient(String importPrefix,
      {bool hasDefaultAdapters = true}) {
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
      'private final Map<String, String> $_svFragmentNap = new HashMap<>();',
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
            "queries = new ${classNameFromType(GLQueryType.query)}(adapter, $_svFragmentNap, encoder, decoder, store);",
          if (_grammar.hasMutations)
            "mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, ${_grammar.hasUploadMutations ? 'multipartAdapter, ' : ''}$_svFragmentNap, encoder, decoder, store);",
          if (_grammar.hasSubscriptions)
            "subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, $_svFragmentNap, encoder, decoder, store);",
          ..._grammar.fragments.values.map((value) =>
              '$_svFragmentNap.put("${value.tokenInfo}", "${gqlSerializer.serializeFragmentDefinitionBase(value)}");'),
        ],
      ),
      if (hasDefaultAdapters) ..._convenienceConstructors(),
    ]));
    if (serializeSubscriptions().isNotEmpty) {
      bodyBuf.writeln(serializeSubscriptions().ident());
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
        // the url+$_svEncoder constructors can delegate with this() as the first
        // statement while only constructing one $_svAdapter instance.
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
  GLClassModel? getQueriesClass(String importPrefix) =>
      _buildClassForType(GLQueryType.query, importPrefix);

  @override
  GLClassModel? getMutationsClass(String importPrefix) =>
      _buildClassForType(GLQueryType.mutation, importPrefix);

  @override
  GLClassModel? getSubscriptionsClass(String importPrefix) =>
      _buildClassForType(GLQueryType.subscription, importPrefix);

  /// Kept for backwards compatibility — prefer [getQueriesClass],
  /// [getMutationsClass], or [getSubscriptionsClass] via the base-class API.
  GLClassModel? generateQueriesClassByType(
          GLQueryType type, String importPrefix) =>
      _buildClassForType(type, importPrefix);

  GLClassModel? _buildClassForType(GLQueryType type, String importPrefix) {
    var queries = _grammar.queries.values;
    var queryList = queries
        .where((element) => element.type == type && _grammar.hasQueryType(type))
        .toList();
    if (queryList.isEmpty) {
      return null;
    }
    final importContainer = GLImportContainer();
    if (type == GLQueryType.subscription) {
      importContainer.importDepencies
          .add(_grammar.getTypeByName("GraphLinkClientAdapter")!);
    } else {
      importContainer.importDepencies
          .add(_grammar.getTypeByName("GraphLinkClientAdapter")!);
    }
    importContainer.importDepencies.addAll([
      'GraphLinkJsonEncoder',
      'GraphLinkJsonDecoder'
    ].map((e) => _grammar.getTypeByName(e)!));

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
                'super(fragmentMap, store, encoder, decoder);',
                'this.$_svAdapter = adapter;',
                if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
                  'this.$_svMultipartAdapter = multipartAdapter;',
                if (type == GLQueryType.subscription)
                  '$_svHandler = new GraphLinkSubscriptionHandler(adapter, decoder, encoder);',
              ]),
          ...queryList
              .where((e) => e.type == GLQueryType.query)
              .map((e) => queryToMethod(e, importContainer)),
          ...queryList
              .where((e) => e.type == GLQueryType.subscription)
              .map((e) => subscriptionToMethod(e, importContainer)),
          ...queryList
              .where((e) => e.type == GLQueryType.mutation)
              .map((e) => mutationToMethod(e, importContainer)),
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
                      'fragmentsBuilder.append(${_svFragmentNap}.get(fragName));',
                    ]),
                'queryBuilder.append(fragmentsBuilder);',
                'return GraphLinkPayload.builder().query(queryBuilder.toString()).operationName(operationName).variables(variables).build();',
              ],
            ),
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

  Set<GLToken> _getQueryImports(GLQueryType type) {
    var result = <GLToken>[_grammar.getTokenByKey("GraphLinkPayload")!];
    var queries = _grammar.queries.values.where((e) => e.type == type);
    queries
        .where((element) => element.typeDefinition != null)
        .map((e) => e.typeDefinition!)
        .forEach(result.add);

    queries.expand((e) => e.arguments).forEach((arg) {
      if (_grammar.isEnum(arg.type.token)) {
        result.add(_grammar.enums[arg.type.token]!);
      } else if (_grammar.isInput(arg.type.token)) {
        result.add(_grammar.inputs[arg.type.token]!);
      }
    });
    return Set.unmodifiable(result);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      if (type == GLQueryType.subscription)
        'GraphLinkWebSocketAdapter adapter'
      else
        'GraphLinkClientAdapter adapter',
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
          'private final GraphLinkClientAdapter $_svAdapter;',
          if (type == GLQueryType.mutation && _grammar.hasUploadMutations)
            'private final GraphLinkMultipartAdapter $_svMultipartAdapter;',
        ];
      case GLQueryType.subscription:
        return [
          "private final GraphLinkSubscriptionHandler $_svHandler;",
          "private final GraphLinkWebSocketAdapter $_svAdapter;"
        ];
    }
  }

  String queryToMethod(GLQueryDefinition def, GLImportContainer container) {
    final dividedQueries = gqlSerializer.divideQueryDefinition(def, _grammar);
    final directives = gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));
    final returnType = def.getGeneratedTypeDefinition().tokenInfo.token;
    container.imports.addAll([
      JavaImports.map,
      JavaImports.hashMap,
      JavaImports.list,
      JavaImports.arrayList
    ]);
    if (dividedQueries.isNotEmpty) {
      container.imports
          .addAll([JavaImports.set, JavaImports.hashSet, JavaImports.arrays]);
    }
    return codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String $_svOperationName = "${def.tokenInfo}";',
          generateVariables(def, container),
          'List<GraphLinkPartialQuery> $_svPartialQueries = new ArrayList<>();',
          ...dividedQueries.map(serializePartialQueryJava),
          'Map<String, Object> $_svResponseMap = new HashMap<>();',
          'Map<String, Object> $_svStaleData = new HashMap<>();',
          codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: '$_svPartialQueries',
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
                                    '$_svStaleData.put(partQuery.elementKey, $_svDecoder.decode(entry.data));'
                                  ],
                                  elseBlockStatements: [
                                    '$_svResponseMap.put(partQuery.elementKey, $_svDecoder.decode(entry.data));'
                                  ],
                                ),
                              ]),
                        ],
                        catchStatements: [],
                        catchVariable: 'ignored',
                      ),
                    ]),
              ]),
          'List<GraphLinkPartialQuery> $_svRemaining = new ArrayList<>();',
          codeGenUtils.forEachLoop(
              variable: 'partQuery',
              iterable: '$_svPartialQueries',
              statements: [
                codeGenUtils.ifStatement(
                    condition: '!$_svResponseMap.containsKey(partQuery.elementKey)',
                    ifBlockStatements: [
                      '$_svRemaining.add(partQuery);',
                    ]),
              ]),
          codeGenUtils.ifStatement(
              condition: '$_svRemaining.isEmpty()',
              ifBlockStatements: [
                'return $returnType.fromJson($_svResponseMap);',
              ]),
          'GraphLinkPayload $_svPayload = buildPayload($_svRemaining, $_svOperationName, "$directives");',
          codeGenUtils.tryCatchFinally(
            tryStatements: [
              'String $_svResponseText = $_svAdapter.execute($_svEncoder.encode($_svPayload));',
              'return parseToObjectAndCache($_svResponseText, $_svResponseMap, $returnType::fromJson, $_svRemaining);',
            ],
            catchStatements: [
              '$_svResponseMap.putAll($_svStaleData);',
              'long remainingCount = $_svPartialQueries.stream().filter(e -> !$_svResponseMap.containsKey(e.elementKey)).count();',
              codeGenUtils.ifStatement(
                  condition: 'remainingCount > 0',
                  ifBlockStatements: [
                    'throw new RuntimeException(exception);',
                  ]),
              'return $returnType.fromJson($_svResponseMap);',
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
      buffer.writeln('  pqVars.put("$argName", $_svVariables.get("$argName"));');
    }
    buffer.writeln('  $_svPartialQueries.add(new GraphLinkPartialQuery(');
    buffer.writeln('    "$queryStr",');
    buffer.writeln('    pqVars,');
    buffer.writeln('    ${e.cacheTTL},');
    buffer.writeln('    $tagsStr,');
    buffer.writeln('    "${e.operationName}",');
    buffer.writeln('    "${e.elementKey}",');
    buffer.writeln('    $fragNamesStr,');
    buffer.writeln('    $argDeclsStr,');
    buffer.writeln('    ${e.staleIfOffline},');
    buffer.writeln('    $_svEncoder');
    buffer.writeln('  ));');
    buffer.write('}');
    return buffer.toString();
  }

  String mutationToMethod(GLQueryDefinition def, GLImportContainer container) {
    final frags = def.fragments(_grammar);
    final returnType = 'public ${returnTypeByQueryType(def)}';
    final methodName = def.tokenInfo.token;
    final queryLine = frags.isNotEmpty
        ? [
            'List<String> $_svFragsValues = Arrays.asList(${frags.map((e) => '${_svFragmentNap}.get("${e.token}")').join(", ")});',
            'String $_svQuery = "${gqlSerializer.serializeQueryDefinition(def)} " + String.join(" ", $_svFragsValues);',
          ]
        : ['String $_svQuery = "${gqlSerializer.serializeQueryDefinition(def)}";'];
    container.imports
        .addAll([JavaImports.map, JavaImports.hashMap, JavaImports.arrays]);
    if (frags.isNotEmpty) {
      container.imports.add(JavaImports.list);
    }

    if (_grammar.mutationHasUploads(def)) {
      final argsNoProgress = getArguments(def);
      final argNamesNoProgress =
          def.arguments.map((e) => e.dartArgumentName).join(', ');
      final argsWithProgress = [
        ...argsNoProgress,
        'UploadProgressCallback onProgress'
      ];

      final body = codeGenUtils.block([
        'String $_svOperationName = "$methodName";',
        ...queryLine,
        generateVariables(def, container),
        _serializeMultipartAdapterCall(def, container),
      ]);

      // overload without onProgress delegates to the full method with null
      final noProgressBody = codeGenUtils.block([
        'return $methodName($argNamesNoProgress, null);',
      ]);
      container.imports.add(JavaImports.ioException);
      return [
        '$returnType $methodName${codeGenUtils.parentheses(argsNoProgress)} throws IOException $noProgressBody',
        '$returnType $methodName${codeGenUtils.parentheses(argsWithProgress)} throws IOException $body',
      ].join('\n\n');
    }

    return codeGenUtils.createMethod(
        returnType: returnType,
        methodName: methodName,
        arguments: getArguments(def),
        statements: [
          'String $_svOperationName = "$methodName";',
          ...queryLine,
          generateVariables(def, container),
          'GraphLinkPayload $_svPayload = GraphLinkPayload.builder().query($_svQuery).operationName($_svOperationName).variables($_svVariables).build();',
          _serializeAdapterCall(def),
        ]);
  }

  String _serializeMultipartAdapterCall(
      GLQueryDefinition def, GLImportContainer container) {
    final uploadNames = _grammar.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();
    final returnType = def.getGeneratedTypeDefinition().tokenInfo.token;
    final hasListArg = uploadArgs.any((a) => a.type.isList);
    container.imports.addAll(
        [JavaImports.linkedHashMap, JavaImports.hashMap, JavaImports.arrays]);
    final statements = <String>[
      'Map<String, GLUpload> ${_svFiles} = new LinkedHashMap<>();',
      'Map<String, Object> ${_svFileMap} = new HashMap<>();',
      if (hasListArg) 'int _slot = 0;',
    ];

    var staticIndex = 0;
    for (final arg in uploadArgs) {
      final name = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.add(
          codeGenUtils.forLoop(
            init: 'int _i = 0',
            condition: '_i < $name.size()',
            increment: '_i++',
            statements: [
              '${_svFiles}.put(String.valueOf(_slot + _i), $name.get(_i));',
              '${_svFileMap}.put(String.valueOf(_slot + _i), Arrays.asList("variables.$name." + _i));',
            ],
          ),
        );
        statements.add('_slot += $name.size();');
      } else if (hasListArg) {
        statements.addAll([
          '${_svFiles}.put(String.valueOf(_slot), $name);',
          '${_svFileMap}.put(String.valueOf(_slot), Arrays.asList("variables.$name"));',
          '_slot++;',
        ]);
      } else {
        statements.addAll([
          '${_svFiles}.put("$staticIndex", $name);',
          '${_svFileMap}.put("$staticIndex", Arrays.asList("variables.$name"));',
        ]);
        staticIndex++;
      }
    }

    statements.addAll([
      'Map<String, Object> ${_svOperationsMap} = new HashMap<>();',
      '${_svOperationsMap}.put("query", $_svQuery);',
      '${_svOperationsMap}.put("operationName", $_svOperationName);',
      '${_svOperationsMap}.put("variables", $_svVariables);',
      'String ${_svOperations} = $_svEncoder.encode(${_svOperationsMap});',
      'String ${_svMapJson} = $_svEncoder.encode(${_svFileMap});',
      'String $_svResponseText = $_svMultipartAdapter.executeMultipart(${_svOperations}, ${_svMapJson}, ${_svFiles}, onProgress);',
      'Map<String, Object> $_svDecodedResponse = $_svDecoder.decode($_svResponseText);',
      codeGenUtils.ifStatement(
        condition: '$_svDecodedResponse.containsKey("errors")',
        ifBlockStatements: [
          'throw ${clientExceptionName}.of((List)$_svDecodedResponse.get("errors"));'
        ],
      ),
      'Map<String, Object> $_svData = (Map<String, Object>) $_svDecodedResponse.get("data");',
      _serializeInvalidationCall(def),
      'return $returnType.fromJson($_svData);',
    ]);

    return statements.join('\n');
  }

  String subscriptionToMethod(
      GLQueryDefinition def, GLImportContainer container) {
        container.imports.addAll([JavaImports.map, JavaImports.hashMap, JavaImports.list, JavaImports.arrays]);
    final frags = def.fragments(_grammar);
    return codeGenUtils.createMethod(
        returnType: 'public ${returnTypeByQueryType(def)}',
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        statements: [
          'String $_svOperationName = "${def.tokenInfo}";',
          if (frags.isNotEmpty) ...[
            'List<String> $_svFragsValues = Arrays.asList(${frags.map((e) => '${_svFragmentNap}.get("${e.token}")').join(", ")});',
            'String $_svQuery = "${gqlSerializer.serializeQueryDefinition(def)} " + String.join(" ", $_svFragsValues);',
          ] else
            'String $_svQuery = "${gqlSerializer.serializeQueryDefinition(def)}";',
          generateVariables(def, container),
          "GraphLinkPayload $_svPayload = GraphLinkPayload.builder().query($_svQuery).operationName($_svOperationName).variables($_svVariables).build();",
          _serializeSubscriptionAdapterCall(def),
        ]);
  }

  String generateVariables(GLQueryDefinition def, GLImportContainer container) {
    var buffer =
        StringBuffer("Map<String, Object> $_svVariables = new HashMap<>();");
    buffer.writeln();
    def.arguments
        .map((e) =>
            '$_svVariables.put("${e.dartArgumentName}", ${_serializeArgumentValue(def, e.token, container)});')
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
      "String $_svEncodedPayload = $_svEncoder.encode($_svPayload);",
      "String $_svResponseText = $_svAdapter.execute($_svEncodedPayload);",
      "Map<String, Object> $_svDecodedResponse = $_svDecoder.decode($_svResponseText);",
      codeGenUtils.ifStatement(
          condition: '$_svDecodedResponse.containsKey("errors")',
          ifBlockStatements: [
            'throw ${clientExceptionName}.of((List)$_svDecodedResponse.get("errors"));'
          ],
          elseBlockStatements: [
            'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson((Map<String, Object>)$_svDecodedResponse.get("data"));'
          ])
    ].join("\n");
  }

  String _serializeMutationAdapterCall(GLQueryDefinition def) {
    return [
      "String $_svEncodedPayload = $_svEncoder.encode($_svPayload);",
      "String $_svResponseText = $_svAdapter.execute($_svEncodedPayload);",
      "Map<String, Object> $_svDecodedResponse = $_svDecoder.decode($_svResponseText);",
      codeGenUtils.ifStatement(
          condition: '$_svDecodedResponse.containsKey("errors")',
          ifBlockStatements: [
            'throw ${clientExceptionName}.of((List)$_svDecodedResponse.get("errors"));',
          ]),
      'Map<String, Object> $_svData = (Map<String, Object>) $_svDecodedResponse.get("data");',
      _serializeInvalidationCall(def),
      'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson($_svData);',
    ].join("\n");
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return '$_svStore.invalidateAll();';
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
            '${subscriptionListenerRef}<Map<String, Object>> $_svRawListener = new ${subscriptionListenerRef}<Map<String, Object>>',
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
    return ['${method};', '$_svHandler.handlePayload($_svPayload, $_svRawListener);']
        .join('\n');
  }

  String _serializeArgumentValue(
      GLQueryDefinition def, String argName, GLImportContainer container) {
    var arg = def.findByName(argName);
    if (_grammar.uploadScalarNames.contains(arg.type.firstType.token)) {
      if (arg.type.isList) {
        container.imports
            .addAll([JavaImports.arrayList, JavaImports.collections]);
        return 'new ArrayList<>(Collections.nCopies(${arg.dartArgumentName}.size(), null))';
      } else {
        return 'null';
      }
    }
    return _callToJson(arg.dartArgumentName, arg.type, 0, container);
  }

  String _callToJson(String variableName, GLType type, int index,
      GLImportContainer container) {
    if (type.isList) {
      var inlineType = type.inlineType;
      String varName = "e${index}";
      var inlineCallToJson =
          _callToJson(varName, inlineType, index + 1, container);
      String method;
      if (varName == inlineCallToJson) {
        container.imports.add(JavaImports.collectors);
        method = "stream().${javaCollectorsToList}";
      } else {
        container.imports.add(JavaImports.collectors);
        method =
            "stream().map(${varName} -> ${inlineCallToJson}).${javaCollectorsToList}";
      }
      return JavaCodeGenUtils.safeCall(variableName, method, type.nullable);
    } else if (_grammar.isEnum(type.token) || _grammar.isInput(type.token)) {
      return JavaCodeGenUtils.safeCall(variableName, "toJson()", type.nullable);
    } else {
      return variableName;
    }
  }

  String _resolveArgType(arg) {
    final uploadNames = _grammar.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'List<GLUpload>' : 'GLUpload';
    }
    return serializer.serializeType(arg.type, false);
  }

  List<String> getArguments(GLQueryDefinition def) {
    final result = def.arguments
        .map((e) => '${_resolveArgType(e)} ${e.dartArgumentName}')
        .toList();
    if (def.type == GLQueryType.subscription) {
      result.add(
          '${subscriptionListenerRef}<${def.typeDefinition?.token}> listener');
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

  GLClassModel generateGraphLinkResolverBaseFile(String importPrefix) {
    final allTags = _grammar.getAllCacheTags();

    final classBody = codeGenUtils.createClass(
      className: 'GraphLinkResolverBase',
      statements: [
        'protected final Map<String, String> ${_svFragmentNap};',
        'protected final GraphLinkCacheStore $_svStore;',
        'protected final GraphLinkJsonEncoder $_svEncoder;',
        'protected final GraphLinkJsonDecoder $_svDecoder;',
        'private final Map<String, ReentrantLock> $_svTagLocks = new HashMap<>();',
        codeGenUtils.createMethod(
          methodName: 'GraphLinkResolverBase',
          arguments: [
            'Map<String, String> fragmentMap',
            'GraphLinkCacheStore store',
            'GraphLinkJsonEncoder encoder',
            'GraphLinkJsonDecoder decoder',
          ],
          statements: [
            'this.${_svFragmentNap} = fragmentMap;',
            'this.$_svStore = store;',
            'this.$_svEncoder = encoder;',
            'this.$_svDecoder = decoder;',
            'String[] tags = {${allTags.map((t) => '"$t"').join(', ')}};',
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              '$_svTagLocks.put(tag, new ReentrantLock());',
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
            'Map<String, Object> result = $_svDecoder.decode(data);',
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
                        'GraphLinkCacheEntry entry = new GraphLinkCacheEntry($_svEncoder.encode(dataMap.get(q.elementKey)), System.currentTimeMillis() + q.ttl * 1000L);',
                        '$_svStore.set(q.cacheKey, $_svEncoder.encode(entry.toJson()));',
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
            'String result = $_svStore.get(key);',
            codeGenUtils
                .ifStatement(condition: 'result != null', ifBlockStatements: [
              'Map<String, Object> entryMap = $_svDecoder.decode(result);',
              'GraphLinkCacheEntry entry = GraphLinkCacheEntry.fromJson(entryMap);',
              codeGenUtils.ifStatement(
                  condition: 'entry.isExpired()',
                  ifBlockStatements: [
                    codeGenUtils.ifStatement(
                        condition: 'staleIfOffline',
                        ifBlockStatements: ['return entry.asStale();']),
                    '$_svStore.invalidate(key);',
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
              'ReentrantLock lock = $_svTagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $_svStore.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson($_svDecoder.decode(data));',
                  codeGenUtils.forEachLoop(
                      variable: 'k',
                      iterable: 'entry.keys',
                      statements: ['$_svStore.invalidate(k);']),
                  '$_svStore.invalidate(tKey);',
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
              'ReentrantLock lock = $_svTagLocks.get(tag);',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $_svStore.get(tKey);',
                'GraphLinkTagEntry entry = data != null ? GraphLinkTagEntry.fromJson($_svDecoder.decode(data)) : new GraphLinkTagEntry(new HashSet<>());',
                'entry.add(key);',
                '$_svStore.set(tKey, $_svEncoder.encode(entry.toJson()));',
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
              'ReentrantLock lock = $_svTagLocks.computeIfAbsent(tag, k -> new ReentrantLock());',
              'lock.lock();',
              codeGenUtils.tryCatchFinally(tryStatements: [
                'String data = $_svStore.get(tKey);',
                codeGenUtils
                    .ifStatement(condition: 'data != null', ifBlockStatements: [
                  'GraphLinkTagEntry entry = GraphLinkTagEntry.fromJson($_svDecoder.decode(data));',
                  'entry.remove(key);',
                  codeGenUtils.ifStatement(
                    condition: 'entry.keys.isEmpty()',
                    ifBlockStatements: ['$_svStore.invalidate(tKey);'],
                    elseBlockStatements: [
                      '$_svStore.set(tKey, $_svEncoder.encode(entry.toJson()));'
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
    );

    return GLClassModel(
      imports: [
        JavaImports.map,
        JavaImports.list,
        JavaImports.hashMap,
        JavaImports.hashSet,
        JavaImports.reentrantLock,
        JavaImports.function,
      ],
      importDepencies: [
        _grammar.getTokenByKey("GraphLinkJsonEncoder")!,
        _grammar.getTokenByKey("GraphLinkJsonDecoder")!
      ],
      body: classBody,
    );
  }

  GLClassModel? generateQueriesClassFile(
          GLQueryType type, String importPrefix) =>
      generateQueriesClassByType(type, importPrefix);

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
    // $_svAdapter/codec interfaces. Query return types and input argument types
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

  GLClassModel generateGLUploadFile() => const GLClassModel(
        imports: [
          JavaImports.inputStream,
          JavaImports.byteArrayInputStream,
          JavaImports.fileInputStream,
          JavaImports.file,
          JavaImports.ioException,
        ],
        body: javaGLUpload,
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
                ? defaultClientAdapterOkHttpWithUpload
                : defaultClientAdapterJava11WithUpload)
            : (flavor == 'okhttp'
                ? defaultClientAdapterOkHttp
                : defaultClientAdapterJava11),
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

