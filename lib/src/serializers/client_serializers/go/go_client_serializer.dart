import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/go_code_gen_utils.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_client_vars.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/go/go_rest_operation_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/go/go_serializer.dart';

class GoClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final GoHttpAdapter httpAdapter;
  final GoWsAdapter wsAdapter;
  final GoHttpAdapter restHttpAdapter;
  final codeGenUtils = GoCodeGenUtils();
  late final GoClientOperationSerializer _opSer;
  late final GoRestOperationSerializer _restSer;

  GoClientSerializer(
    this._parser,
    GoSerializer serializer, {
    this.httpAdapter = GoHttpAdapter.nethttp,
    this.wsAdapter = GoWsAdapter.coder,
    this.restHttpAdapter = GoHttpAdapter.nethttp,
    bool commaQueryLists = false,
    bool bracketFormNesting = false,
  }) : super(serializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = GoClientOperationSerializer(_parser, codeGenUtils, gqlSerializer, serializer);
    _restSer = GoRestOperationSerializer(
      _parser,
      codeGenUtils,
      serializer,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _parser.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) => _parser.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get hasRest => _parser.restOperations.isNotEmpty;

  bool get hasGraphQL => GLQueryType.values.any(_parser.hasQueryType);

  bool get _restViaHttp => hasRest && restHttpAdapter == GoHttpAdapter.nethttp;

  bool get generatesRestAdapter => _restViaHttp;

  bool get usesUploadsRuntime => _parser.hasUploadMutations || hasRest;

  GoSerializer get _go => serializer as GoSerializer;

  bool get _hasHttp => httpAdapter == GoHttpAdapter.nethttp;
  bool get _hasDefaultWs => wsAdapter == GoWsAdapter.coder;
  bool get _hasHttpFactory => (hasGraphQL && _hasHttp) || _restViaHttp;

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
  GLClassModel generateUploadsFile() => GLClassModel(
        body: _parser.hasUploadMutations ? '$goUploads\n$goUploadDefaultConverter' : goUploads,
      );

  GLClassModel generateRestFile() => GLClassModel(
        body: '$goRestFile\n${goRestNoGraphQL(_parser.operationNameAsParameter)}',
      );

  GLClassModel generateRestResolverFile() => const GLClassModel(body: goRestResolver);

  GLClassModel generateRestHttpAdapterFile() => const GLClassModel(body: goRestHttpAdapter);

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
        if (_restOperations(type).isNotEmpty) 'restAdapter GLRestAdapter',
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
    final restOperations = _restOperations(type);
    final methods = [...buildOperationMethods(type), ...restOperations.map(_restSer.operationToMethod)];
    if (methods.isEmpty) return null;
    final name = _className(type);
    final fields = [
      restOperations.isEmpty ? 'GraphLinkResolverBase' : 'GraphLinkRestResolver',
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
        if (restOperations.isNotEmpty) 'result.restAdapter = restAdapter',
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
    return body == null ? null : GLClassModel(imports: _parser.scalarImportsOfOperationType(type).map((i) => '"$i"').toList(), body: body);
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
        if (hasRest) 'RestAdapter GLRestAdapter',
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
        if (_hasOperations(GLQueryType.query)) 'Queries *GraphLinkQueries',
        if (_hasOperations(GLQueryType.mutation)) 'Mutations *GraphLinkMutations',
        if (hasSubs) 'Subscriptions *GraphLinkSubscriptions',
        'Store GraphLinkCacheStore',
      ].join('\n'),
    ]);
    return GLClassModel(
      body: [
        options,
        client,
        _newClient(),
        if (_hasHttpFactory) _httpOptions(),
        if (_hasHttpFactory) _newClientWithHttp(),
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
    final adapterArg = hasGraphQL ? 'opts.Adapter' : 'adapter';
    return codeGenUtils.createMethod(
      methodName: 'NewGraphLinkClient',
      arguments: ['opts GraphLinkClientOptions'],
      returnType: '(*GraphLinkClient, error)',
      statements: [
        if (hasGraphQL)
          codeGenUtils.inlineIfStatement(
            condition: 'opts.Adapter == nil',
            statement: 'return nil, errors.New("GraphLinkClientOptions.Adapter is required")',
          )
        else ...[
          'adapter := opts.Adapter',
          codeGenUtils.inlineIfStatement(condition: 'adapter == nil', statement: 'adapter = glNoGraphQL__'),
        ],
        if (hasRest)
          codeGenUtils.inlineIfStatement(
            condition: 'opts.RestAdapter == nil',
            statement: 'return nil, errors.New("GraphLinkClientOptions.RestAdapter is required")',
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
        if (_hasOperations(GLQueryType.query))
          'client.Queries = newGraphLinkQueries($adapterArg, $getAdapterArg, ${_restArg(GLQueryType.query)}fragments, store, locks)',
        if (_hasOperations(GLQueryType.mutation))
          'client.Mutations = newGraphLinkMutations($adapterArg, $getAdapterArg, ${_restArg(GLQueryType.mutation)}fragments, store, locks${_hasUploads ? ', uploadConverter, opts.UploadAdapter' : ''})',
        if (hasSubs)
          'client.Subscriptions = newGraphLinkSubscriptions(opts.Adapter, $getAdapterArg, fragments, store, locks, NewGraphLinkSubscriptionHandler(opts.WsAdapter))',
        'return client, nil',
      ],
    );
  }

  String _restArg(GLQueryType type) => _restOperations(type).isEmpty ? '' : 'opts.RestAdapter, ';

  String _httpOptions() {
    final graphqlHttp = hasGraphQL && _hasHttp;
    return codeGenUtils.structDecl('GraphLinkHttpOptions', [
      [
        if (graphqlHttp) 'URL string',
        if (hasGraphQL && !graphqlHttp) 'Adapter GraphLinkAdapter',
        if (_restViaHttp) 'RestBaseURL string',
        if (hasRest && !_restViaHttp) 'RestAdapter GLRestAdapter',
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
    final graphqlHttp = hasGraphQL && _hasHttp;
    return codeGenUtils.createMethod(
      methodName: 'NewGraphLinkClientWithHttp',
      arguments: ['opts GraphLinkHttpOptions'],
      returnType: '(*GraphLinkClient, error)',
      statements: [
        'clientOptions := GraphLinkClientOptions{Store: opts.Store}',
        if (graphqlHttp) ...[
          'adapter := NewGraphLinkHttpAdapter(opts.URL)',
          'adapter.HeadersProvider = opts.HeadersProvider',
          codeGenUtils.inlineIfStatement(condition: 'opts.HTTPClient != nil', statement: 'adapter.Client = opts.HTTPClient'),
          'clientOptions.Adapter = adapter.Call',
          if (_parser.persistedQueriesUseGet) 'clientOptions.GetAdapter = adapter.GetCall',
          if (_hasUploads) ...[
            'clientOptions.UploadConverter = DefaultUploadConverter',
            'clientOptions.UploadAdapter = adapter.MultipartCall',
          ],
        ],
        if (hasGraphQL && !graphqlHttp) 'clientOptions.Adapter = opts.Adapter',
        if (_restViaHttp) ...[
          'restAdapter := NewGraphLinkRestHttpAdapter(opts.RestBaseURL)',
          'restAdapter.HeadersProvider = opts.HeadersProvider',
          codeGenUtils.inlineIfStatement(condition: 'opts.HTTPClient != nil', statement: 'restAdapter.Client = opts.HTTPClient'),
          'clientOptions.RestAdapter = restAdapter.Call',
        ],
        if (hasRest && !_restViaHttp) 'clientOptions.RestAdapter = opts.RestAdapter',
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
