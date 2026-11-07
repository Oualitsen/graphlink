import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
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
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_runtime_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_adapters_serializer.dart';

const _operationNameParam = "operationName";
const cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';
const resolverBaseClassName = 'GraphLinkResolverBase';
const _restResolverMixinName = 'GraphLinkRestResolver';

class DartClientSerializer extends GLClientSerializer {
  late final runtime = DartClientRuntimeSerializer(this);
  late final adapters = DartClientAdaptersSerializer(this);

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
        super(dartSerializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = DartClientOperationSerializer(
        _parser, codeGenUtils, gqlSerializer, serializer);
    _restSer = DartRestOperationSerializer(_parser, codeGenUtils, serializer,
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

    buffer.writeln(runtime.buildResolverBaseClass());
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

  /// Returns the standalone [GraphLinkQueries] file, or null if no queries.
  @override
  GLClassModel? getQueriesClass() {
    final body = _buildOperationClass(GLQueryType.query);
    if (body == null) return null;
    return GLClassModel(
      imports: _importsForType(GLQueryType.query),
      importDepencies: _tokensForType(GLQueryType.query),
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
      importDepencies: _tokensForType(GLQueryType.mutation),
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
      importDepencies: _tokensForType(GLQueryType.subscription),
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
    return {
      if (type != GLQueryType.subscription) "import 'dart:convert';",
      "import 'dart:async';",
      "import 'graph_link_cache_store.dart';",
      "import 'graph_link_lock.dart';",
      "import 'graph_link_resolver_base.dart';",
      if (type == GLQueryType.query) ...[
        "import 'graph_link_cache_entry.dart';",
        "import 'graph_link_partial_query.dart';",
      ],
      if (type == GLQueryType.mutation && _parser.hasUploadMutations)
        "import 'graph_link_uploads.dart';",
      if (type == GLQueryType.subscription) ...[
        "import 'graph_link_subscription_handler.dart';",
        "import 'graph_link_websocket_adapter.dart';",
      ],
      ..._restImportsFor(type),
      ..._parser.scalarImportsOfOperationType(type),
    }.toList();
  }

  List<GLToken> _tokensForType(GLQueryType type) => {
        if (type == GLQueryType.query) _parser.getTokenByKey('GraphLinkFullResponse')!,
        ...schemaTokensFor(type),
        ..._restTokensFor(type),
      }.toList();

  List<GLToken> _restTokensFor(GLQueryType type) {
    final operations = _restOperations(type);
    final tokens = <GLToken>[];
    for (final operation in operations) {
      final names = [
        operation.field.type.firstType.token,
        ...operation.arguments.map((a) => a.argument.type.firstType.token),
      ];
      for (final name in names) {
        if (_parser.isRestImportableType(name)) {
          final token = _parser.getTokenByKey(name);
          if (token != null) tokens.add(token);
        }
      }
    }
    return tokens;
  }

  List<String> _restImportsFor(GLQueryType type) {
    final operations = _restOperations(type);
    if (operations.isEmpty) return const [];
    final uploads = _parser.uploadScalarNames;
    final usesUploads =
        operations.any((o) => o.arguments.any((a) => uploads.contains(a.argument.type.firstType.token)));
    return [
      "import 'graph_link_rest.dart';",
      "import 'graph_link_rest_resolver.dart';",
      if (usesUploads && !(type == GLQueryType.mutation && _parser.hasUploadMutations))
        "import 'graph_link_uploads.dart';",
    ];
  }

  // ── Generated class builders ───────────────────────────────────────────────

  String? _buildOperationClass(GLQueryType type) {
    final restOperations = _restOperations(type);
    final methods = [
      ...buildOperationMethods(type),
      ...restOperations.map(_restSer.operationToMethod),
    ];
    if (methods.isEmpty) return null;

    return codeGenUtils.createClass(
        className:
            "${classNameFromType(type)} extends $resolverBaseClassName${restOperations.isEmpty ? '' : ' with $_restResolverMixinName'}",
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
      'late final $cacheStoreClassName store;',
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
          '$cacheStoreClassName? store'
        ],
        namedArguments: true,
        statements: [
          ..._parser.usedFragments
              .where((value) => !oversizedFragmentNames.contains(value.tokenInfo.token))
              .map((value) =>
                  "$svFragMap['${value.tokenInfo}'] = ${serializer.stringLiteral(gqlSerializer.serializeFragmentDefinitionBase(value))};"),
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
      '$cacheStoreClassName store',
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
      '$cacheStoreClassName? store',
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
        '$cacheStoreClassName? store',
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

  String get fileExtension => '.dart';

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: dartUploadsFile);

  GLParser get parser => _parser;
}
