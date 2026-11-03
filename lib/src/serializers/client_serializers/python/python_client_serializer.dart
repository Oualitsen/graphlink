import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/python_code_gen_utils.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_vars.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_operation_serializer.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/python/python_serializer.dart';

const _resolverBaseClassName = 'GraphLinkResolverBase';
const _cacheStoreClassName = 'GraphLinkCacheStore';

class PythonClientSerializer extends GLClientSerializer {
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

  bool get _restViaHttp => _hasRest && restHttpAdapter == PythonHttpAdapter.httpx;

  bool get generatesRestAdapter => _restViaHttp;

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

  GLClassModel _static(String body) => GLClassModel(body: body);

  GLClassModel generateModelBaseFile() => _static(pythonModelBase);
  GLClassModel generateExceptionFile() => _static(pythonException);
  GLClassModel generateLockFile() => _static(pythonLock);
  GLClassModel generateCacheEntryFile() => _static(pythonCacheEntry);
  GLClassModel generateTagEntryFile() => _static(pythonTagEntry);
  GLClassModel generatePartialQueryFile() => _static(pythonPartialQuery);
  GLClassModel generateCacheStoreFile() => _static(pythonCacheStore);
  GLClassModel generateInMemoryCacheStoreFile() => _static(pythonInMemoryCacheStore);
  GLClassModel generateWsMessageTypesFile() => _static(pythonWsMessageTypes);
  GLClassModel generateWsAdapterFile() => _static(pythonWebSocketAdapter);
  GLClassModel generateDefaultWebSocketAdapterFile() => _static(pythonDefaultWebSocketAdapter);
  GLClassModel generateUploadConverterFile() => _static(pythonUploadDefaultConverter);

  @override
  GLClassModel generateUploadsFile() => _static(pythonUploads);

  GLClassModel generateRestFile() => _static(pythonRestFile);

  GLClassModel generateRestResolverFile() => GLClassModel(
        imports: [
          'import json',
          'import time',
          'from typing import Any, Awaitable, Callable, Dict, List, Optional, TypeVar',
          '',
          'from .graph_link_cache_entry import GraphLinkCacheEntry',
          'from .graph_link_partial_query import GraphLinkPartialQuery',
          'from .graph_link_resolver_base import $_resolverBaseClassName',
          'from .graph_link_rest import DownloadProgressCallback, GLDownload, GLRestAdapter, RestError, RestRequest, RestResponse, rest_navigate',
        ],
        body: ['T = TypeVar("T")', pythonRestResolver].join('\n\n\n'),
      );

  GLClassModel? generateRestHttpxAdapterFile() {
    if (!_restViaHttp) return null;
    return const GLClassModel(
      imports: [
        'import inspect',
        'from typing import Any, AsyncIterator, Callable, Dict, Optional',
        '',
        'import httpx',
        '',
        'from .graph_link_rest import (',
        '    RestFormBody,',
        '    RestJsonBody,',
        '    RestMultipartBody,',
        '    RestRawBody,',
        '    RestRequest,',
        '    RestResponse,',
        '    rest_form_body,',
        '    rest_url,',
        ')',
        'from .graph_link_uploads import gl_counted_stream, gl_multipart_stream',
      ],
      body: pythonRestHttpxAdapter,
    );
  }

  GLClassModel generatePersistedQueriesFile() {
    if (!_parser.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return _static(pythonPersistedQueries(useGet: _parser.persistedQueriesUseGet));
  }

  GLClassModel generateSubscriptionHandlerFile() => _static(pythonSubscriptionHandler);

  // ── Imports ────────────────────────────────────────────────────────────────

  String _tokenImport(String key) {
    final token = _parser.getTokenByKey(key);
    return token == null ? '' : serializer.serializeImportToken(token);
  }

  List<String> _persistedImports() => [
        if (_parser.persistedQueries) 'from .graph_link_persisted_queries import GraphLinkPersistedQueries, graph_link_sha256_hex',
        if (_parser.persistedQueriesUseGet) 'from .graph_link_persisted_queries import GraphLinkGetNotSupported',
      ];

  List<String> _restImportsFor(GLQueryType type) {
    final operations = _restOperations(type);
    if (operations.isEmpty) return const [];
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
      'from .graph_link_rest_resolver import GraphLinkRestResolver',
      'from .graph_link_rest import DownloadProgressCallback, GLDownload, GLRestAdapter, RestFormBody, RestJsonBody, RestMultipartBody, RestPart, RestRawBody, RestRequest, RestBody, rest_encode, rest_encode_json, rest_entries, rest_header, rest_headers, rest_parts, rest_spread_entries, rest_text',
      if (!(type == GLQueryType.mutation && _parser.hasUploadMutations))
        'from .graph_link_uploads import GLUpload, UploadProgressCallback',
      ...tokens.map(serializer.serializeImportToken).where((e) => e.isNotEmpty).toSet(),
    ];
  }

  List<String> _importsForType(GLQueryType type) => [
        'from .graph_link_cache_store import $_cacheStoreClassName',
        'from .graph_link_lock import GraphLinkLock',
        'from .graph_link_resolver_base import $_resolverBaseClassName',
        _tokenImport('GraphLinkPayload'),
        if (type == GLQueryType.query) 'from .graph_link_partial_query import GraphLinkPartialQuery',
        if (type != GLQueryType.subscription) 'from .graph_link_exception import GraphLinkException',
        if (type == GLQueryType.mutation && _parser.hasUploadMutations)
          'from .graph_link_uploads import GLUpload, GLUploadConverter, GLMultipartAdapter, UploadProgressCallback',
        if (type == GLQueryType.subscription) ...[
          'from .graph_link_subscription_handler import GraphLinkSubscriptionHandler',
          'from .graph_link_websocket_adapter import GraphLinkWebSocketAdapter',
        ],
        ...schemaImportsFor(type),
        ..._restImportsFor(type),
      ];

  // ── Resolver base ──────────────────────────────────────────────────────────

  String get _adapterType =>
      _parser.operationNameAsParameter ? 'Callable[[str, str], Awaitable[str]]' : 'Callable[[str], Awaitable[str]]';

  String _adapterCall(String adapterField, String bodyExpr) => _parser.operationNameAsParameter
      ? 'await self.$adapterField($bodyExpr, ${bodyExpr == 'json.dumps(body)' ? 'body["operationName"]' : 'payload.operation_name'})'
      : 'await self.$adapterField($bodyExpr)';

  GLClassModel generateResolverBaseFile() {
    return GLClassModel(
      imports: [
        'import asyncio',
        'import json',
        'import time',
        'from typing import Any, Awaitable, Callable, Dict, List, Optional, TypeVar',
        '',
        'from .graph_link_cache_entry import GraphLinkCacheEntry',
        'from .graph_link_cache_store import $_cacheStoreClassName',
        'from .graph_link_exception import GraphLinkException',
        'from .graph_link_lock import GraphLinkLock',
        'from .graph_link_partial_query import GraphLinkPartialQuery',
        'from .graph_link_tag_entry import GraphLinkTagEntry',
        _tokenImport('GraphLinkPayload'),
        ..._persistedImports(),
      ],
      body: [
        'TAG_KEY_PREFIX = "__tag__"',
        'TFull = TypeVar("TFull")',
        _buildResolverBaseClass(),
      ].join('\n\n\n'),
    );
  }

  String _buildResolverBaseClass() {
    final persisted = _parser.persistedQueries;
    final useGet = _parser.persistedQueriesUseGet;
    final cg = codeGenUtils;
    const fromJsonType = 'Callable[[Dict[str, Any]], TFull]';

    return cg.createClass(className: _resolverBaseClassName, statements: [
      cg.createMethod(
        methodName: '__init__',
        arguments: [
          'self',
          'store: $_cacheStoreClassName',
          'locks: Dict[str, GraphLinkLock]',
          'adapter: $_adapterType',
          if (useGet) 'get_adapter: $_adapterType',
          'fragment_map: Dict[str, str]',
        ],
        returnType: 'None',
        statements: [
          'self.$svStore = store',
          'self.$svTagLocks = locks',
          'self.$svAdapter = adapter',
          if (useGet) ...['self.$svGetAdapter = get_adapter', 'self.gl_get_unsupported__ = False'],
          'self.$svFragMap = fragment_map',
          if (persisted) ...['self.gl_hashes__: Dict[str, str] = {}', 'self.gl_persisted_unsupported__ = False'],
        ],
      ),
      '',
      cg.createMethod(
        methodName: 'assemble_query',
        arguments: ['self', 'query: str', 'fragment_names: List[str]'],
        returnType: 'str',
        statements: [
          cg.constDecl('parts', '[query]'),
          cg.forEachLoop(variable: 'name', iterable: 'fragment_names', statements: [
            cg.constDecl('frag', 'self.$svFragMap.get(name)'),
            cg.ifStatement(condition: 'frag is not None', ifBlockStatements: ['parts.append(" ")', 'parts.append(frag)']),
          ]),
          'return "".join(parts)',
        ],
      ),
      if (persisted) ...[
        '',
        _buildHashMethod(),
        '',
        _buildSendMethod(),
      ],
      if (useGet) ...['', _buildSendHashOnlyMethod()],
      '',
      cg.createMethod(
        async: true,
        methodName: 'gl_call_adapter',
        arguments: ['self', 'payload: GraphLinkPayload'],
        returnType: 'str',
        statements: persisted
            ? _persistedCallAdapterStatements()
            : ['return ${_adapterCall(svAdapter, 'json.dumps(payload.to_json())')}'],
      ),
      '',
      cg.createMethod(
        async: true,
        methodName: 'execute_full',
        arguments: [
          'self',
          'query: str',
          'fragment_names: List[str]',
          'operation_name: str',
          'variables: Dict[str, Any]',
          'from_json: $fromJsonType',
        ],
        returnType: 'TFull',
        statements: [
          cg.constDecl('full_query', 'self.assemble_query(query, fragment_names)'),
          cg.constDecl(
            svPayload,
            cg.callExpression('GraphLinkPayload', ['query=full_query', 'operation_name=operation_name', 'variables=variables']),
          ),
          cg.constDecl(svResponse, 'await self.gl_call_adapter($svPayload)'),
          'return from_json(json.loads($svResponse))',
        ],
      ),
      '',
      cg.createMethod(
        async: true,
        methodName: 'execute_data',
        arguments: [
          'self',
          'query: str',
          'fragment_names: List[str]',
          'operation_name: str',
          'variables: Dict[str, Any]',
          'from_json: $fromJsonType',
        ],
        returnType: 'TFull',
        statements: [
          cg.constDecl(
            svResult,
            'await ${cg.callExpression('self.execute_full', ['query', 'fragment_names', 'operation_name', 'variables', 'from_json'])}',
          ),
          cg.ifStatement(
            condition: '$svResult.errors is not None',
            ifBlockStatements: ['raise GraphLinkException($svResult.errors)'],
          ),
          'return $svResult',
        ],
      ),
      '',
      _buildExecuteCached(fromJsonType),
      '',
      _buildBuildPayload(),
      '',
      _buildParseAndCache(),
      '',
      _buildGetFromCache(),
      '',
      ..._buildTagMethods(),
    ]);
  }

  String _buildHashMethod() => codeGenUtils.createMethod(
        methodName: 'gl_hash',
        arguments: ['self', 'query: str'],
        returnType: 'str',
        statements: [
          codeGenUtils.constDecl('cached', 'self.gl_hashes__.get(query)'),
          codeGenUtils.ifStatement(condition: 'cached is not None', ifBlockStatements: ['return cached']),
          codeGenUtils.constDecl('digest', 'graph_link_sha256_hex(query)'),
          'self.gl_hashes__[query] = digest',
          'return digest',
        ],
      );

  String _buildSendMethod() => codeGenUtils.createMethod(
        async: true,
        methodName: 'gl_send__',
        arguments: ['self', 'body: Dict[str, Any]'],
        returnType: 'str',
        statements: ['return ${_adapterCall(svAdapter, 'json.dumps(body)')}'],
      );

  String _buildSendHashOnlyMethod() => codeGenUtils.createMethod(
        async: true,
        methodName: 'gl_send_hash_only__',
        arguments: ['self', 'payload: GraphLinkPayload', 'body: Dict[str, Any]'],
        returnType: 'str',
        statements: [
          codeGenUtils.ifStatement(
            condition: 'self.gl_get_unsupported__ or payload.query.startswith("mutation")',
            ifBlockStatements: ['return await self.gl_send__(body)'],
          ),
          codeGenUtils.tryCatchFinally(
            tryStatements: ['return ${_adapterCall(svGetAdapter, 'json.dumps(body)')}'],
            catchVariable: 'e',
            catchStatements: [
              codeGenUtils.ifStatement(
                condition: 'not isinstance(e, GraphLinkGetNotSupported)',
                ifBlockStatements: ['raise'],
              ),
              'self.gl_get_unsupported__ = True',
              'return await self.gl_send__(body)',
            ],
          ),
        ],
      );

  List<String> _persistedCallAdapterStatements() {
    final cg = codeGenUtils;
    return [
      cg.ifStatement(
        condition: 'self.gl_persisted_unsupported__ or len(payload.query) <= GraphLinkPersistedQueries.MIN_QUERY_LENGTH',
        ifBlockStatements: ['return await self.gl_send__(payload.to_json())'],
      ),
      cg.constDecl('gl_extensions__', 'GraphLinkPersistedQueries.extensions(self.gl_hash(payload.query))'),
      cg.constDecl(
        'gl_hash_only__',
        '{"operationName": payload.operation_name, "variables": payload.variables, "extensions": gl_extensions__}',
      ),
      cg.constDecl(
        svResponse,
        _parser.persistedQueriesUseGet
            ? 'await self.gl_send_hash_only__(payload, gl_hash_only__)'
            : 'await self.gl_send__(gl_hash_only__)',
      ),
      cg.constDecl('gl_failure__', 'GraphLinkPersistedQueries.failure($svResponse)'),
      cg.ifStatement(condition: 'gl_failure__ is None', ifBlockStatements: ['return $svResponse']),
      cg.constDecl('gl_body__', 'payload.to_json()'),
      cg.ifStatement(
        condition: 'gl_failure__ == GraphLinkPersistedQueries.NOT_SUPPORTED',
        ifBlockStatements: ['self.gl_persisted_unsupported__ = True'],
        elseBlockStatements: ['gl_body__["extensions"] = gl_extensions__'],
      ),
      'return await self.gl_send__(gl_body__)',
    ];
  }

  String _buildExecuteCached(String fromJsonType) {
    final cg = codeGenUtils;
    return cg.createMethod(
      async: true,
      methodName: 'execute_cached',
      arguments: [
        'self',
        'partial_queries: List[GraphLinkPartialQuery]',
        'operation_name: str',
        'directives: str',
        'from_json: $fromJsonType',
        'capture_errors: bool',
      ],
      returnType: 'TFull',
      statements: [
        cg.constDecl(svResponseMap, '{}', type: 'Dict[str, Any]'),
        cg.constDecl(svStaleData, '{}', type: 'Dict[str, Any]'),
        cg.createMethod(
          async: true,
          methodName: 'fetch',
          arguments: ['part_query: GraphLinkPartialQuery'],
          returnType: 'None',
          statements: [
            cg.constDecl(
              'entry',
              'await ${cg.callExpression('self.get_from_cache', ['part_query.cache_key', 'part_query.tags', 'part_query.stale_if_offline'])}',
            ),
            cg.ifStatement(condition: 'entry is None', ifBlockStatements: ['return']),
            cg.ifStatement(
              condition: 'entry.stale',
              ifBlockStatements: ['$svStaleData[part_query.element_key] = json.loads(entry.data)'],
              elseBlockStatements: ['$svResponseMap[part_query.element_key] = json.loads(entry.data)'],
            ),
          ],
        ),
        'await asyncio.gather(*[fetch(q) for q in partial_queries if q.ttl > 0], return_exceptions=True)',
        cg.constDecl(svRemainingQueries, '[q for q in partial_queries if q.element_key not in $svResponseMap]'),
        cg.ifStatement(
          condition: 'not $svRemainingQueries',
          ifBlockStatements: ['return from_json({"data": $svResponseMap})'],
        ),
        cg.constDecl(svPayload, 'self._build_payload($svRemainingQueries, operation_name, directives)'),
        cg.tryCatchFinally(
          tryStatements: [
            cg.constDecl(svResponseText, 'await self.gl_call_adapter($svPayload)'),
            'return await self._parse_to_object_and_cache($svResponseText, $svResponseMap, from_json, $svRemainingQueries, capture_errors)',
          ],
          catchStatements: [
            '$svResponseMap.update($svStaleData)',
            cg.constDecl('remaining_count', 'len([q for q in partial_queries if q.element_key not in $svResponseMap])'),
            cg.ifStatement(condition: 'remaining_count > 0', ifBlockStatements: ['raise']),
            'return from_json({"data": $svResponseMap})',
          ],
        ),
      ],
    );
  }

  String _buildBuildPayload() {
    final cg = codeGenUtils;
    return cg.createMethod(
      methodName: '_build_payload',
      arguments: ['self', 'part_queries: List[GraphLinkPartialQuery]', 'operation_name: str', 'directives: str'],
      returnType: 'GraphLinkPayload',
      statements: [
        cg.constDecl('variables', '{}', type: 'Dict[str, Any]'),
        cg.forEachLoop(variable: 'part_query', iterable: 'part_queries', statements: ['variables.update(part_query.variables)']),
        cg.constDecl('query_parts', '["query " + operation_name]', type: 'List[str]'),
        cg.constDecl(
          'args',
          'list(dict.fromkeys(a for q in part_queries for a in q.argument_declarations))',
        ),
        cg.ifStatement(condition: 'args', ifBlockStatements: ['query_parts.append("(" + ", ".join(args) + ")")']),
        cg.ifStatement(condition: 'directives', ifBlockStatements: ['query_parts.append(directives)']),
        'query_parts.append("{")',
        cg.forEachLoop(
          variable: 'part_query',
          iterable: 'part_queries',
          statements: ['query_parts.append(part_query.query)', 'query_parts.append(" ")'],
        ),
        'query_parts.append("}")',
        cg.constDecl(
          'fragment_names',
          'list(dict.fromkeys(n for q in part_queries for n in q.fragment_names))',
        ),
        'query_parts.append("".join(self.$svFragMap[name] for name in fragment_names))',
        'return ${cg.callExpression('GraphLinkPayload', ['query="".join(query_parts)', 'operation_name=operation_name', 'variables=variables'])}',
      ],
    );
  }

  String _buildParseAndCache() {
    final cg = codeGenUtils;
    return cg.createMethod(
      async: true,
      methodName: '_parse_to_object_and_cache',
      arguments: [
        'self',
        'data: str',
        'cached_response: Dict[str, Any]',
        'parser: Callable[[Dict[str, Any]], TFull]',
        'remaining_queries: List[GraphLinkPartialQuery]',
        'capture_errors: bool',
      ],
      returnType: 'TFull',
      statements: [
        cg.constDecl('result', 'json.loads(data)'),
        cg.constDecl('raw_data', 'result.get("data")'),
        cg.constDecl('data_map', 'raw_data if raw_data is not None else {}'),
        cg.forEachLoop(variable: 'q', iterable: 'remaining_queries', statements: [
          cg.ifStatement(
            condition: 'q.ttl > 0 and data_map.get(q.element_key) is not None',
            ifBlockStatements: [
              cg.constDecl(
                'entry',
                'GraphLinkCacheEntry(json.dumps(data_map[q.element_key]), int(time.time() * 1000) + q.ttl * 1000)',
              ),
              'await self.$svStore.set(q.cache_key, json.dumps(entry.to_json()))',
              cg.ifStatement(condition: 'q.tags', ifBlockStatements: ['await self.add_key_to_tags(q.cache_key, q.tags)']),
            ],
          ),
        ]),
        'data_map.update(cached_response)',
        cg.constDecl('full_response', '{"data": data_map if raw_data is not None else None}', type: 'Dict[str, Any]'),
        cg.ifStatement(
          condition: 'result.get("errors") is not None',
          ifBlockStatements: ['full_response["errors"] = result["errors"]'],
        ),
        cg.constDecl('parsed', 'parser(full_response)'),
        cg.ifStatement(condition: 'capture_errors', ifBlockStatements: ['return parsed']),
        cg.ifStatement(
          condition: 'result.get("errors")',
          ifBlockStatements: ['raise GraphLinkException(parsed.errors)'],
        ),
        'return parsed',
      ],
    );
  }

  String _buildGetFromCache() {
    final cg = codeGenUtils;
    return cg.createMethod(
      async: true,
      methodName: 'get_from_cache',
      arguments: ['self', 'key: str', 'tags: List[str]', 'stale_if_offline: bool'],
      returnType: 'Optional[GraphLinkCacheEntry]',
      statements: [
        cg.constDecl('result', 'await self.$svStore.get(key)'),
        cg.ifStatement(condition: 'result is None', ifBlockStatements: ['return None']),
        cg.constDecl('entry', 'GraphLinkCacheEntry.from_json(json.loads(result))'),
        cg.ifStatement(condition: 'not entry.is_expired', ifBlockStatements: ['return entry']),
        cg.ifStatement(condition: 'stale_if_offline', ifBlockStatements: ['return entry.as_stale()']),
        'await self.$svStore.invalidate(key)',
        cg.ifStatement(condition: 'tags', ifBlockStatements: ['await self._remove_key_from_tags(key, tags)']),
        'return None',
      ],
    );
  }

  List<String> _buildTagMethods() {
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
      baseClassNames: [restOperations.isEmpty ? _resolverBaseClassName : 'GraphLinkRestResolver'],
      statements: [
        cg.createMethod(
          methodName: '__init__',
          arguments: [
            'self',
            'adapter: $_adapterType',
            '*',
            if (restOperations.isNotEmpty) 'rest_adapter: GLRestAdapter',
            if (_parser.persistedQueriesUseGet) 'get_adapter: $_adapterType',
            if (type == GLQueryType.subscription) 'ws_adapter: GraphLinkWebSocketAdapter',
            if (isUpload) ...[
              'upload_converter: GLUploadConverter',
              'upload_adapter: Optional[GLMultipartAdapter]',
            ],
            'fragment_map: Dict[str, str]',
            'store: $_cacheStoreClassName',
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
      'from .graph_link_cache_store import $_cacheStoreClassName',
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
      if (_restViaHttp) 'from .graph_link_rest_httpx_adapter import GraphLinkRestHttpxAdapter',
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
          if (_hasGraphQL) 'adapter: $_adapterType',
          if (_hasRest) 'rest_adapter: GLRestAdapter',
          if (useGet) 'get_adapter: $_adapterType',
          if (hasUploads) ...[
            'upload_converter: GLUploadConverter = default_upload_converter',
            'upload_adapter: Optional[GLMultipartAdapter] = None',
          ],
          if (_parser.hasSubscriptions) 'ws_adapter: GraphLinkWebSocketAdapter',
          'store: Optional[$_cacheStoreClassName] = None',
        ],
        returnType: 'None',
        statements: [
          'self.$svFragMap: Dict[str, str] = {}',
          ...fragments.map((f) =>
              'self.$svFragMap[${_py.pythonStringLiteral(f.tokenInfo.token)}] = ${_py.pythonStringLiteral(gqlSerializer.serializeFragmentDefinitionBase(f))}'),
          'self.store: $_cacheStoreClassName = store if store is not None else InMemoryGraphLinkCacheStore()',
          'self.$svTagLocks: Dict[str, GraphLinkLock] = {tag: GraphLinkLock() for tag in [${tags.join(', ')}]}',
          if (_hasOperations(GLQueryType.query)) 'self.queries = ${opConstruction(GLQueryType.query)}',
          if (_hasOperations(GLQueryType.mutation)) 'self.mutations = ${opConstruction(GLQueryType.mutation)}',
          if (_hasOperations(GLQueryType.subscription)) 'self.subscriptions = ${opConstruction(GLQueryType.subscription)}',
        ],
      ),
      if (_graphqlViaHttp || _restViaHttp) ...['', _withHttpConstructor()],
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
        if (_hasGraphQL && !_graphqlViaHttp) 'adapter: $_adapterType',
        if (_restViaHttp) 'rest_base_url: str',
        if (_hasRest && !_restViaHttp) 'rest_adapter: GLRestAdapter',
        if (_graphqlViaHttp && hasSubs && _hasWsAdapter) ...['ws_url: str', 'ws_headers_provider: $headersType = None'],
        if (hasSubs && !(_graphqlViaHttp && _hasWsAdapter)) 'ws_adapter: GraphLinkWebSocketAdapter',
        'headers_provider: $headersType = None',
        'store: Optional[$_cacheStoreClassName] = None',
      ],
      returnType: '"GraphLinkClient"',
      statements: [
        if (_graphqlViaHttp) cg.constDecl('http', 'GraphLinkHttpxAdapter(url=url, headers_provider=headers_provider)'),
        'return ${cg.callExpression('cls', [
          if (_hasGraphQL) _graphqlViaHttp ? 'adapter=http.call' : 'adapter=adapter',
          if (_restViaHttp)
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

  GLClassModel generateHttpxAdapterFile() {
    final cg = codeGenUtils;
    final nameParam = _parser.operationNameAsParameter ? ', operation_name: str' : '';
    final postUrl = _parser.operationNameAsParameter ? 'f"{self.url}?operationName={operation_name}"' : 'self.url';
    return GLClassModel(
      imports: [
        'import inspect',
        'from typing import Any, Awaitable, Callable, Dict, List, Optional',
        '',
        'import httpx',
        '',
        if (_parser.hasUploadMutations) 'from .graph_link_uploads import GLMultipartPart, GLUpload, UploadProgressCallback, gl_multipart_stream',
        if (_parser.persistedQueriesUseGet) 'from .graph_link_persisted_queries import GraphLinkGetNotSupported, GraphLinkGetRequest',
      ],
      body: cg.createClass(className: 'GraphLinkHttpxAdapter', statements: [
        cg.createMethod(
          methodName: '__init__',
          arguments: [
            'self',
            '*',
            'url: str',
            'headers_provider: Optional[Callable[[], Any]] = None',
            'client: Optional[httpx.AsyncClient] = None',
          ],
          returnType: 'None',
          statements: [
            'self.url = url',
            'self.headers_provider = headers_provider',
            'self.client = client if client is not None else httpx.AsyncClient()',
          ],
        ),
        '',
        cg.createMethod(
          async: true,
          methodName: '_extra_headers',
          arguments: ['self'],
          returnType: 'Dict[str, str]',
          statements: [
            cg.ifStatement(condition: 'self.headers_provider is None', ifBlockStatements: ['return {}']),
            cg.constDecl('provided', 'self.headers_provider()'),
            cg.ifStatement(condition: 'inspect.isawaitable(provided)', ifBlockStatements: ['provided = await provided']),
            'return dict(provided) if provided else {}',
          ],
        ),
        '',
        cg.createMethod(
          async: true,
          methodName: 'call',
          arguments: ['self', 'payload: str$nameParam'],
          returnType: 'str',
          statements: [
            cg.constDecl('headers', '{"Content-Type": "application/json", **await self._extra_headers()}'),
            cg.constDecl('response', 'await self.client.post($postUrl, content=payload, headers=headers)'),
            'return response.text',
          ],
        ),
        if (_parser.persistedQueriesUseGet) ...[
          '',
          cg.createMethod(
            async: true,
            methodName: 'get_call',
            arguments: ['self', 'payload: str$nameParam'],
            returnType: 'str',
            statements: [
              cg.constDecl(
                'response',
                'await ${cg.callExpression('self.client.get', [
                  'self.url',
                  'params=GraphLinkGetRequest.query_parameters(payload)',
                  'headers=await self._extra_headers()',
                ])}',
              ),
              cg.ifStatement(
                condition: 'response.status_code == 405',
                ifBlockStatements: ['raise GraphLinkGetNotSupported("GET is not allowed")'],
              ),
              'return response.text',
            ],
          ),
        ],
        if (_parser.hasUploadMutations) ...[
          '',
          cg.createMethod(
            async: true,
            methodName: 'multipart_call',
            arguments: ['self', 'parts: Dict[str, Any]', 'on_progress: Optional[UploadProgressCallback] = None'],
            returnType: 'str',
            statements: [
              cg.constDecl('multipart', 'self._multipart_parts(parts)'),
              'content_type, total, content = gl_multipart_stream(multipart, on_progress)',
              cg.constDecl('headers', '{**await self._extra_headers(), "Content-Type": content_type}'),
              cg.ifStatement(condition: 'total is not None', ifBlockStatements: ['headers["Content-Length"] = str(total)']),
              cg.constDecl('response', 'await self.client.post(self.url, content=content, headers=headers)'),
              'return response.text',
            ],
          ),
        ],
        if (_parser.hasUploadMutations) ...[
          '',
          cg.createMethod(
            methodName: '_multipart_parts',
            arguments: ['parts: Dict[str, Any]'],
            returnType: 'List[GLMultipartPart]',
            decorators: ['@staticmethod'],
            statements: [
              'return [GLMultipartPart(name=k, file=v) if isinstance(v, GLUpload) else GLMultipartPart(name=k, value=str(v)) for k, v in parts.items()]',
            ],
          ),
        ],
        '',
        cg.createMethod(async: true, methodName: 'aclose', arguments: ['self'], returnType: 'None', statements: ['await self.client.aclose()']),
      ]),
    );
  }
}
