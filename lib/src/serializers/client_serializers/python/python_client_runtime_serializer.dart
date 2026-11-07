import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_vars.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_rest_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/python/python_client_serializer.dart';

class PythonClientRuntimeSerializer {
  final PythonClientSerializer _client;
  PythonClientRuntimeSerializer(this._client);

  GLClassModel generateModelBaseFile() => _client.static(pythonModelBase);

  GLClassModel generateExceptionFile() => _client.static(pythonException);

  GLClassModel generateLockFile() => _client.static(pythonLock);

  GLClassModel generateCacheEntryFile() => _client.static(pythonCacheEntry);

  GLClassModel generateTagEntryFile() => _client.static(pythonTagEntry);

  GLClassModel generatePartialQueryFile() => _client.static(pythonPartialQuery);

  GLClassModel generateCacheStoreFile() => _client.static(pythonCacheStore);

  GLClassModel generateInMemoryCacheStoreFile() => _client.static(pythonInMemoryCacheStore);

  GLClassModel generateWsMessageTypesFile() => _client.static(pythonWsMessageTypes);

  GLClassModel generateWsAdapterFile() => _client.static(pythonWebSocketAdapter);

  GLClassModel generateUploadConverterFile() => _client.static(pythonUploadDefaultConverter);

  GLClassModel generateRestFile() => _client.static(pythonRestFile);

  GLClassModel generateRestResolverFile() => GLClassModel(
        imports: [
          'import json',
          'import time',
          'from typing import Any, Awaitable, Callable, Dict, List, Optional, TypeVar',
          '',
          'from .graph_link_cache_entry import GraphLinkCacheEntry',
          'from .graph_link_partial_query import GraphLinkPartialQuery',
          'from .graph_link_resolver_base import $resolverBaseClassName',
          'from .graph_link_rest import DownloadProgressCallback, GLDownload, GLRestAdapter, RestError, RestRequest, RestResponse, rest_navigate',
        ],
        body: ['T = TypeVar("T")', pythonRestResolver].join('\n\n\n'),
      );

  GLClassModel generatePersistedQueriesFile() {
    if (!_client.parser.persistedQueries) {
      throw StateError('The persisted-queries runtime is only generated when persistedQueries is enabled.');
    }
    return _client.static(pythonPersistedQueries(useGet: _client.parser.persistedQueriesUseGet));
  }

  GLClassModel generateSubscriptionHandlerFile() => _client.static(pythonSubscriptionHandler);

  // ── Imports ────────────────────────────────────────────────────────────────

  String _tokenImport(String key) {
    final token = _client.parser.getTokenByKey(key);
    return token == null ? '' : _client.serializer.serializeImportToken(token);
  }

  String _adapterCall(String adapterField, String bodyExpr) => _client.parser.operationNameAsParameter
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
        'from .graph_link_cache_store import $cacheStoreClassName',
        'from .graph_link_exception import GraphLinkException',
        'from .graph_link_lock import GraphLinkLock',
        'from .graph_link_partial_query import GraphLinkPartialQuery',
        'from .graph_link_tag_entry import GraphLinkTagEntry',
        _tokenImport('GraphLinkPayload'),
        ..._client.persistedImports(),
      ],
      body: [
        'TAG_KEY_PREFIX = "__tag__"',
        'TFull = TypeVar("TFull")',
        _buildResolverBaseClass(),
      ].join('\n\n\n'),
    );
  }

  String _buildResolverBaseClass() {
    final persisted = _client.parser.persistedQueries;
    final useGet = _client.parser.persistedQueriesUseGet;
    final cg = _client.codeGenUtils;
    const fromJsonType = 'Callable[[Dict[str, Any]], TFull]';

    return cg.createClass(className: resolverBaseClassName, statements: [
      cg.createMethod(
        methodName: '__init__',
        arguments: [
          'self',
          'store: $cacheStoreClassName',
          'locks: Dict[str, GraphLinkLock]',
          'adapter: ${_client.adapterType}',
          if (useGet) 'get_adapter: ${_client.adapterType}',
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
      ..._client.buildTagMethods(),
    ]);
  }

  String _buildHashMethod() => _client.codeGenUtils.createMethod(
        methodName: 'gl_hash',
        arguments: ['self', 'query: str'],
        returnType: 'str',
        statements: [
          _client.codeGenUtils.constDecl('cached', 'self.gl_hashes__.get(query)'),
          _client.codeGenUtils.ifStatement(condition: 'cached is not None', ifBlockStatements: ['return cached']),
          _client.codeGenUtils.constDecl('digest', 'graph_link_sha256_hex(query)'),
          'self.gl_hashes__[query] = digest',
          'return digest',
        ],
      );

  String _buildSendMethod() => _client.codeGenUtils.createMethod(
        async: true,
        methodName: 'gl_send__',
        arguments: ['self', 'body: Dict[str, Any]'],
        returnType: 'str',
        statements: ['return ${_adapterCall(svAdapter, 'json.dumps(body)')}'],
      );

  String _buildSendHashOnlyMethod() => _client.codeGenUtils.createMethod(
        async: true,
        methodName: 'gl_send_hash_only__',
        arguments: ['self', 'payload: GraphLinkPayload', 'body: Dict[str, Any]'],
        returnType: 'str',
        statements: [
          _client.codeGenUtils.ifStatement(
            condition: 'self.gl_get_unsupported__ or payload.query.startswith("mutation")',
            ifBlockStatements: ['return await self.gl_send__(body)'],
          ),
          _client.codeGenUtils.tryCatchFinally(
            tryStatements: ['return ${_adapterCall(svGetAdapter, 'json.dumps(body)')}'],
            catchVariable: 'e',
            catchStatements: [
              _client.codeGenUtils.ifStatement(
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
    final cg = _client.codeGenUtils;
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
        _client.parser.persistedQueriesUseGet
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
    final cg = _client.codeGenUtils;
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
    final cg = _client.codeGenUtils;
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
    final cg = _client.codeGenUtils;
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
    final cg = _client.codeGenUtils;
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
}
