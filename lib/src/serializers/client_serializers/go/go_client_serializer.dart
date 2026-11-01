import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/go_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_fragment_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_vars.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/go_serializer.dart';

class GoClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final GoHttpAdapter httpAdapter;
  final GoWsAdapter wsAdapter;
  final codeGenUtils = GoCodeGenUtils();
  late final GoClientOperationSerializer _opSer;

  GoClientSerializer(
    this._parser,
    GoSerializer serializer, {
    this.httpAdapter = GoHttpAdapter.nethttp,
    this.wsAdapter = GoWsAdapter.coder,
  }) : super(serializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = GoClientOperationSerializer(_parser, codeGenUtils, gqlSerializer, serializer);
  }

  GoSerializer get _go => serializer as GoSerializer;

  bool get _hasHttp => httpAdapter == GoHttpAdapter.nethttp;
  bool get _hasDefaultWs => wsAdapter == GoWsAdapter.coder;
  bool get _hasUploads => _parser.hasMutations && _parser.hasUploadMutations;

  @override
  String renderQueryMethod(def) => _opSer.operationMethod(def);

  @override
  String renderMutationMethod(def) => _opSer.operationMethod(def);

  @override
  String renderUploadMutationMethod(def) => _opSer.operationMethod(def);

  @override
  String renderSubscriptionMethod(def) => _opSer.operationMethod(def);

  // ── Runtime files ──────────────────────────────────────────────────────────

  GLClassModel generateUtilFile() => const GLClassModel(body: goUtil);

  GLClassModel generateExceptionFile() => const GLClassModel(body: goException);

  GLClassModel generateCacheFile() => const GLClassModel(body: goCache);

  GLClassModel generatePartialQueryFile() => const GLClassModel(body: goPartialQuery);

  GLClassModel generateResolverBaseFile() => GLClassModel(
        body: goResolverBase(
          operationNameAsParameter: _parser.operationNameAsParameter,
          persistedQueries: _parser.persistedQueries,
        ),
      );

  GLClassModel generatePersistedQueriesFile() => GLClassModel(
        body: goPersistedQueries(
          operationNameAsParameter: _parser.operationNameAsParameter,
          useGet: _parser.persistedQueriesUseGet,
        ),
      );

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: '$goUploads\n$goUploadDefaultConverter');

  GLClassModel generateHttpAdapterFile() => GLClassModel(
        body: goHttpAdapter(
          operationNameAsParameter: _parser.operationNameAsParameter,
          useGet: _parser.persistedQueriesUseGet,
          hasUploads: _hasUploads,
        ),
      );

  GLClassModel generateWsMessageTypesFile() => const GLClassModel(body: goWsMessageTypes);

  GLClassModel generateWsAdapterFile() => const GLClassModel(body: goWebSocketAdapter);

  GLClassModel generateSubscriptionHandlerFile() => const GLClassModel(body: goSubscriptionHandler);

  GLClassModel generateDefaultWebSocketAdapterFile() => const GLClassModel(body: goDefaultWebSocketAdapter);

  // ── Operation classes ──────────────────────────────────────────────────────

  String _className(GLQueryType type) => classNameFromType(type);

  String _constructorParams(GLQueryType type) => [
        'adapter, getAdapter GraphLinkAdapter',
        'fragments map[string]string',
        'store GraphLinkCacheStore',
        'locks *GraphLinkTagLocks',
        if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
          'uploadConverter GLUploadConverter',
          'uploadAdapter GLMultipartAdapter',
        ],
        if (type == GLQueryType.subscription) 'handler *GraphLinkSubscriptionHandler',
      ].join(', ');

  String? _buildOperationClass(GLQueryType type) {
    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;
    final name = _className(type);
    final fields = [
      'GraphLinkResolverBase',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
        '$svUploadConverter GLUploadConverter',
        '$svUploadAdapter GLMultipartAdapter',
      ],
      if (type == GLQueryType.subscription) '$svHandler *GraphLinkSubscriptionHandler',
    ];
    final constructor = codeGenUtils.createMethod(
      methodName: 'new$name',
      arguments: [_constructorParams(type)],
      returnType: '*$name',
      statements: [
        'result := &$name{}',
        'result.init(store, locks, adapter, getAdapter, fragments)',
        if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
          'result.$svUploadConverter = uploadConverter',
          'result.$svUploadAdapter = uploadAdapter',
        ],
        if (type == GLQueryType.subscription) 'result.$svHandler = handler',
        'return result',
      ],
    );
    return [
      codeGenUtils.structDecl(name, [fields.join('\n')]),
      constructor,
      ...methods,
    ].join('\n\n');
  }

  @override
  GLClassModel? getQueriesClass() => _classModel(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() => _classModel(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() => _classModel(GLQueryType.subscription);

  GLClassModel? _classModel(GLQueryType type) {
    final body = _buildOperationClass(type);
    return body == null ? null : GLClassModel(body: body);
  }

  // ── Client ─────────────────────────────────────────────────────────────────

  @override
  GLClassModel generateClient() => generateClientFile();

  GLClassModel generateClientFile() {
    final hasSubs = _parser.hasSubscriptions;
    final useGet = _parser.persistedQueriesUseGet;
    final options = codeGenUtils.structDecl('GraphLinkClientOptions', [
      [
        'Adapter GraphLinkAdapter',
        if (useGet) 'GetAdapter GraphLinkAdapter',
        if (_hasUploads) ...[
          'UploadConverter GLUploadConverter',
          'UploadAdapter GLMultipartAdapter',
        ],
        if (hasSubs) 'WsAdapter GraphLinkWebSocketAdapter',
        'Store GraphLinkCacheStore',
      ].join('\n'),
    ]);
    final client = codeGenUtils.structDecl('GraphLinkClient', [
      [
        if (_parser.hasQueries) 'Queries *GraphLinkQueries',
        if (_parser.hasMutations) 'Mutations *GraphLinkMutations',
        if (hasSubs) 'Subscriptions *GraphLinkSubscriptions',
        'Store GraphLinkCacheStore',
      ].join('\n'),
    ]);
    return GLClassModel(
      body: [
        options,
        client,
        _newClient(),
        if (_hasHttp) _httpOptions(),
        if (_hasHttp) _newClientWithHttp(),
      ].join('\n\n'),
    );
  }

  String _newClient() {
    final hasSubs = _parser.hasSubscriptions;
    final useGet = _parser.persistedQueriesUseGet;
    final fragments = _parser.usedFragments
        .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
        .map((f) =>
            '${_go.stringLiteral(f.tokenInfo.token)}: ${_go.stringLiteral(gqlSerializer.serializeFragmentDefinitionBase(f))},')
        .join('\n');
    final tags = _parser.getAllCacheTags().map(_go.stringLiteral).join(', ');
    final getAdapterArg = useGet ? 'opts.GetAdapter' : 'nil';
    return codeGenUtils.createMethod(
      methodName: 'NewGraphLinkClient',
      arguments: ['opts GraphLinkClientOptions'],
      returnType: '(*GraphLinkClient, error)',
      statements: [
        codeGenUtils.inlineIfStatement(
          condition: 'opts.Adapter == nil',
          statement: 'return nil, errors.New("GraphLinkClientOptions.Adapter is required")',
        ),
        if (useGet)
          codeGenUtils.inlineIfStatement(
            condition: 'opts.GetAdapter == nil',
            statement: 'return nil, errors.New("GraphLinkClientOptions.GetAdapter is required when persistedQueriesUseGet is enabled")',
          ),
        if (hasSubs)
          codeGenUtils.inlineIfStatement(
            condition: 'opts.WsAdapter == nil',
            statement: 'return nil, errors.New("GraphLinkClientOptions.WsAdapter is required")',
          ),
        'store := opts.Store',
        codeGenUtils.inlineIfStatement(condition: 'store == nil', statement: 'store = NewInMemoryGraphLinkCacheStore()'),
        if (_hasUploads) ...[
          'uploadConverter := opts.UploadConverter',
          codeGenUtils.inlineIfStatement(condition: 'uploadConverter == nil', statement: 'uploadConverter = DefaultUploadConverter'),
        ],
        'fragments := map[string]string{${fragments.isEmpty ? '' : '\n${fragments.identGo()}\n'}}',
        'locks := NewGraphLinkTagLocks([]string{$tags})',
        'client := &GraphLinkClient{Store: store}',
        if (_parser.hasQueries)
          'client.Queries = newGraphLinkQueries(opts.Adapter, $getAdapterArg, fragments, store, locks)',
        if (_parser.hasMutations)
          'client.Mutations = newGraphLinkMutations(opts.Adapter, $getAdapterArg, fragments, store, locks${_hasUploads ? ', uploadConverter, opts.UploadAdapter' : ''})',
        if (hasSubs)
          'client.Subscriptions = newGraphLinkSubscriptions(opts.Adapter, $getAdapterArg, fragments, store, locks, NewGraphLinkSubscriptionHandler(opts.WsAdapter))',
        'return client, nil',
      ],
    );
  }

  String _httpOptions() {
    return codeGenUtils.structDecl('GraphLinkHttpOptions', [
      [
        'URL string',
        if (_parser.hasSubscriptions && _hasDefaultWs) ...[
          'WsURL string',
          'WsHeadersProvider func(ctx context.Context) (map[string]string, error)',
        ],
        if (_parser.hasSubscriptions && !_hasDefaultWs) 'WsAdapter GraphLinkWebSocketAdapter',
        'HeadersProvider func(ctx context.Context) (map[string]string, error)',
        'HTTPClient *http.Client',
        'Store GraphLinkCacheStore',
      ].join('\n'),
    ]);
  }

  String _newClientWithHttp() {
    final hasSubs = _parser.hasSubscriptions;
    return codeGenUtils.createMethod(
      methodName: 'NewGraphLinkClientWithHttp',
      arguments: ['opts GraphLinkHttpOptions'],
      returnType: '(*GraphLinkClient, error)',
      statements: [
        'adapter := NewGraphLinkHttpAdapter(opts.URL)',
        'adapter.HeadersProvider = opts.HeadersProvider',
        codeGenUtils.inlineIfStatement(condition: 'opts.HTTPClient != nil', statement: 'adapter.Client = opts.HTTPClient'),
        'clientOptions := GraphLinkClientOptions{Adapter: adapter.Call, Store: opts.Store}',
        if (_parser.persistedQueriesUseGet) 'clientOptions.GetAdapter = adapter.GetCall',
        if (_hasUploads) ...[
          'clientOptions.UploadConverter = DefaultUploadConverter',
          'clientOptions.UploadAdapter = adapter.MultipartCall',
        ],
        if (hasSubs && _hasDefaultWs) ...[
          'ws := NewDefaultGraphLinkWebSocketAdapter(opts.WsURL)',
          'ws.HeadersProvider = opts.WsHeadersProvider',
          'clientOptions.WsAdapter = ws',
        ],
        if (hasSubs && !_hasDefaultWs) 'clientOptions.WsAdapter = opts.WsAdapter',
        'return NewGraphLinkClient(clientOptions)',
      ],
    );
  }
}
