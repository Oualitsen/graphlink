import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_vars.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_operation_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_runtime_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_adapters_serializer.dart';

const resolverBaseClassName = 'GraphLinkResolverBase';
const cacheStoreClassName = 'GraphLinkCacheStore';

class PythonClientSerializer extends GLClientSerializer {
  late final runtime = PythonClientRuntimeSerializer(this);
  late final adapters = PythonClientAdaptersSerializer(this);

  final GLParser _parser;

  final PythonHttpAdapter httpAdapter;

  final PythonWsAdapter wsAdapter;

  final PythonHttpAdapter restHttpAdapter;

  final PythonCodeGenUtils codeGenUtils = PythonCodeGenUtils();

  late final PythonClientOperationSerializer _opSer;

  late final PythonRestOperationSerializer _restSer;

  PythonClientSerializer(
    this._parser,
    PythonSerializer pythonSerializer, {
    this.httpAdapter = PythonHttpAdapter.httpx,
    this.wsAdapter = PythonWsAdapter.websockets,
    this.restHttpAdapter = PythonHttpAdapter.httpx,
    bool commaQueryLists = false,
    bool bracketFormNesting = false,
  }) : super(pythonSerializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = PythonClientOperationSerializer(_parser, codeGenUtils, gqlSerializer, pythonSerializer);
    _restSer = PythonRestOperationSerializer(
      _parser,
      codeGenUtils,
      pythonSerializer,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _parser.restOperations.values.where((o) => o.type == type).toList();

  bool get _hasRest => _parser.restOperations.isNotEmpty;

  bool get hasRest => _hasRest;

  bool get _hasGraphQL => GLQueryType.values.any(_parser.hasQueryType);

  bool get hasGraphQL => _hasGraphQL;

  bool get _graphqlViaHttp => _hasGraphQL && _hasHttpAdapter;

  bool get restViaHttp => _hasRest && restHttpAdapter == PythonHttpAdapter.httpx;

  bool get generatesRestAdapter => restViaHttp;

  bool get generatesHttpxAdapter => _graphqlViaHttp;

  bool _hasOperations(GLQueryType type) => _parser.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get usesUploadsRuntime => _parser.hasUploadMutations || _hasRest;

  PythonSerializer get _py => serializer as PythonSerializer;

  bool get _hasHttpAdapter => httpAdapter == PythonHttpAdapter.httpx;

  bool get _hasWsAdapter => wsAdapter == PythonWsAdapter.websockets;

  String get fileExtension => '.py';

  @override
  String renderQueryMethod(GLQueryDefinition def) => _opSer.queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) => _opSer.mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) => _opSer.mutationToMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) => _opSer.mutationToMethod(def);

  @override
  GLClassModel generateClient() => generateClientFile();

  // ── Static runtime files ───────────────────────────────────────────────────

  GLClassModel static(String body) => GLClassModel(body: body);

  @override
  GLClassModel generateUploadsFile() => static(pythonUploads);

  List<String> persistedImports() => [
        if (_parser.persistedQueries) 'from .graph_link_persisted_queries import GraphLinkPersistedQueries, graph_link_sha256_hex',
        if (_parser.persistedQueriesUseGet) 'from .graph_link_persisted_queries import GraphLinkGetNotSupported',
      ];

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
    return [
      'from .graph_link_rest_resolver import GraphLinkRestResolver',
      'from .graph_link_rest import DownloadProgressCallback, GLDownload, GLRestAdapter, RestFormBody, RestJsonBody, RestMultipartBody, RestPart, RestRawBody, RestRequest, RestBody, rest_encode, rest_encode_json, rest_entries, rest_header, rest_headers, rest_parts, rest_spread_entries, rest_text',
      if (!(type == GLQueryType.mutation && _parser.hasUploadMutations))
        'from .graph_link_uploads import GLUpload, UploadProgressCallback',
    ];
  }

  List<String> _importsForType(GLQueryType type) => [
        'from .graph_link_cache_store import $cacheStoreClassName',
        'from .graph_link_lock import GraphLinkLock',
        'from .graph_link_resolver_base import $resolverBaseClassName',
        if (type == GLQueryType.query) 'from .graph_link_partial_query import GraphLinkPartialQuery',
        if (type != GLQueryType.subscription) 'from .graph_link_exception import GraphLinkException',
        if (type == GLQueryType.mutation && _parser.hasUploadMutations)
          'from .graph_link_uploads import GLUpload, GLUploadConverter, GLMultipartAdapter, UploadProgressCallback',
        if (type == GLQueryType.subscription) ...[
          'from .graph_link_subscription_handler import GraphLinkSubscriptionHandler',
          'from .graph_link_websocket_adapter import GraphLinkWebSocketAdapter',
        ],
        ..._parser.scalarImportsOfOperationType(type),
        ..._restImportsFor(type),
      ];

  // ── Resolver base ──────────────────────────────────────────────────────────

  String get adapterType =>
      _parser.operationNameAsParameter ? 'Callable[[str, str], Awaitable[str]]' : 'Callable[[str], Awaitable[str]]';

  List<String> buildTagMethods() {
    final cg = codeGenUtils;
    String tagLoop({required String lockExpr, required List<String> work}) => cg.forEachLoop(
          variable: 'tag',
          iterable: 'tags',
          statements: [
            cg.constDecl('tag_key', 'TAG_KEY_PREFIX + tag'),
            cg.constDecl('lock', lockExpr),
            cg.createMethod(async: true, methodName: 'work', arguments: [], returnType: 'None', statements: work),
            'await lock.synchronized(work)',
          ],
        );

    return [
      cg.createMethod(
        async: true,
        methodName: 'invalidate_by_tags',
        arguments: ['self', 'tags: List[str]'],
        returnType: 'None',
        statements: [
          tagLoop(lockExpr: 'self.$svTagLocks[tag]', work: [
            cg.constDecl('data', 'await self.$svStore.get(tag_key)'),
            cg.ifStatement(condition: 'data is not None', ifBlockStatements: [
              cg.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
              cg.forEachLoop(variable: 'key', iterable: 'list(entry.keys)', statements: ['await self.$svStore.invalidate(key)']),
              'await self.$svStore.invalidate(tag_key)',
            ]),
          ]),
        ],
      ),
      '',
      cg.createMethod(
        async: true,
        methodName: 'add_key_to_tags',
        arguments: ['self', 'key: str', 'tags: List[str]'],
        returnType: 'None',
        statements: [
          tagLoop(lockExpr: 'self.$svTagLocks[tag]', work: [
            cg.constDecl('data', 'await self.$svStore.get(tag_key)'),
            cg.constDecl('entry', 'GraphLinkTagEntry.decode(data) if data is not None else GraphLinkTagEntry()'),
            'entry.add(key)',
            'await self.$svStore.set(tag_key, entry.encode())',
          ]),
        ],
      ),
      '',
      cg.createMethod(
        async: true,
        methodName: '_remove_key_from_tags',
        arguments: ['self', 'key: str', 'tags: List[str]'],
        returnType: 'None',
        statements: [
          tagLoop(lockExpr: 'self.$svTagLocks.setdefault(tag, GraphLinkLock())', work: [
            cg.constDecl('data', 'await self.$svStore.get(tag_key)'),
            cg.ifStatement(condition: 'data is not None', ifBlockStatements: [
              cg.constDecl('entry', 'GraphLinkTagEntry.decode(data)'),
              'entry.remove(key)',
              cg.ifStatement(
                condition: 'not entry.keys',
                ifBlockStatements: ['await self.$svStore.invalidate(tag_key)'],
                elseBlockStatements: ['await self.$svStore.set(tag_key, entry.encode())'],
              ),
            ]),
          ]),
        ],
      ),
    ];
  }

  // ── Operation classes ──────────────────────────────────────────────────────

  String? _buildOperationClass(GLQueryType type) {
    final restOperations = _restOperations(type);
    final methods = [...buildOperationMethods(type), ...restOperations.map(_restSer.operationToMethod)];
    if (methods.isEmpty) return null;
    final cg = codeGenUtils;
    final isUpload = type == GLQueryType.mutation && _parser.hasUploadMutations;
    return cg.createClass(
      className: classNameFromType(type),
      baseClassNames: [restOperations.isEmpty ? resolverBaseClassName : 'GraphLinkRestResolver'],
      statements: [
        cg.createMethod(
          methodName: '__init__',
          arguments: [
            'self',
            'adapter: $adapterType',
            '*',
            if (restOperations.isNotEmpty) 'rest_adapter: GLRestAdapter',
            if (_parser.persistedQueriesUseGet) 'get_adapter: $adapterType',
            if (type == GLQueryType.subscription) 'ws_adapter: GraphLinkWebSocketAdapter',
            if (isUpload) ...[
              'upload_converter: GLUploadConverter',
              'upload_adapter: Optional[GLMultipartAdapter]',
            ],
            'fragment_map: Dict[str, str]',
            'store: $cacheStoreClassName',
            'tag_locks: Dict[str, GraphLinkLock]',
          ],
          returnType: 'None',
          statements: [
            cg.callExpression('super().__init__', [
              'store',
              'tag_locks',
              'adapter',
              if (_parser.persistedQueriesUseGet) 'get_adapter',
              'fragment_map',
            ]),
            if (restOperations.isNotEmpty) 'self.rest_adapter = rest_adapter',
            if (type == GLQueryType.subscription) 'self.$svHandler = GraphLinkSubscriptionHandler(ws_adapter)',
            if (isUpload) ...[
              'self.$svUploadConverter = upload_converter',
              'self.$svUploadAdapter = upload_adapter',
            ],
          ],
        ),
        ...methods.expand((m) => ['', m]),
      ],
    );
  }

  GLClassModel? _operationFile(GLQueryType type) {
    final body = _buildOperationClass(type);
    if (body == null) return null;
    return GLClassModel(
      imports: [
        'import json',
        'from typing import Any, AsyncIterator, Awaitable, Callable, Dict, List, Optional, Tuple',
        '',
        ..._importsForType(type),
      ],
      importDepencies: {...schemaTokensFor(type), ..._restTokensFor(type)}.toList(),
      body: body,
    );
  }

  @override
  GLClassModel? getQueriesClass() => _operationFile(GLQueryType.query);

  @override
  GLClassModel? getMutationsClass() => _operationFile(GLQueryType.mutation);

  @override
  GLClassModel? getSubscriptionsClass() => _operationFile(GLQueryType.subscription);

  // ── Client ─────────────────────────────────────────────────────────────────

  GLClassModel generateClientFile() {
    final imports = <String>[
      'from typing import Any, Awaitable, Callable, Dict, List, Optional',
      '',
      'from .graph_link_cache_store import $cacheStoreClassName',
      'from .graph_link_in_memory_cache_store import InMemoryGraphLinkCacheStore',
      'from .graph_link_lock import GraphLinkLock',
      if (_hasOperations(GLQueryType.query)) 'from .graph_link_queries import GraphLinkQueries',
      if (_hasOperations(GLQueryType.mutation)) 'from .graph_link_mutations import GraphLinkMutations',
      if (_hasOperations(GLQueryType.subscription)) ...[
        'from .graph_link_subscriptions import GraphLinkSubscriptions',
        'from .graph_link_websocket_adapter import GraphLinkWebSocketAdapter',
      ],
      if (_hasRest) ...[
        'from .graph_link_rest import GLRestAdapter',
        if (!_hasGraphQL) 'from .graph_link_rest import gl_no_graphql__',
      ],
      if (restViaHttp) 'from .graph_link_rest_httpx_adapter import GraphLinkRestHttpxAdapter',
      if (_graphqlViaHttp) 'from .graph_link_httpx_adapter import GraphLinkHttpxAdapter',
      if (_graphqlViaHttp && _parser.hasSubscriptions && _hasWsAdapter)
        'from .graph_link_default_websocket_adapter import DefaultGraphLinkWebSocketAdapter',
      if (_parser.hasMutations && _parser.hasUploadMutations) ...[
        'from .graph_link_uploads import GLUploadConverter, GLMultipartAdapter',
        'from .graph_link_upload_converter import default_upload_converter',
      ],
    ];
    return GLClassModel(imports: imports, body: _buildClientClass());
  }

  String _buildClientClass() {
    final cg = codeGenUtils;
    final hasUploads = _parser.hasMutations && _parser.hasUploadMutations;
    final useGet = _parser.persistedQueriesUseGet;
    final fragments = _parser.usedFragments.where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token));
    final tags = _parser.getAllCacheTags().map(_py.pythonStringLiteral).toList();

    String opConstruction(GLQueryType type) => cg.callExpression(classNameFromType(type), [
          _hasGraphQL ? 'adapter' : 'gl_no_graphql__',
          if (_restOperations(type).isNotEmpty) 'rest_adapter=rest_adapter',
          if (useGet) 'get_adapter=get_adapter',
          if (type == GLQueryType.subscription) 'ws_adapter=ws_adapter',
          if (type == GLQueryType.mutation && hasUploads) ...[
            'upload_converter=upload_converter',
            'upload_adapter=upload_adapter',
          ],
          'fragment_map=self.$svFragMap',
          'store=self.store',
          'tag_locks=self.$svTagLocks',
        ]);

    return cg.createClass(className: 'GraphLinkClient', statements: [
      cg.createMethod(
        methodName: '__init__',
        arguments: [
          'self',
          '*',
          if (_hasGraphQL) 'adapter: $adapterType',
          if (_hasRest) 'rest_adapter: GLRestAdapter',
          if (useGet) 'get_adapter: $adapterType',
          if (hasUploads) ...[
            'upload_converter: GLUploadConverter = default_upload_converter',
            'upload_adapter: Optional[GLMultipartAdapter] = None',
          ],
          if (_parser.hasSubscriptions) 'ws_adapter: GraphLinkWebSocketAdapter',
          'store: Optional[$cacheStoreClassName] = None',
        ],
        returnType: 'None',
        statements: [
          'self.$svFragMap: Dict[str, str] = {}',
          ...fragments.map((f) =>
              'self.$svFragMap[${_py.pythonStringLiteral(f.tokenInfo.token)}] = ${_py.pythonStringLiteral(gqlSerializer.serializeFragmentDefinitionBase(f))}'),
          'self.store: $cacheStoreClassName = store if store is not None else InMemoryGraphLinkCacheStore()',
          'self.$svTagLocks: Dict[str, GraphLinkLock] = {tag: GraphLinkLock() for tag in [${tags.join(', ')}]}',
          if (_hasOperations(GLQueryType.query)) 'self.queries = ${opConstruction(GLQueryType.query)}',
          if (_hasOperations(GLQueryType.mutation)) 'self.mutations = ${opConstruction(GLQueryType.mutation)}',
          if (_hasOperations(GLQueryType.subscription)) 'self.subscriptions = ${opConstruction(GLQueryType.subscription)}',
        ],
      ),
      if (_graphqlViaHttp || restViaHttp) ...['', _withHttpConstructor()],
    ]);
  }

  String _withHttpConstructor() {
    final cg = codeGenUtils;
    final hasUploads = _parser.hasMutations && _parser.hasUploadMutations;
    final hasSubs = _parser.hasSubscriptions;
    const headersType = 'Optional[Callable[[], Awaitable[Optional[Dict[str, str]]]]]';
    return cg.createMethod(
      decorators: ['@classmethod'],
      methodName: 'with_http',
      arguments: [
        'cls',
        '*',
        if (_graphqlViaHttp) 'url: str',
        if (_hasGraphQL && !_graphqlViaHttp) 'adapter: $adapterType',
        if (restViaHttp) 'rest_base_url: str',
        if (_hasRest && !restViaHttp) 'rest_adapter: GLRestAdapter',
        if (_graphqlViaHttp && hasSubs && _hasWsAdapter) ...['ws_url: str', 'ws_headers_provider: $headersType = None'],
        if (hasSubs && !(_graphqlViaHttp && _hasWsAdapter)) 'ws_adapter: GraphLinkWebSocketAdapter',
        'headers_provider: $headersType = None',
        'store: Optional[$cacheStoreClassName] = None',
      ],
      returnType: '"GraphLinkClient"',
      statements: [
        if (_graphqlViaHttp) cg.constDecl('http', 'GraphLinkHttpxAdapter(url=url, headers_provider=headers_provider)'),
        'return ${cg.callExpression('cls', [
          if (_hasGraphQL) _graphqlViaHttp ? 'adapter=http.call' : 'adapter=adapter',
          if (restViaHttp)
            'rest_adapter=GraphLinkRestHttpxAdapter(base_url=rest_base_url, headers_provider=headers_provider)'
          else if (_hasRest)
            'rest_adapter=rest_adapter',
          if (_graphqlViaHttp && _parser.persistedQueriesUseGet) 'get_adapter=http.get_call',
          if (_graphqlViaHttp && hasUploads) ...['upload_converter=default_upload_converter', 'upload_adapter=http.multipart_call'],
          if (hasSubs && _graphqlViaHttp && _hasWsAdapter)
            'ws_adapter=DefaultGraphLinkWebSocketAdapter(url=ws_url, headers_provider=ws_headers_provider)',
          if (hasSubs && !(_graphqlViaHttp && _hasWsAdapter)) 'ws_adapter=ws_adapter',
          'store=store',
        ])}',
      ],
    );
  }

  // ── HTTP adapter (httpx) ───────────────────────────────────────────────────

  GLParser get parser => _parser;
}
