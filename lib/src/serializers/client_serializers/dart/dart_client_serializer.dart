import 'dart:io';
import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';

import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_rest_operation_serializer.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';

import 'package:graphlink/src/serializers/gl_serializer.dart';

const _operationNameParam = "operationName";
const _cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';
const _resolverBaseClassName = 'GraphLinkResolverBase';
const _restResolverMixinName = 'GraphLinkRestResolver';

class DartClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;
  final codeGenUtils = DartCodeGenUtils();

  late final DartClientOperationSerializer _opSer;
  late final DartRestOperationSerializer _restSer;

  DartClientSerializer(this._parser, GLSerializer dartSerializer,
      {this.generateAdapters = true,
      this.httpAdapter = DartHttpAdapter.http,
      DartHttpAdapter? restHttpAdapter,
      this.commaQueryLists = false,
      this.bracketFormNesting = false})
      : restHttpAdapter = restHttpAdapter ?? httpAdapter,
        super(dartSerializer, _parser.serializer) {
    _opSer = DartClientOperationSerializer(
        _parser, codeGenUtils, gqlSerializer, serializer);
    _restSer = DartRestOperationSerializer(_parser, codeGenUtils, serializer, _opSer.callToJson,
        commaLists: commaQueryLists, bracketNesting: bracketFormNesting);
  }

  final DartHttpAdapter restHttpAdapter;
  final bool commaQueryLists;
  final bool bracketFormNesting;

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _parser.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) => _parser.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get _generatesWithHttp =>
      generateAdapters &&
      (httpAdapter != DartHttpAdapter.none || (!_hasGraphQL && restHttpAdapter != DartHttpAdapter.none));

  bool get _hasRest => _parser.restOperations.isNotEmpty;

  bool get _hasQueries => _hasOperations(GLQueryType.query);

  bool get _hasMutations => _hasOperations(GLQueryType.mutation);

  bool get _hasGraphQL => GLQueryType.values.any(_parser.hasQueryType);

  bool get _useDio => httpAdapter == DartHttpAdapter.dio;

  bool get _useRestDio => restHttpAdapter == DartHttpAdapter.dio;

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
      if (_hasRest) "import 'dart:typed_data';",
      if (generateAdapters && httpAdapter != DartHttpAdapter.none && _hasGraphQL)
        _useDio
            ? "import 'graph_link_dio_adapter.dart';"
            : "import 'graph_link_http_adapter.dart';",
      if (_hasRest && generateAdapters && restHttpAdapter != DartHttpAdapter.none)
        _useRestDio ? "import 'graph_link_rest_dio_adapter.dart';" : "import 'graph_link_rest_http_adapter.dart';",
      if (generateAdapters && _parser.hasSubscriptions)
        "import 'graph_link_websocket_adapter.dart';",
      ...serializeImports(_parser)
          .split('\n')
          .where((l) => l.trim().isNotEmpty),
      if ((_parser.hasMutations && _parser.hasUploadMutations) || _hasRest)
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

    if (_hasRest) {
      buffer.writeln(dartRestFile);
      buffer.writeln();
      buffer.writeln(dartRestResolver);
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

  /// Returns the standalone [GraphLinkSha256] file, only needed by persisted queries.
  GLClassModel generateSha256File() {
    if (!_parser.persistedQueries) {
      throw StateError('The SHA-256 runtime is only generated when persistedQueries is enabled.');
    }
    return const GLClassModel(
      imports: ["import 'dart:convert';"],
      body: dartSha256,
    );
  }

  /// Returns the standalone [GraphLinkPersistedQueries] file, only needed by persisted queries.
  GLClassModel generatePersistedQueriesFile() {
    if (!_parser.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return GLClassModel(
      imports: const ["import 'dart:convert';"],
      body: _parser.persistedQueriesUseGet ? '$dartPersistedQueries\n$dartPersistedQueriesGet' : dartPersistedQueries,
    );
  }

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
        "import 'graph_link_partial_query.dart';",
        if (_parser.persistedQueries) ...[
          "import 'graph_link_sha256.dart';",
          "import 'graph_link_persisted_queries.dart';",
        ],
        serializer.serializeImportToken(
            _parser.getTokenByKey('GraphLinkFullResponse')!),
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
      if (_hasQueries) "import 'graph_link_queries.dart';",
      if (_hasMutations) "import 'graph_link_mutations.dart';",
      if (_parser.hasSubscriptions) "import 'graph_link_subscriptions.dart';",
      if (_hasRest) "import 'graph_link_rest.dart';",
      if (_hasRest && generateAdapters && restHttpAdapter != DartHttpAdapter.none)
        _useRestDio ? "import 'graph_link_rest_dio_adapter.dart';" : "import 'graph_link_rest_http_adapter.dart';",
      if (generateAdapters && httpAdapter != DartHttpAdapter.none && _hasGraphQL)
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
      ..._restImportsFor(type),
      ...schemaImportsFor(type),
    ].toSet().toList();
  }

  List<String> _restImportsFor(GLQueryType type) {
    final operations = _restOperations(type);
    if (operations.isEmpty) return const [];
    final uploads = _parser.uploadScalarNames;
    final usesUploads =
        operations.any((o) => o.arguments.any((a) => uploads.contains(a.argument.type.firstType.token)));
    final tokens = <GLToken>[];
    for (final operation in operations) {
      final names = [
        operation.field.type.firstType.token,
        ...operation.arguments.map((a) => a.argument.type.firstType.token),
      ];
      for (final name in names) {
        if (_parser.isEnum(name) ||
            _parser.isInput(name) ||
            _parser.types.containsKey(name) ||
            _parser.interfaces.containsKey(name)) {
          final token = _parser.getTokenByKey(name);
          if (token != null) tokens.add(token);
        }
      }
    }
    return [
      "import 'graph_link_rest.dart';",
      "import 'graph_link_rest_resolver.dart';",
      if (usesUploads && !(type == GLQueryType.mutation && _parser.hasUploadMutations))
        "import 'graph_link_uploads.dart';",
      ...tokens.map(serializer.serializeImportToken).where((e) => e.isNotEmpty),
    ];
  }

  // ── Generated class builders ───────────────────────────────────────────────

  String _buildGlSendMethod() {
    final call = _parser.operationNameAsParameter
        ? "$svAdapter(json.encode(body), body['operationName'] as String)"
        : '$svAdapter(json.encode(body))';
    return codeGenUtils.createMethod(
        returnType: 'Future<String>',
        methodName: 'glSend__',
        async: true,
        namedArguments: false,
        arguments: ['Map<String, dynamic> body'],
        statements: ['return await $call;']);
  }

  String _buildGlSendHashOnlyMethod() {
    final call = _parser.operationNameAsParameter
        ? "glGetAdapter__(json.encode(body), body['operationName'] as String)"
        : 'glGetAdapter__(json.encode(body))';
    return codeGenUtils.createMethod(
        returnType: 'Future<String>',
        methodName: 'glSendHashOnly__',
        async: true,
        namedArguments: false,
        arguments: ['GraphLinkPayload payload', 'Map<String, dynamic> body'],
        statements: [
          codeGenUtils.ifStatement(
              condition: "glGetUnsupported__ || payload.query.startsWith('mutation')",
              ifBlockStatements: ['return await glSend__(body);']),
          codeGenUtils.tryCatchFinally(
              tryStatements: ['return await $call;'],
              catchVariable: 'e',
              catchStatements: [
                codeGenUtils.ifStatement(
                    condition: 'e is! GraphLinkGetNotSupported', ifBlockStatements: ['rethrow;']),
                'glGetUnsupported__ = true;',
                'return await glSend__(body);',
              ]),
        ]);
  }

  List<String> _persistedCallAdapterStatements() {
    return [
      codeGenUtils.ifStatement(
          condition:
              'glPersistedUnsupported__ || payload.query.length <= GraphLinkPersistedQueries.minQueryLength',
          ifBlockStatements: ['return await glSend__(payload.toJson());']),
      codeGenUtils.constDecl(
          'glExtensions__', 'GraphLinkPersistedQueries.extensions(glHash(payload.query))'),
      codeGenUtils.constDecl(
          'glHashOnly__',
          "{'operationName': payload.operationName, 'variables': payload.variables, 'extensions': glExtensions__}"),
      codeGenUtils.constDecl(
          'glResponse__',
          _parser.persistedQueriesUseGet
              ? 'await glSendHashOnly__(payload, glHashOnly__)'
              : 'await glSend__(glHashOnly__)'),
      codeGenUtils.constDecl('glFailure__', 'GraphLinkPersistedQueries.failure(glResponse__)'),
      codeGenUtils.ifStatement(condition: 'glFailure__ == null', ifBlockStatements: ['return glResponse__;']),
      codeGenUtils.constDecl('glBody__', 'payload.toJson()'),
      codeGenUtils.ifStatement(
          condition: 'glFailure__ == GraphLinkPersistedQueries.notSupported',
          ifBlockStatements: ['glPersistedUnsupported__ = true;'],
          elseBlockStatements: ["glBody__['extensions'] = glExtensions__;"]),
      'return await glSend__(glBody__);',
    ];
  }

  String _buildGlHashMethod() {
    return codeGenUtils.createMethod(
        returnType: 'String',
        methodName: 'glHash',
        namedArguments: false,
        arguments: ['String query'],
        statements: [
          codeGenUtils.constDecl('cached', '_glHashes[query]'),
          codeGenUtils.ifStatement(
              condition: 'cached != null',
              ifBlockStatements: ['return cached;']),
          codeGenUtils.constDecl('hash', 'GraphLinkSha256.hex(query)'),
          '_glHashes[query] = hash;',
          'return hash;',
        ]);
  }

  String _buildResolverBaseClass() {
    return codeGenUtils.createClass(
        className: _resolverBaseClassName,
        statements: [
          'late final $_cacheStoreClassName $svStore;',
          'late final Map<String, GraphLinkLock> $svTagLocks;',
                    'late final Map<String, String> $svFragMap;',
          declareHttpAdapter(),
          if (_parser.persistedQueries) ...[
            'final Map<String, String> _glHashes = {};',
            'bool glPersistedUnsupported__ = false;',
            _buildGlHashMethod(),
            _buildGlSendMethod(),
          ],
          if (_parser.persistedQueriesUseGet) ...[
            'final ${delcareHttpAdapterFunction()} glGetAdapter__;',
            'bool glGetUnsupported__ = false;',
            _buildGlSendHashOnlyMethod(),
          ],
          codeGenUtils.createMethod(
              methodName: _resolverBaseClassName,
              namedArguments: false,
              arguments: [
                '$_cacheStoreClassName store',
                'Map<String, GraphLinkLock> locks',
                'this.$svAdapter',
                if (_parser.persistedQueriesUseGet) 'this.glGetAdapter__',
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
                codeGenUtils.constDecl('buffer', 'StringBuffer(query)'),
                codeGenUtils.forEachLoop(
                    variable: 'name',
                    iterable: 'fragmentNames',
                    statements: [
                      codeGenUtils.constDecl('frag', '$svFragMap[name]'),
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
              statements: _parser.persistedQueries
                  ? _persistedCallAdapterStatements()
                  : [
                      if (_parser.operationNameAsParameter)
                        'return await $svAdapter(json.encode(payload.toJson()), payload.operationName);'
                      else
                        'return await $svAdapter(json.encode(payload.toJson()));'
                    ]),
          codeGenUtils.createMethod(
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
                codeGenUtils.constDecl('fullQuery', 'assembleQuery(query, fragmentNames)'),
                codeGenUtils.constDecl(svPayload, codeGenUtils.callExpression('GraphLinkPayload', ['query: fullQuery', 'operationName: operationName', 'variables: variables'])),
                codeGenUtils.constDecl(svResponse, 'await glCallAdapter($svPayload)'),
                'return fromJson(jsonDecode($svResponse));',
              ]),
          codeGenUtils.createMethod(
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
                codeGenUtils.constDecl(svResult, 'await ${codeGenUtils.callExpression('executeFull<TFull>', ['query', 'fragmentNames', 'operationName', 'variables', 'fromJson'])}'),
                codeGenUtils.ifStatement(
                    condition: '$svResult.errors != null',
                    ifBlockStatements: ['throw $svResult.errors!;']),
                'return $svResult;',
              ]),
          codeGenUtils.createMethod(
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
                codeGenUtils.constDecl(svResponseMap, '<String, dynamic>{}'),
                codeGenUtils.constDecl(svStaleData, '<String, dynamic>{}'),
                codeGenUtils.constDecl(svCacheFetchFutures, '<Future>[]'),
                codeGenUtils.forEachLoop(
                    variable: "partQuery",
                    iterable: "partialQueries.where((e) => e.ttl > 0)",
                    statements: [
                      "$svCacheFetchFutures.add(getFromCache(partQuery.cacheKey!, partQuery.tags, partQuery.staleIfOffline)",
                      ".asStream().where((e) => e != null).map((e) => e!).first.then((entry) ${codeGenUtils.block([
                            codeGenUtils.ifStatement(
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
                codeGenUtils.ifStatement(
                    condition: '$svRemaining.isEmpty',
                    ifBlockStatements: [
                      "return fromJson({'data': $svResponseMap});"
                    ]),
                codeGenUtils.constDecl(svRemainingQueries, "partialQueries.where((e) => !$svResponseMap.containsKey(e.elementKey)).toList()"),
                codeGenUtils.constDecl(svPayload, codeGenUtils.callExpression("_buildPayload", ["$svRemainingQueries", "operationName", "directives"])),
                codeGenUtils.tryCatchFinally(tryStatements: [
                  codeGenUtils.constDecl(svResponseText, 'await glCallAdapter($svPayload)'),
                  'return ${codeGenUtils.callExpression('_parseToObjectAndCache', ['$svResponseText', '$svResponseMap', 'fromJson', '$svRemaining', 'captureErrors'])};',
                ], catchStatements: [
                  "$svResponseMap.addAll($svStaleData);",
                  codeGenUtils.constDecl('remainingCount', 'partialQueries.where((e) => !$svResponseMap.containsKey(e.elementKey)).length'),
                  codeGenUtils.ifStatement(
                      condition: 'remainingCount > 0',
                      ifBlockStatements: ["rethrow;"]),
                  "return fromJson({'data': $svResponseMap});",
                ], catchVariable: 'exception'),
              ]),
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
                codeGenUtils.constDecl("variables", "{}", type: "Map<String, dynamic>"),
                codeGenUtils.forEachLoop(
                    variable: "partQuery",
                    iterable: "partQueries",
                    statements: ["variables.addAll(partQuery.variables);"]),
                codeGenUtils.constDecl('queryBuilder', 'StringBuffer("query \${operationName}")'),
                codeGenUtils.constDecl('args', 'partQueries.expand((e) => e.argumentDeclarations).toSet()'),
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
                codeGenUtils.constDecl('fragments', 'partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => $svFragMap[fragName]!).join()'),
                'queryBuilder.write(fragments);',
                'return ${codeGenUtils.callExpression('GraphLinkPayload', ['query: queryBuilder.toString()', 'operationName: operationName', 'variables: variables'])};',
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
                codeGenUtils.constDecl('result', 'jsonDecode(data) as Map<String, dynamic>'),
                codeGenUtils.constDecl('rawData', 'result["data"]'),
                codeGenUtils.constDecl('dataMap', 'rawData as Map<String, dynamic>? ?? <String, dynamic>{}'),
                codeGenUtils.forEachLoop(
                    variable: 'q',
                    iterable: 'remainingQueries',
                    statements: [
                      codeGenUtils.ifStatement(
                          condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
                          ifBlockStatements: [
                            codeGenUtils.constDecl('entry', 'GraphLinkCacheEntry(jsonEncode(dataMap[q.elementKey]), DateTime.now().millisecondsSinceEpoch + q.ttl * 1000)'),
                            '$svStore.set(q.cacheKey!, jsonEncode(entry.toJson()));',
                            codeGenUtils.ifStatement(
                                condition: 'q.tags.isNotEmpty',
                                ifBlockStatements: [
                                  'addKeyToTags(q.cacheKey!, q.tags);',
                                ]),
                          ])
                    ]),
                'dataMap.addAll(cachedResponse);',
                codeGenUtils.constDecl("fullResponse", "<String, dynamic>{'data': rawData != null ? dataMap : null}"),
                codeGenUtils.ifStatement(
                    condition: 'result["errors"] != null',
                    ifBlockStatements: [
                      'fullResponse["errors"] = result["errors"];',
                    ]),
                codeGenUtils.constDecl('parsed', 'parser.call(fullResponse)'),
                codeGenUtils.ifStatement(
                    condition: 'captureErrors',
                    ifBlockStatements: ['return parsed;']),
                codeGenUtils.constDecl('errors', 'result["errors"] as List?'),
                codeGenUtils.ifStatement(
                    condition: 'errors != null && errors.isNotEmpty',
                    ifBlockStatements: ['throw parsed.errors!;']),
                'return parsed;',
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
                      codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      codeGenUtils.constDecl('lock', '$svTagLocks[tag]!'),
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
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
                      codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      codeGenUtils.constDecl('lock', '$svTagLocks[tag]!'),
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        codeGenUtils.constDecl('entry', 'data != null ? GraphLinkTagEntry.decode(data) : GraphLinkTagEntry({})'),
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
                      codeGenUtils.constDecl('tagKey', '"\${tagKeyPrefix}\${tag}"'),
                      codeGenUtils.constDecl('lock', '$svTagLocks.putIfAbsent(tag, () => GraphLinkLock())'),
                      'await lock.synchronized(() async',
                      codeGenUtils.block([
                        codeGenUtils.constDecl('data', 'await $svStore.get(tagKey)'),
                        codeGenUtils.ifStatement(
                            condition: "data != null",
                            ifBlockStatements: [
                              codeGenUtils.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
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
    final restOperations = _restOperations(type);
    final methods = [
      ...buildOperationMethods(type),
      ...restOperations.map(_restSer.operationToMethod),
    ];
    if (methods.isEmpty) return null;

    return codeGenUtils.createClass(
        className:
            "${classNameFromType(type)} extends $_resolverBaseClassName${restOperations.isEmpty ? '' : ' with $_restResolverMixinName'}",
        statements: [
          _declareOperationFields(type),
          codeGenUtils.createConstructor(
              className: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              superArguments: [
                'store',
                svTagLocks,
                'httpAdapter',
                if (_parser.persistedQueriesUseGet) 'getAdapter',
                'fragmentMap',
              ],
              statements: [
                if (type == GLQueryType.subscription)
                  '$svHandler = GraphLinkSubscriptionHandler(adapter);',
              ]),
          ...methods,
        ]);
  }

  String _buildGraphLinkClientClass() {
    return codeGenUtils.createClass(className: 'GraphLinkClient', statements: [
      codeGenUtils.constDecl(svFragMap, '<String, String>{}'),
      codeGenUtils.constDecl(svTagLocks, '<String, GraphLinkLock>{}'),
      if (_hasQueries)
        'late final ${classNameFromType(GLQueryType.query)} queries;',
      if (_hasMutations)
        'late final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_parser.hasSubscriptions)
        'late final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      'late final $_cacheStoreClassName store;',
      codeGenUtils.createMethod(
        methodName: 'GraphLinkClient',
        arguments: [
          if (_hasGraphQL) 'required ${_adapterDeclaration()}' else '${_adapterDeclaration()} = glNoGraphQL__',
          if (_parser.persistedQueriesUseGet) 'required ${_getAdapterDeclaration()}',
          if (_parser.hasUploadMutations) ...[
            'GLUploadConverter uploadConverter = defaultUploadConverter',
            'GLMultipartAdapter? uploadAdapter',
          ],
          if (_parser.hasSubscriptions) 'required GraphLinkWebSocketAdapter wsAdapter',
          if (_hasRest) 'required GLRestAdapter restAdapter',
          '$_cacheStoreClassName? store'
        ],
        namedArguments: true,
        statements: [
          ..._parser.usedFragments
              .where((value) => !oversizedFragmentNames.contains(value.tokenInfo.token))
              .map((value) =>
                  "$svFragMap['${value.tokenInfo}'] = '${gqlSerializer.serializeFragmentDefinitionBase(value)}';"),
          'this.store = store ?? $_inMemorycacheStoreClassName();',
          codeGenUtils.constDecl('tags', '${_parser.getAllCacheTags().map((e) => e.quote()).toList()}'),
          codeGenUtils.forEachLoop(
              variable: 'tag',
              iterable: 'tags',
              statements: ['$svTagLocks[tag] = GraphLinkLock();']),
          if (_hasQueries)
            "queries = ${classNameFromType(GLQueryType.query)}(adapter, $_getArg$svFragMap, this.store, $svTagLocks);",
          if (_hasMutations)
            _parser.hasUploadMutations
                ? "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, ${_getArg}uploadConverter, uploadAdapter, $svFragMap, this.store, $svTagLocks);"
                : "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, $_getArg$svFragMap, this.store, $svTagLocks);",
          if (_parser.hasSubscriptions)
            "subscriptions = ${classNameFromType(GLQueryType.subscription)}(adapter, $_getArg${'wsAdapter'}, $svFragMap, this.store, $svTagLocks);",
          for (final type in [GLQueryType.query, GLQueryType.mutation])
            if (_restOperations(type).isNotEmpty)
              '${type == GLQueryType.query ? 'queries' : 'mutations'}.restAdapter = restAdapter;',
        ],
      ),
      if (_parser.hasSubscriptions &&
          generateAdapters &&
          httpAdapter != DartHttpAdapter.none)
        _fromUrlConstructor(),
      if (_generatesWithHttp) _withHttpConstructor(),
    ]);
  }

  // ── Constructor / adapter helpers ──────────────────────────────────────────

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      '${delcareHttpAdapterFunction()} httpAdapter',
      if (_parser.persistedQueriesUseGet) '${delcareHttpAdapterFunction()} getAdapter',
      if (type == GLQueryType.subscription) 'GraphLinkWebSocketAdapter adapter',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
        'this.$svUploadConverter',
        'this.$svUploadAdapter',
      ],
      'Map<String, String> fragmentMap',
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

  String get _getArg => _parser.persistedQueriesUseGet ? 'getAdapter, ' : '';

  String _getAdapterDeclaration() {
    if (_parser.operationNameAsParameter) {
      return 'Future<String> Function(String payload, String $_operationNameParam) getAdapter';
    }
    return 'Future<String> Function(String payload) getAdapter';
  }

  String _adapterDeclaration() {
    if (_parser.operationNameAsParameter) {
      return 'Future<String> Function(String payload, String $_operationNameParam) adapter';
    }
    return 'Future<String> Function(String payload) adapter';
  }

  String _withHttpConstructor() {
    final hasSubscriptions = _parser.hasSubscriptions;
    final adapterClass = _useDio ? 'GraphLinkDioAdapter' : 'GraphLinkHttpAdapter';
    const adapterArgs = 'url: url, headersProvider: headersProvider';
    final restAdapterClass = _useRestDio ? 'GraphLinkRestDioAdapter' : 'GraphLinkRestHttpAdapter';
    final generatesRestAdapter = restHttpAdapter != DartHttpAdapter.none;
    final restArg = !_hasRest
        ? null
        : generatesRestAdapter
            ? 'restAdapter: $restAdapterClass(baseUrl: restBaseUrl, headersProvider: headersProvider).call'
            : 'restAdapter: restAdapter';
    final wsArgs = hasSubscriptions
        ? ['wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider)']
        : <String>[];
    final constructorArgs = [
      if (_hasGraphQL) 'required String url',
      if (_hasRest) generatesRestAdapter ? 'required String restBaseUrl' : 'required GLRestAdapter restAdapter',
      if (hasSubscriptions) ...[
        'required String wsUrl',
        'Future<Map<String, String>?> Function()? wsHeadersProvider',
      ],
      'Future<Map<String, String>?> Function()? headersProvider',
      '$_cacheStoreClassName? store',
    ];

    if (_parser.hasUploadMutations || _parser.persistedQueriesUseGet) {
      return codeGenUtils.createMethod(
        returnType: 'factory',
        methodName: 'GraphLinkClient.withHttp',
        arguments: constructorArgs,
        statements: [
          codeGenUtils.constDecl('_a', '$adapterClass($adapterArgs)'),
          'return ${codeGenUtils.callExpression('GraphLinkClient', [
            'adapter: _a.call',
            if (restArg != null) restArg,
            if (_parser.persistedQueriesUseGet) 'getAdapter: _a.getCall',
            if (_parser.hasUploadMutations) ...[
              'uploadConverter: defaultUploadConverter',
              'uploadAdapter: _a.multipartCall',
            ],
            ...wsArgs,
            'store: store',
          ])};',
        ],
      );
    }

    return codeGenUtils.createMethod(
      methodName: 'GraphLinkClient.withHttp',
      arguments: constructorArgs,
      initializers: [
        codeGenUtils.callExpression('this', [
          if (_hasGraphQL) 'adapter: $adapterClass($adapterArgs).call',
          if (restArg != null) restArg,
          ...wsArgs,
          'store: store',
        ]),
      ],
    );
  }

  String _fromUrlConstructor() {
    return codeGenUtils.createMethod(
      methodName: 'GraphLinkClient.fromUrl',
      arguments: [
        'required ${_adapterDeclaration()}',
        if (_parser.persistedQueriesUseGet) 'required ${_getAdapterDeclaration()}',
        'required String wsUrl',
        'Future<Map<String, String>?> Function()? wsHeadersProvider',
        if (_hasRest) 'required GLRestAdapter restAdapter',
        '$_cacheStoreClassName? store',
      ],
      initializers: [
        codeGenUtils.callExpression('this', [
          'adapter: adapter',
          if (_hasRest) 'restAdapter: restAdapter',
          if (_parser.persistedQueriesUseGet) 'getAdapter: getAdapter',
          'wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider)',
          'store: store',
        ]),
      ],
    );
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

  String get _operationNameArg => _parser.operationNameAsParameter ? ', String operationName' : '';

  String get _postUrlExpr => _parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url';

  GLClassModel generateHttpAdapterFile() {
    if (_parser.hasUploadMutations) {
      stdout.writeln(
        '⚠️  Upload mutations detected with the http adapter.\n'
        '   Progress tracking buffers the entire request body in memory.\n'
        '   For large files, consider switching to the Dio adapter (httpAdapter: "dio").',
      );
    }
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'package:http/http.dart' as http;",
        "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
        if (_parser.persistedQueriesUseGet) "import 'graph_link_persisted_queries.dart';",
      ],
      body: codeGenUtils.createClass(
        className: 'GraphLinkHttpAdapter',
        statements: [
          'final String url;',
          'final Future<Map<String, String>?> Function()? headersProvider;',
          codeGenUtils.createMethod(
            methodName: 'GraphLinkHttpAdapter',
            arguments: ['required this.url', 'this.headersProvider'],
          ),
          codeGenUtils.createMethod(
            returnType: 'Future<String>',
            methodName: 'call',
            async: true,
            namedArguments: false,
            arguments: ['String payload$_operationNameArg'],
            statements: [
              codeGenUtils.constDecl('extraHeaders', 'await headersProvider?.call()'),
              codeGenUtils.constDecl("requestHeaders", codeGenUtils.block([
                "'Content-Type': 'application/json',",
                'if (extraHeaders != null) ...extraHeaders,',
              ])),
              codeGenUtils.constDecl('response', 'await ${codeGenUtils.callExpression('http.post', [
                'Uri.parse($_postUrlExpr)',
                'body: payload',
                'headers: requestHeaders',
              ])}'),
              'return response.body;',
            ],
          ),
          if (_parser.persistedQueriesUseGet) _httpGetMethod(),
          if (_parser.hasUploadMutations) _httpMultipartMethod(),
        ],
      ),
    );
  }

  String _httpGetMethod() {
    return codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'getCall',
      async: true,
      namedArguments: false,
      arguments: ['String payload$_operationNameArg'],
      statements: [
        codeGenUtils.constDecl('uri', 'Uri.parse(url)'),
        codeGenUtils.constDecl('response', 'await ${codeGenUtils.callExpression('http.get', [
          'uri.replace(queryParameters: {...uri.queryParameters, ...GraphLinkGetRequest.queryParameters(payload)})',
          'headers: await headersProvider?.call()',
        ])}'),
        codeGenUtils.ifStatement(
          condition: 'response.statusCode == 405',
          ifBlockStatements: ["throw const GraphLinkGetNotSupported('GET is not allowed');"],
        ),
        'return response.body;',
      ],
    );
  }

  String _httpMultipartMethod() {
    final addPart = codeGenUtils.ifStatement(
      condition: 'entry.value is GLUpload',
      ifBlockStatements: [
        codeGenUtils.constDecl('u', 'entry.value as GLUpload'),
        'request.files.add(${codeGenUtils.callExpression('http.MultipartFile', [
          'entry.key, u.stream, u.length ?? 0',
          'filename: u.filename',
          'contentType: MediaType.parse(u.mimeType)',
        ])});',
      ],
      elseBlockStatements: ['request.fields[entry.key] = entry.value as String;'],
    );
    final countedStream = 'final counted = Stream.fromIterable([\n'
        '  for (var i = 0; i < bodyBytes.length; i += chunkSize)\n'
        '    bodyBytes.sublist(i, (i + chunkSize).clamp(0, bodyBytes.length)),\n'
        ']).map(${codeGenUtils.functionLiteral(['chunk'], [
      'sent += chunk.length;',
      'onProgress(sent, total);',
      'return chunk;',
    ])});';
    return codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'multipartCall',
      async: true,
      namedArguments: false,
      arguments: ['Map<String, Object> parts', 'UploadProgressCallback? onProgress'],
      statements: [
        codeGenUtils.constDecl("request", "http.MultipartRequest('POST', Uri.parse(url))"),
        codeGenUtils.constDecl('extraHeaders', 'await headersProvider?.call() ?? {}'),
        'request.headers.addAll(extraHeaders);',
        codeGenUtils.forEachLoop(variable: 'entry', iterable: 'parts.entries', statements: [addPart]),
        codeGenUtils.ifStatement(
          condition: 'onProgress == null',
          ifBlockStatements: [
            codeGenUtils.constDecl('streamed', 'await request.send()'),
            'return (await http.Response.fromStream(streamed)).body;',
          ],
        ),
        codeGenUtils.constDecl('bodyBytes', 'await request.finalize().toBytes()'),
        codeGenUtils.constDecl('total', 'bodyBytes.length'),
        'int sent = 0;',
        'const chunkSize = 8192;',
        countedStream,
        codeGenUtils.constDecl("raw", "http.StreamedRequest('POST', Uri.parse(url))"),
        'raw.headers.addAll(extraHeaders);',
        "raw.headers['content-type'] = request.headers['content-type']!;",
        'raw.contentLength = total;',
        'counted.listen(raw.sink.add, onDone: raw.sink.close);',
        codeGenUtils.constDecl('streamed', 'await raw.send()'),
        'return (await http.Response.fromStream(streamed)).body;',
      ],
    );
  }

  GLClassModel generateDioAdapterFile() {
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'dart:convert';",
        "import 'package:dio/dio.dart';",
        if (_parser.hasUploadMutations) "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
        if (_parser.persistedQueriesUseGet) "import 'graph_link_persisted_queries.dart';",
      ],
      body: [
        _dioAdapterClass(),
        _dioHeadersInterceptorClass(),
      ].join('\n\n'),
    );
  }

  String _dioAdapterClass() {
    return codeGenUtils.createClass(
      className: 'GraphLinkDioAdapter',
      statements: [
        'final String url;',
        'final Dio dio;',
        codeGenUtils.createMethod(
          methodName: 'GraphLinkDioAdapter',
          arguments: [
            'required this.url',
            'Dio? dio',
            'Future<Map<String, String>?> Function()? headersProvider',
            'List<Interceptor> interceptors = const []',
            'BaseOptions? options',
          ],
          initializers: ["dio = dio ?? Dio(options ?? BaseOptions(contentType: 'application/json'))"],
          statements: [
            codeGenUtils.ifStatement(
              condition: 'dio == null',
              ifBlockStatements: [
                codeGenUtils.ifStatement(
                  condition: 'headersProvider != null',
                  ifBlockStatements: ['this.dio.interceptors.add(_HeadersInterceptor(headersProvider));'],
                ),
                'this.dio.interceptors.addAll(interceptors);',
              ],
            ),
          ],
        ),
        codeGenUtils.createMethod(
          returnType: 'Future<String>',
          methodName: 'call',
          async: true,
          namedArguments: false,
          arguments: ['String payload$_operationNameArg'],
          statements: [
            codeGenUtils.constDecl('response', 'await dio.post<dynamic>($_postUrlExpr, data: payload)'),
            codeGenUtils.constDecl('data', 'response.data'),
            'return data is String ? data : jsonEncode(data);',
          ],
        ),
        if (_parser.persistedQueriesUseGet) _dioGetMethod(),
        if (_parser.hasUploadMutations) _dioMultipartMethod(),
      ],
    );
  }

  String _dioGetMethod() {
    return codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'getCall',
      async: true,
      namedArguments: false,
      arguments: ['String payload$_operationNameArg'],
      statements: [
        codeGenUtils.tryCatchFinally(
          tryStatements: [
            codeGenUtils.constDecl('response',
                'await dio.get<dynamic>(url, queryParameters: GraphLinkGetRequest.queryParameters(payload))'),
            codeGenUtils.constDecl('data', 'response.data'),
            'return data is String ? data : jsonEncode(data);',
          ],
          catchVariable: 'e',
          catchStatements: [
            codeGenUtils.ifStatement(
              condition: 'e is DioException && e.response?.statusCode == 405',
              ifBlockStatements: ["throw const GraphLinkGetNotSupported('GET is not allowed');"],
            ),
            'rethrow;',
          ],
        ),
      ],
    );
  }

  String _dioMultipartMethod() {
    final convertPart = codeGenUtils.ifStatement(
      condition: 'entry.value is GLUpload',
      ifBlockStatements: [
        codeGenUtils.constDecl('u', 'entry.value as GLUpload'),
        'converted[entry.key] = ${codeGenUtils.callExpression('MultipartFile', [
          'u.stream, u.length ?? 0',
          'filename: u.filename',
          'contentType: u.mimeType.isNotEmpty ? MediaType.parse(u.mimeType) : null',
        ])};',
      ],
      elseBlockStatements: ['converted[entry.key] = entry.value;'],
    );
    return codeGenUtils.createMethod(
      returnType: 'Future<String>',
      methodName: 'multipartCall',
      async: true,
      namedArguments: false,
      arguments: ['Map<String, Object> parts', 'UploadProgressCallback? onProgress'],
      statements: [
        codeGenUtils.constDecl('converted', '<String, dynamic>{}'),
        codeGenUtils.forEachLoop(variable: 'entry', iterable: 'parts.entries', statements: [convertPart]),
        codeGenUtils.constDecl('formData', 'FormData.fromMap(converted)'),
        codeGenUtils.constDecl('response', 'await ${codeGenUtils.callExpression('dio.post<dynamic>', [
          'url',
          'data: formData',
          'onSendProgress: onProgress != null ? (sent, total) => onProgress(sent, total) : null',
        ])}'),
        codeGenUtils.constDecl('data', 'response.data'),
        'return data is String ? data : jsonEncode(data);',
      ],
    );
  }

  String _dioHeadersInterceptorClass() {
    return codeGenUtils.createClass(
      className: '_HeadersInterceptor',
      extendsClassName: 'Interceptor',
      statements: [
        'final Future<Map<String, String>?> Function() _headersProvider;',
        codeGenUtils.createMethod(
          methodName: '_HeadersInterceptor',
          namedArguments: false,
          arguments: ['this._headersProvider'],
        ),
        codeGenUtils.createMethod(
          override: true,
          returnType: 'Future<void>',
          methodName: 'onRequest',
          async: true,
          namedArguments: false,
          arguments: ['RequestOptions options', 'RequestInterceptorHandler handler'],
          statements: [
            codeGenUtils.constDecl('headers', 'await _headersProvider()'),
            codeGenUtils.ifStatement(
              condition: 'headers != null',
              ifBlockStatements: ['options.headers.addAll(headers);'],
            ),
            'handler.next(options);',
          ],
        ),
      ],
    );
  }

  GLClassModel generateUploadConverterFile() => const GLClassModel(
        imports: ["import 'graph_link_uploads.dart';"],
        body: dartUploadDefaultConverter,
      );

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: dartUploadsFile);

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

  GLClassModel generateRestHttpAdapterFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:typed_data';",
          "import 'package:http/http.dart' as http;",
          "import 'package:http_parser/http_parser.dart';",
          "import 'graph_link_rest.dart';",
          "import 'graph_link_uploads.dart';",
        ],
        body: dartRestHttpAdapter,
      );

  GLClassModel generateRestDioAdapterFile() => const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:typed_data';",
          "import 'package:dio/dio.dart';",
          "import 'package:http_parser/http_parser.dart';",
          "import 'graph_link_rest.dart';",
        ],
        body: dartRestDioAdapter,
      );

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
