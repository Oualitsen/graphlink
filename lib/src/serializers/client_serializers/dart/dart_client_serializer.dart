import 'dart:io';
import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';

import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';

import 'package:graphlink/src/serializers/gl_serializer.dart';

const _operationNameParam = "operationName";
const _cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';
const _resolverBaseClassName = 'GraphLinkResolverBase';

class DartClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;
  final codeGenUtils = DartCodeGenUtils();

  late final DartClientOperationSerializer _opSer;

  DartClientSerializer(this._parser, GLSerializer dartSerializer,
      {this.generateAdapters = true, this.httpAdapter = DartHttpAdapter.http})
      : super(dartSerializer, _parser.serializer) {
    _opSer = DartClientOperationSerializer(
        _parser, codeGenUtils, gqlSerializer, serializer);
  }

  bool get _useDio => httpAdapter == DartHttpAdapter.dio;

  // ── render*Method delegates ────────────────────────────────────────────────

  @override
  String renderQueryMethod(GLQueryDefinition def) => _opSer.queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def);

  // ── Monolithic single-file generator (kept for backward compatibility) ─────

  @override
  GLClassModel generateClient() {
    final dartImports = [
      "import 'dart:convert';",
      "import 'dart:async';",
      if (_parser.hasSubscriptions) "import 'dart:math';",
      if (generateAdapters && httpAdapter != DartHttpAdapter.none)
        _useDio
            ? "import 'graph_link_dio_adapter.dart';"
            : "import 'graph_link_http_adapter.dart';",
      if (generateAdapters && _parser.hasSubscriptions)
        "import 'graph_link_websocket_adapter.dart';",
      ...serializeImports(_parser)
          .split('\n')
          .where((l) => l.trim().isNotEmpty),
      if (_parser.hasMutations && _parser.hasUploadMutations)
        "import 'graph_link_uploads.dart';",
    ];

    final buffer = StringBuffer();
    buffer.writeln();
    buffer.writeln("const tagKeyPrefix = '__tag__';");
    buffer.writeln();
    buffer.writeln(cacheEntry);
    buffer.writeln();
    buffer.writeln(glLock);
    buffer.writeln();
    buffer.writeln(tagEntry);
    buffer.writeln();
    buffer.writeln(partialQuery);
    buffer.writeln();
    buffer.writeln(graphLinkCacheStore);
    buffer.writeln();
    buffer.writeln(inMemoryGraphLinkCacheStore);
    buffer.writeln();
    if (_parser.hasUploadMutations) {
      buffer.writeln(dartUploadDefaultConverter);
      buffer.writeln();
    }

    GLQueryType.values
        .map((e) => _buildOperationClass(e))
        .where((e) => e != null)
        .map((e) => e!)
        .forEach(buffer.writeln);

    buffer.writeln(_buildResolverBaseClass());
    buffer.writeln(_buildGraphLinkClientClass());
    if (_parser.hasSubscriptions) {
      buffer.writeln(handshakeStatus.ident());
      buffer.writeln(dartStreamSink.ident());
      buffer.writeln(webSocketAdapter.ident());
      buffer.writeln(dartGraphqlMessageTypes.ident());
      buffer.writeln(subscriptionHandler.ident());
    }
    return GLClassModel(imports: dartImports, body: buffer.toString());
  }

  // ── Per-file generators (used by dart_client_generator) ───────────────────

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

  /// Returns the resolver base file: tag prefix constant + [GraphLinkResolverBase].
  GLClassModel generateResolverBaseFile() {
    final payloadImport = serializer.serializeImportToken(
        _parser.getTokenByKey('GraphLinkPayload')!);
    return GLClassModel(
      imports: [
        "import 'dart:convert';",
        "import 'dart:async';",
        if (payloadImport.isNotEmpty) payloadImport,
        "import 'graph_link_cache_entry.dart';",
        "import 'graph_link_lock.dart';",
        "import 'graph_link_tag_entry.dart';",
        "import 'graph_link_cache_store.dart';",
      ],
      body: "const tagKeyPrefix = '__tag__';\n\n${_buildResolverBaseClass()}",
    );
  }

  /// Returns the standalone [GraphLinkQueries] file, or null if no queries.
  @override
  GLClassModel? getQueriesClass() {
    final body = _buildOperationClass(GLQueryType.query);
    if (body == null) return null;
    return GLClassModel(
      imports: _importsForType(GLQueryType.query),
      body: body,
    );
  }

  /// Returns the standalone [GraphLinkMutations] file, or null if no mutations.
  @override
  GLClassModel? getMutationsClass() {
    final body = _buildOperationClass(GLQueryType.mutation);
    if (body == null) return null;
    return GLClassModel(
      imports: _importsForType(GLQueryType.mutation),
      body: body,
    );
  }

  /// Returns the standalone [GraphLinkSubscriptions] file, or null if no subscriptions.
  @override
  GLClassModel? getSubscriptionsClass() {
    final body = _buildOperationClass(GLQueryType.subscription);
    if (body == null) return null;
    return GLClassModel(
      imports: _importsForType(GLQueryType.subscription),
      body: body,
    );
  }

  /// Returns a lean [GraphLinkClient]-only file (no operation classes).
  GLClassModel generateClientOnlyFile() {
    final imports = <String>[
      "import 'dart:async';",
      "import 'graph_link_cache_store.dart';",
      "import 'graph_link_in_memory_cache_store.dart';",
      "import 'graph_link_lock.dart';",
      if (_parser.hasQueries) "import 'graph_link_queries.dart';",
      if (_parser.hasMutations) "import 'graph_link_mutations.dart';",
      if (_parser.hasSubscriptions) "import 'graph_link_subscriptions.dart';",
      if (generateAdapters && httpAdapter != DartHttpAdapter.none)
        _useDio
            ? "import 'graph_link_dio_adapter.dart';"
            : "import 'graph_link_http_adapter.dart';",
      if (generateAdapters && _parser.hasSubscriptions) ...[
        "import 'graph_link_websocket_adapter.dart';",
        if (httpAdapter != DartHttpAdapter.none)
          "import 'graph_link_default_websocket_adapter.dart';",
      ],
      if (_parser.hasMutations && _parser.hasUploadMutations) ...[
        "import 'graph_link_uploads.dart';",
        "import 'graph_link_upload_converter.dart';",
      ],
    ];
    return GLClassModel(imports: imports, body: _buildGraphLinkClientClass());
  }

  // ── Import helpers ─────────────────────────────────────────────────────────

  List<String> _importsForType(GLQueryType type) {
    return [
      if (type != GLQueryType.subscription) "import 'dart:convert';",
      "import 'dart:async';",
      "import 'graph_link_cache_store.dart';",
      "import 'graph_link_lock.dart';",
      "import 'graph_link_resolver_base.dart';",
      if (type == GLQueryType.query) ...[
        "import 'graph_link_cache_entry.dart';",
        "import 'graph_link_partial_query.dart';",
        serializer.serializeImportToken(_parser.getTokenByKey('GraphLinkFullResponse')!),
      ],
      if (type == GLQueryType.mutation && _parser.hasUploadMutations)
        "import 'graph_link_uploads.dart';",
      if (type == GLQueryType.subscription) ...[
        "import 'graph_link_subscription_handler.dart';",
        "import 'graph_link_websocket_adapter.dart';",
      ],
      ...schemaImportsFor(type),
    ];
  }

  // ── Generated class builders ───────────────────────────────────────────────

  String _buildResolverBaseClass() {
    return codeGenUtils.createClass(
        className: _resolverBaseClassName,
        statements: [
          'late final $_cacheStoreClassName $svStore;',
          'late final Map<String, GraphLinkLock> $svTagLocks;',
                    'late final Map<String, String> $svFragMap;',
          declareHttpAdapter(),
          codeGenUtils.createMethod(
              methodName: _resolverBaseClassName,
              namedArguments: false,
              arguments: [
                '$_cacheStoreClassName store',
                'Map<String, GraphLinkLock> locks',
                'this.$svAdapter',
                'Map<String, String> fragmentMap',
              ],
              statements: [
                '$svStore = store;',
                '$svTagLocks = locks;',
                '$svFragMap = fragmentMap;',
              ]),
          codeGenUtils.createMethod(
              methodName: "assembleQuery",
              namedArguments: false,
              arguments: [
                "String query",
                "Set<String> fragmentNames",
              ],
              returnType: "String",
              statements: [
                'final buffer = StringBuffer(query);',
                codeGenUtils.forEachLoop(
                    variable: 'name',
                    iterable: 'fragmentNames',
                    statements: [
                      'final frag = $svFragMap[name];',
                      codeGenUtils.ifStatement(
                          condition: 'frag != null',
                          ifBlockStatements: [
                            'buffer.write(" ");',
                            'buffer.write(frag);',
                          ]),
                    ]),
                'return buffer.toString();',
              ]),
          codeGenUtils.createMethod(
              returnType: 'Future<String>',
              methodName: "glCallAdapter",
              async: true,
              namedArguments: false,
              arguments: ['GraphLinkPayload payload'],
              statements: [
                if (_parser.operationNameAsParameter)
                  'return await $svAdapter(json.encode(payload.toJson()), payload.operationName);'
                else
                  'return await $svAdapter(json.encode(payload.toJson()));'
              ]),
          codeGenUtils.createMethod(
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
                codeGenUtils
                    .ifStatement(condition: 'result != null', ifBlockStatements: [
                  'var entryMap = jsonDecode(result);',
                  'var entry = GraphLinkCacheEntry.fromJson(entryMap);',
                  codeGenUtils.ifStatement(
                      condition: 'entry.isExpired',
                      ifBlockStatements: [
                        codeGenUtils.ifStatement(
                            condition: 'staleIfOffline',
                            ifBlockStatements: ['return entry.asStale();']),
                        '$svStore.invalidate(key);',
                        codeGenUtils.ifStatement(
                            condition: 'tags.isNotEmpty',
                            ifBlockStatements: ['_removeKeyFromTags(key, tags);']),
                        'return null;',
                      ],
                      elseBlockStatements: ['return entry;']),
                ]),
                'return null;'
              ]),
          codeGenUtils.createMethod(
              methodName: "invalidateByTags",
              namedArguments: false,
              arguments: ["List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      'final tagKey = "\${tagKeyPrefix}\${tag}";',
                      'final lock = $svTagLocks[tag]!;',
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        'final data = await $svStore.get(tagKey);',
                        codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              'final entry = GraphLinkTagEntry.decode(data);',
                              codeGenUtils.forEachLoop(
                                  variable: 'key',
                                  iterable: 'entry.keys',
                                  statements: ['await $svStore.invalidate(key);']),
                              'await $svStore.invalidate(tagKey);'
                            ]),
                      ]),
                      ');'
                    ])
              ]),
          codeGenUtils.createMethod(
              methodName: "addKeyToTags",
              namedArguments: false,
              arguments: ["String key", "List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      'final tagKey = "\${tagKeyPrefix}\${tag}";',
                      'final lock = $svTagLocks[tag]!;',
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        'final data = await $svStore.get(tagKey);',
                        'final entry = data != null ? GraphLinkTagEntry.decode(data) : GraphLinkTagEntry({});',
                        'entry.add(key);',
                        'await $svStore.set(tagKey, entry.encode());'
                      ]),
                      ');'
                    ])
              ]),
          codeGenUtils.createMethod(
              methodName: "_removeKeyFromTags",
              namedArguments: false,
              arguments: ["String key", "List<String> tags"],
              returnType: "Future<void>",
              async: true,
              statements: [
                codeGenUtils.forEachLoop(
                    variable: 'tag',
                    iterable: 'tags',
                    statements: [
                      'final tagKey = "\${tagKeyPrefix}\${tag}";',
                      'final lock = $svTagLocks.putIfAbsent(tag, () => GraphLinkLock());',
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        'final data = await $svStore.get(tagKey);',
                        codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              'final entry = GraphLinkTagEntry.decode(data);',
                              'entry.remove(key);',
                              codeGenUtils.ifStatement(
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

  String? _buildOperationClass(GLQueryType type) {
    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

    return codeGenUtils.createClass(
        className: "${classNameFromType(type)} extends $_resolverBaseClassName",
        statements: [
          _declareOperationFields(type),
          codeGenUtils.createConstructor(
              className: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              superArguments: ['store', svTagLocks, 'httpAdapter', if (type == GLQueryType.query) 'fragmentMap' else 'const {}'],
              statements: [
                if (type == GLQueryType.subscription)
                  '$svHandler = GraphLinkSubscriptionHandler(adapter);',
              ]),
          ...methods,
          if (type == GLQueryType.query) ...[
            codeGenUtils.createMethod(
                returnType: "GraphLinkPayload",
                namedArguments: false,
                methodName: "_buildPayload",
                arguments: [
                  "List<GraphLinkPartialQuery> partQueries",
                  "String operationName",
                  "String directives"
                ],
                statements: [
                  "final Map<String, dynamic> variables = {};",
                  codeGenUtils.forEachLoop(
                      variable: "partQuery",
                      iterable: "partQueries",
                      statements: ["variables.addAll(partQuery.variables);"]),
                  'final queryBuilder = StringBuffer("query \${operationName}");',
                  'final args = partQueries.expand((e) => e.argumentDeclarations).toSet();',
                  codeGenUtils.ifStatement(
                      condition: 'args.isNotEmpty',
                      ifBlockStatements: [
                        'queryBuilder.write("(");',
                        'queryBuilder.writeAll(args, ", ");',
                        'queryBuilder.write(")");'
                      ]),
                  codeGenUtils.ifStatement(
                      condition: 'directives.isNotEmpty',
                      ifBlockStatements: ['queryBuilder.write(directives);']),
                  'queryBuilder.write("{");',
                  codeGenUtils.forEachLoop(
                      variable: 'partQuery',
                      iterable: 'partQueries',
                      statements: [
                        'queryBuilder.write(partQuery.query);',
                        'queryBuilder.write(" ");',
                      ]),
                  'queryBuilder.write("}");',
                  'final fragments = partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => $svFragMap[fragName]!).join();',
                  'queryBuilder.write(fragments);',
                  'return GraphLinkPayload(query: queryBuilder.toString(), operationName: operationName, variables: variables);',
                ]),
            codeGenUtils.createMethod(
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
                  'final result = jsonDecode(data) as Map<String, dynamic>;',
                  'final rawData = result["data"];',
                  'final dataMap = rawData as Map<String, dynamic>? ?? <String, dynamic>{};',
                  codeGenUtils.forEachLoop(
                      variable: 'q',
                      iterable: 'remainingQueries',
                      statements: [
                        codeGenUtils.ifStatement(
                            condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
                            ifBlockStatements: [
                              'final entry = GraphLinkCacheEntry(jsonEncode(dataMap[q.elementKey]), DateTime.now().millisecondsSinceEpoch + q.ttl * 1000);',
                              '$svStore.set(q.cacheKey!, jsonEncode(entry.toJson()));',
                              codeGenUtils.ifStatement(
                                  condition: 'q.tags.isNotEmpty',
                                  ifBlockStatements: [
                                    'addKeyToTags(q.cacheKey!, q.tags);',
                                  ]),
                            ])
                      ]),
                  'dataMap.addAll(cachedResponse);',
                  "final fullResponse = <String, dynamic>{'data': rawData != null ? dataMap : null};",
                  codeGenUtils.ifStatement(
                      condition: 'result["errors"] != null',
                      ifBlockStatements: [
                        'fullResponse["errors"] = result["errors"];',
                      ]),
                  'final parsed = parser.call(fullResponse);',
                  codeGenUtils.ifStatement(
                      condition: 'captureErrors',
                      ifBlockStatements: ['return parsed;']),
                  'final errors = result["errors"] as List?;',
                  codeGenUtils.ifStatement(
                      condition: 'errors != null && errors.isNotEmpty',
                      ifBlockStatements: ['throw parsed.errors!;']),
                  'return parsed;',
                ]),
          ],
        ]);
  }

  String _buildGraphLinkClientClass() {
    return codeGenUtils.createClass(className: 'GraphLinkClient', statements: [
      'final $svFragMap = <String, String>{};',
      'final $svTagLocks = <String, GraphLinkLock>{};',
      if (_parser.hasQueries)
        'late final ${classNameFromType(GLQueryType.query)} queries;',
      if (_parser.hasMutations)
        'late final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_parser.hasSubscriptions)
        'late final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      'late final $_cacheStoreClassName store;',
      codeGenUtils.createMethod(
        methodName: 'GraphLinkClient',
        arguments: [
          'required ${_adapterDeclaration()}',
          if (_parser.hasUploadMutations) ...[
            'GLUploadConverter uploadConverter = defaultUploadConverter',
            'GLMultipartAdapter? uploadAdapter',
          ],
          if (_parser.hasSubscriptions) 'required GraphLinkWebSocketAdapter wsAdapter',
          '$_cacheStoreClassName? store'
        ],
        namedArguments: true,
        statements: [
          ..._parser.fragments.values.map((value) =>
              "$svFragMap['${value.tokenInfo}'] = '${gqlSerializer.serializeFragmentDefinitionBase(value)}';"),
          'this.store = store ?? $_inMemorycacheStoreClassName();',
          'final tags = ${_parser.getAllCacheTags().map((e) => e.quote()).toList()};',
          codeGenUtils.forEachLoop(
              variable: 'tag',
              iterable: 'tags',
              statements: ['$svTagLocks[tag] = GraphLinkLock();']),
          if (_parser.hasQueries)
            "queries = ${classNameFromType(GLQueryType.query)}(adapter, $svFragMap, this.store, $svTagLocks);",
          if (_parser.hasMutations)
            _parser.hasUploadMutations
                ? "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, uploadConverter, uploadAdapter, this.store, $svTagLocks);"
                : "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, this.store, $svTagLocks);",
          if (_parser.hasSubscriptions)
            "subscriptions = ${classNameFromType(GLQueryType.subscription)}(adapter, wsAdapter, this.store, $svTagLocks);",
        ],
      ),
      if (_parser.hasSubscriptions &&
          generateAdapters &&
          httpAdapter != DartHttpAdapter.none)
        _fromUrlConstructor(),
      if (generateAdapters && httpAdapter != DartHttpAdapter.none)
        _withHttpConstructor(),
    ]);
  }

  // ── Constructor / adapter helpers ──────────────────────────────────────────

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      '${delcareHttpAdapterFunction()} httpAdapter',
      if (type == GLQueryType.subscription) 'GraphLinkWebSocketAdapter adapter',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
        'this.$svUploadConverter',
        'this.$svUploadAdapter',
      ],
      if (type == GLQueryType.query) 'Map<String, String> fragmentMap',
      '$_cacheStoreClassName store',
      'Map<String, GraphLinkLock> $svTagLocks',
    ];
  }

  String _declareOperationFields(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return '';
      case GLQueryType.mutation:
        if (_parser.hasUploadMutations) {
          return "final GLUploadConverter $svUploadConverter;\nfinal GLMultipartAdapter? $svUploadAdapter;";
        }
        return '';
      case GLQueryType.subscription:
        return "late final GraphLinkSubscriptionHandler $svHandler;";
    }
  }

  String declareHttpAdapter() {
    return "final ${delcareHttpAdapterFunction()} $svAdapter;";
  }

  String delcareHttpAdapterFunction() {
    return 'Future<String> Function(String payload${_parser.operationNameAsParameter ? ', String $_operationNameParam' : ''})';
  }

  String _adapterDeclaration() {
    if (_parser.operationNameAsParameter) {
      return 'Future<String> Function(String payload, String $_operationNameParam) adapter';
    }
    return 'Future<String> Function(String payload) adapter';
  }

  String _withHttpConstructor() {
    final wsParams = _parser.hasSubscriptions
        ? 'required String wsUrl,\n  Future<Map<String, String>?> Function()? wsHeadersProvider,'
        : '';
    final wsArg = _parser.hasSubscriptions
        ? 'wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider),'
        : '';
    final adapterClass = _useDio ? 'GraphLinkDioAdapter' : 'GraphLinkHttpAdapter';
    const adapterArgs = 'url: url, headersProvider: headersProvider';

    if (_parser.hasUploadMutations) {
      return '''
factory GraphLinkClient.withHttp({
  required String url,
  $wsParams
  Future<Map<String, String>?> Function()? headersProvider,
  $_cacheStoreClassName? store,
}) {
  final _a = $adapterClass($adapterArgs);
  return GraphLinkClient(
    adapter: _a.call,
    uploadConverter: defaultUploadConverter,
    uploadAdapter: _a.multipartCall,
    $wsArg
    store: store,
  );
}''';
    }

    return '''
GraphLinkClient.withHttp({
  required String url,
  $wsParams
  Future<Map<String, String>?> Function()? headersProvider,
  $_cacheStoreClassName? store,
}) : this(
  adapter: $adapterClass($adapterArgs).call,
  $wsArg
  store: store,
);''';
  }

  String _fromUrlConstructor() {
    final adapterDecl = _adapterDeclaration();
    return '''
GraphLinkClient.fromUrl({
  required $adapterDecl,
  required String wsUrl,
  Future<Map<String, String>?> Function()? wsHeadersProvider,
  $_cacheStoreClassName? store,
}) : this(
  adapter: adapter,
  wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider),
  store: store,
);''';
  }

  // ── Subscription infrastructure file generators ───────────────────────────

  GLClassModel generateHandshakeStatusFile() =>
      const GLClassModel(body: handshakeStatus);

  GLClassModel generateStreamSinkFile() =>
      const GLClassModel(imports: ["import 'dart:async';"], body: dartStreamSink);

  GLClassModel generateWsAdapterFile() =>
      const GLClassModel(imports: ["import 'dart:async';"], body: webSocketAdapter);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: dartGraphqlMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() {
    final payloadImport = serializer.serializeImportToken(
        _parser.getTokenByKey('GraphLinkPayload')!);
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
      final token = _parser.getTokenByKey(name);
      if (token != null) {
        final imp = serializer.serializeImportToken(token);
        if (imp.isNotEmpty) imports.add(imp);
      }
    }
    return GLClassModel(imports: imports, body: subscriptionHandler);
  }

  // ── Adapter / upload file generators ──────────────────────────────────────

  String get fileExtension => '.dart';

  GLClassModel generateHttpAdapterFile() {
    if (_parser.hasUploadMutations) {
      stdout.writeln(
        '⚠️  Upload mutations detected with the http adapter.\n'
        '   Progress tracking buffers the entire request body in memory.\n'
        '   For large files, consider switching to the Dio adapter (httpAdapter: "dio").',
      );
    }
    final extraParam =
        _parser.operationNameAsParameter ? ', String operationName' : '';
    final multipartMethod = _parser.hasUploadMutations
        ? '''

  Future<String> multipartCall(Map<String, Object> parts, UploadProgressCallback? onProgress) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    final extraHeaders = await headersProvider?.call() ?? {};
    request.headers.addAll(extraHeaders);
    for (final entry in parts.entries) {
      if (entry.value is GLUpload) {
        final u = entry.value as GLUpload;
        request.files.add(http.MultipartFile(
          entry.key, u.stream, u.length ?? 0,
          filename: u.filename,
          contentType: MediaType.parse(u.mimeType),
        ));
      } else {
        request.fields[entry.key] = entry.value as String;
      }
    }

    if (onProgress == null) {
      final streamed = await request.send();
      return (await http.Response.fromStream(streamed)).body;
    }

    final bodyBytes = await request.finalize().toBytes();
    final total = bodyBytes.length;
    int sent = 0;

    const chunkSize = 8192;
    final counted = Stream.fromIterable([
      for (var i = 0; i < bodyBytes.length; i += chunkSize)
        bodyBytes.sublist(i, (i + chunkSize).clamp(0, bodyBytes.length)),
    ]).map((chunk) {
      sent += chunk.length;
      onProgress(sent, total);
      return chunk;
    });

    final raw = http.StreamedRequest('POST', Uri.parse(url));
    raw.headers.addAll(extraHeaders);
    raw.headers['content-type'] = request.headers['content-type']!;
    raw.contentLength = total;
    counted.listen(raw.sink.add, onDone: raw.sink.close);

    final streamed = await raw.send();
    return (await http.Response.fromStream(streamed)).body;
  }'''
        : '';
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'package:http/http.dart' as http;",
        "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
      ],
      body: """
class GraphLinkHttpAdapter {
  final String url;
  final Future<Map<String, String>?> Function()? headersProvider;

  GraphLinkHttpAdapter({
    required this.url,
    this.headersProvider,
  });

  Future<String> call(String payload$extraParam) async {
    final extraHeaders = await headersProvider?.call();
    final requestHeaders = {
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    };
    final response = await http.post(
      Uri.parse(${_parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url'}),
      body: payload,
      headers: requestHeaders,
    );
    return response.body;
  }$multipartMethod
}
""",
    );
  }

  GLClassModel generateDioAdapterFile() {
    final extraParam =
        _parser.operationNameAsParameter ? ', String operationName' : '';
    final multipartMethod = _parser.hasUploadMutations
        ? '''

  Future<String> multipartCall(Map<String, Object> parts, UploadProgressCallback? onProgress) async {
    final converted = <String, dynamic>{};
    for (final entry in parts.entries) {
      if (entry.value is GLUpload) {
        final u = entry.value as GLUpload;
        converted[entry.key] = MultipartFile(
          u.stream, u.length ?? 0,
          filename: u.filename,
          contentType: u.mimeType.isNotEmpty ? MediaType.parse(u.mimeType) : null,
        );
      } else {
        converted[entry.key] = entry.value;
      }
    }
    final formData = FormData.fromMap(converted);
    final response = await dio.post<dynamic>(url, data: formData,
        onSendProgress: onProgress != null ? (sent, total) => onProgress(sent, total) : null);
    final data = response.data;
    return data is String ? data : jsonEncode(data);
  }'''
        : '';
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'dart:convert';",
        "import 'package:dio/dio.dart';",
        if (_parser.hasUploadMutations) "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
      ],
      body: """
class GraphLinkDioAdapter {
  final String url;
  final Dio dio;

  GraphLinkDioAdapter({
    required this.url,
    Dio? dio,
    Future<Map<String, String>?> Function()? headersProvider,
    List<Interceptor> interceptors = const [],
    BaseOptions? options,
  }) : dio = dio ?? Dio(options ?? BaseOptions(contentType: 'application/json')) {
    if (dio == null) {
      if (headersProvider != null) {
        this.dio.interceptors.add(_HeadersInterceptor(headersProvider));
      }
      this.dio.interceptors.addAll(interceptors);
    }
  }

  Future<String> call(String payload$extraParam) async {
    final response = await dio.post<dynamic>(${_parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url'}, data: payload);
    final data = response.data;
    return data is String ? data : jsonEncode(data);
  }$multipartMethod
}

class _HeadersInterceptor extends Interceptor {
  final Future<Map<String, String>?> Function() _headersProvider;

  _HeadersInterceptor(this._headersProvider);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final headers = await _headersProvider();
    if (headers != null) {
      options.headers.addAll(headers);
    }
    handler.next(options);
  }
}
""",
    );
  }

  GLClassModel generateUploadConverterFile() => GLClassModel(
        imports: ["import 'graph_link_uploads.dart';"],
        body: dartUploadDefaultConverter,
      );

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: dartUploadsFile);

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
