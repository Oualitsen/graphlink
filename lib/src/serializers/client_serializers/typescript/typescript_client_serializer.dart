import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';

import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_vars.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

const _adapterType = 'GraphLinkAdapter';
const _cacheStoreType = 'GraphLinkCacheStore';
const _inMemoryCacheStoreType = 'InMemoryGraphLinkCacheStore';

class TypeScriptClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final bool generateDefaultWsAdapter;
  final bool observables;
  final _cg = TypeScriptCodeGenUtils();

  late final TypeScriptClientOperationSerializer _opSer;

  TypeScriptClientSerializer(
    this._parser,
    GLSerializer tsSerializer, {
    this.generateDefaultWsAdapter = true,
    this.observables = false,
  }) : super(tsSerializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = TypeScriptClientOperationSerializer(
      _parser, _cg, gqlSerializer, serializer,
      observables: observables,
    );
  }

  @override
  String renderQueryMethod(GLQueryDefinition def) => _opSer.queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) =>
      _opSer.mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) =>
      _opSer.uploadMutationToMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) =>
      _opSer.subscriptionToMethod(def);

  // ── Shared import helpers ─────────────────────────────────────────────────

  List<String> _buildImports() {
    return [
      ...serializeImports(_parser)
          .split('\n')
          .where((l) => l.trim().isNotEmpty),
      if (_parser.hasUploadMutations)
        "import { GLUpload, GLMultipartAdapter, UploadProgressCallback } from './graph-link-uploads.js';",
      if (observables)
        "import { Observable } from 'rxjs';",
    ];
  }



  String _adapterTypeAlias() {
    if (_parser.operationNameAsParameter) {
      return 'export type $_adapterType = (payload: string, operationName: string) => Promise<string>;';
    }
    return 'export type $_adapterType = (payload: string) => Promise<string>;';
  }

  GLClassModel generateAdapterTypeFile() =>
      GLClassModel(body: _adapterTypeAlias());

  // ── Monolithic single-file generator (kept for test backward-compatibility) ──

  @override
  GLClassModel generateClient() {
    final imports = _buildImports();
    final buffer = StringBuffer();

    buffer.writeln(_adapterTypeAlias());
    buffer.writeln(tsCacheStore);
    buffer.writeln(tsInMemoryCacheStore);
    buffer.writeln(tsCacheEntry);
    buffer.writeln(tsTagEntry);
    buffer.writeln(tsLock);
    buffer.writeln(tsPartialQuery);
    if (_parser.hasSubscriptions) {
      buffer.writeln(tsWsAdapter);
      buffer.writeln(tsWsMessageTypes);
      buffer.writeln(tsSubscriptionHandler);
      if (generateDefaultWsAdapter) buffer.writeln(tsDefaultWsAdapter);
    }
    buffer.writeln(_resolverBase());
    for (final type in GLQueryType.values) {
      final cls = _buildClass(type);
      if (cls != null) buffer.writeln(cls);
    }
    buffer.writeln(_graphLinkClientClass());

    return GLClassModel(imports: imports, body: buffer.toString());
  }

  // ── Per-file generators ───────────────────────────────────────────────────

  GLClassModel generateCacheStoreFile() =>
      const GLClassModel(body: tsCacheStore);

  GLClassModel generateInMemoryCacheStoreFile() => const GLClassModel(
        imports: [
          "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
        ],
        body: tsInMemoryCacheStore,
      );

  GLClassModel generateCacheEntryFile() =>
      const GLClassModel(body: tsCacheEntry);

  GLClassModel generateTagEntryFile() =>
      const GLClassModel(body: tsTagEntry);

  GLClassModel generateLockFile() =>
      const GLClassModel(body: tsLock);

  GLClassModel generatePartialQueryFile() =>
      const GLClassModel(body: tsPartialQuery);

  GLClassModel generateWsAdapterFile() =>
      const GLClassModel(body: tsWsAdapter);

  GLClassModel generateWsMessageTypesFile() =>
      const GLClassModel(body: tsWsMessageTypes);

  GLClassModel generateSubscriptionHandlerFile() {
    final payloadToken = _parser.getTypeByName('GraphLinkPayload');
    final payloadImport = payloadToken != null
        ? serializer.serializeImportToken(payloadToken)
        : '';
    return GLClassModel(
      imports: [
        if (payloadImport.isNotEmpty) payloadImport,
        "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
        "import { _GL_WS } from './graph-link-ws-message-types.js';",
        "import type { _GlWsMsg } from './graph-link-ws-message-types.js';",
      ],
      body: tsSubscriptionHandler,
    );
  }

  GLClassModel generateDefaultWsAdapterFile() => const GLClassModel(
        imports: [
          "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
          "import { _makeChannel, _makeBroadcastChannel } from './graph-link-subscription-handler.js';",
        ],
        body: tsDefaultWsAdapter,
      );

  GLClassModel generateResolverBaseFile() {
    final payloadToken = _parser.getTypeByName('GraphLinkPayload');
    final payloadImport = payloadToken != null
        ? serializer.serializeImportToken(payloadToken)
        : '';
    return GLClassModel(
      imports: [
        if (payloadImport.isNotEmpty) payloadImport,
        "import type { $_adapterType } from './graph-link-adapter.js';",
        "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
        "import { GraphLinkCacheEntry } from './graph-link-cache-entry.js';",
        "import { GraphLinkTagEntry, __GL_TAG_KEY_PREFIX__ } from './graph-link-tag-entry.js';",
        "import { GraphLinkLock } from './graph-link-lock.js';",
      ],
      body: _resolverBase(),
    );
  }

  GLClassModel? generateQueriesFile() {
    final body = _buildClass(GLQueryType.query);
    if (body == null) return null;
    return GLClassModel(
      imports: [
        ...schemaImportsFor(GLQueryType.query),
        ..._errorImport(),
        if (observables) "import { Observable } from 'rxjs';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $_adapterType } from './graph-link-adapter.js';",
        "import type { $_cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
        "import { GraphLinkCacheEntry } from './graph-link-cache-entry.js';",
        "import { GraphLinkPartialQuery } from './graph-link-partial-query.js';",
      ],
      body: body,
    );
  }

  GLClassModel? generateMutationsFile() {
    final body = _buildClass(GLQueryType.mutation);
    if (body == null) return null;
    return GLClassModel(
      imports: [
        ...schemaImportsFor(GLQueryType.mutation),
        ..._errorImport(),
        if (observables) "import { Observable } from 'rxjs';",
        if (_parser.hasUploadMutations)
          "import { GLUpload, GLMultipartAdapter, UploadProgressCallback } from './graph-link-uploads.js';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $_adapterType } from './graph-link-adapter.js';",
        "import type { $_cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
      ],
      body: body,
    );
  }

  GLClassModel? generateSubscriptionsFile() {
    final body = _buildClass(GLQueryType.subscription);
    if (body == null) return null;
    return GLClassModel(
      imports: [
        ...schemaImportsFor(GLQueryType.subscription),
        if (observables) "import { Observable } from 'rxjs';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $_cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
        "import { GraphLinkSubscriptionHandler } from './graph-link-subscription-handler.js';",
        "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
      ],
      body: body,
    );
  }

  GLClassModel generateClientOnlyFile() {
    final imports = [
      "import type { $_adapterType } from './graph-link-adapter.js';",
      "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
      "import { InMemoryGraphLinkCacheStore } from './graph-link-in-memory-cache-store.js';",
      "import { GraphLinkLock } from './graph-link-lock.js';",
      if (_parser.hasQueries)
        "import { GraphLinkQueries } from './graph-link-queries.js';",
      if (_parser.hasMutations)
        "import { GraphLinkMutations } from './graph-link-mutations.js';",
      if (_parser.hasSubscriptions) ...[
        "import { GraphLinkSubscriptions } from './graph-link-subscriptions.js';",
        "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
      ],
      if (_parser.hasMutations && _parser.hasUploadMutations)
        "import type { GLMultipartAdapter } from './graph-link-uploads.js';",
    ];
    return GLClassModel(imports: imports, body: _graphLinkClientClass());
  }

  // ── Resolver base class ───────────────────────────────────────────────────

  String _resolverBase() {
    return _cg.createClass(
      className: 'GraphLinkResolverBase',
      exported: true,
      statements: [
        'protected readonly $svStore: $_cacheStoreType;',
        'protected readonly $svTagLocks: Map<string, GraphLinkLock>;',
        'protected readonly $svFragMap: Record<string, string>;',
        'protected readonly $svAdapter?: $_adapterType;',
        _cg.createMethod(
          methodName: 'constructor',
          arguments: ['store: $_cacheStoreType', 'tagLocks: Map<string, GraphLinkLock>', 'fragMap: Record<string, string>', 'adapter?: $_adapterType'],
          statements: [
            'this.$svStore = store;',
            'this.$svTagLocks = tagLocks;',
            'this.$svFragMap = fragMap;',
            'this.$svAdapter = adapter;',
          ],
        ),
        _cg.createMethod(
          methodName: '_glCallAdapter',
          async: true,
          returnType: 'string',
          arguments: ['payload: GraphLinkPayload'],
          statements: [
            if (_parser.operationNameAsParameter)
              'return await this.$svAdapter!(JSON.stringify(payload), payload.operationName);'
            else
              'return await this.$svAdapter!(JSON.stringify(payload));'
          ],
        ),
        _cg.createMethod(
          methodName: '_executeFull<T>',
          async: true,
          returnType: 'T',
          arguments: [
            'query: string',
            'fragmentNames: string[]',
            'operationName: string',
            'variables: Record<string, unknown>',
          ],
          statements: [
            'const fullQuery = this.assembleQuery(query, fragmentNames);',
            'const payload: GraphLinkPayload = { query: fullQuery, operationName, variables };',
            'const response = await this._glCallAdapter(payload);',
            'return JSON.parse(response) as T;',
          ],
        ),
        _cg.createMethod(
          methodName: '_getFromCache',
          async: true,
          arguments: [
            'key: string',
            'tags: string[]',
            'staleIfOffline: boolean',
          ],
          returnType: 'GraphLinkCacheEntry | null',
          statements: [
            'const result = await this.$svStore.get(key);',
            _cg.ifStatement(
              condition: 'result !== null',
              ifBlockStatements: [
                'const entry = GraphLinkCacheEntry.fromJson(JSON.parse(result));',
                _cg.ifStatement(
                  condition: 'entry.isExpired',
                  ifBlockStatements: [
                    _cg.ifStatement(
                      condition: 'staleIfOffline',
                      ifBlockStatements: ['return entry.asStale();'],
                    ),
                    'void this.$svStore.invalidate(key);',
                    _cg.ifStatement(
                      condition: 'tags.length > 0',
                      ifBlockStatements: ['void this._removeKeyFromTags(key, tags);'],
                    ),
                    'return null;',
                  ],
                  elseBlockStatements: ['return entry;'],
                ),
              ],
            ),
            'return null;',
          ],
        ),
        _cg.createMethod(
          methodName: '_invalidateByTags',
          async: true,
          arguments: ['tags: string[]'],
          returnType: 'void',
          statements: [
            _cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              r'const tagKey = `${__GL_TAG_KEY_PREFIX__}${tag}`;',
              'const lock = this.$svTagLocks.get(tag)!;',
              'await lock.synchronized(async () => {',
              '  const data = await this.$svStore.get(tagKey);',
              _cg.ifStatement(
                condition: 'data !== null',
                ifBlockStatements: [
                  'const entry = GraphLinkTagEntry.decode(data);',
                  _cg.forEachLoop(
                    variable: 'k',
                    iterable: 'entry.keys',
                    statements: ['await this.$svStore.invalidate(k);'],
                  ),
                  'await this.$svStore.invalidate(tagKey);',
                ],
              ),
              '});',
            ]),
          ],
        ),
        _cg.createMethod(
          methodName: '_addKeyToTags',
          async: true,
          arguments: ['key: string', 'tags: string[]'],
          returnType: 'void',
          statements: [
            _cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              r'const tagKey = `${__GL_TAG_KEY_PREFIX__}${tag}`;',
              'const lock = this.$svTagLocks.get(tag)!;',
              'await lock.synchronized(async () => {',
              '  const data = await this.$svStore.get(tagKey);',
              '  const entry = data !== null ? GraphLinkTagEntry.decode(data) : new GraphLinkTagEntry(new Set());',
              '  entry.add(key);',
              '  await this.$svStore.set(tagKey, entry.encode());',
              '});',
            ]),
          ],
        ),
        _cg.createMethod(
          methodName: '_removeKeyFromTags',
          async: true,
          arguments: ['key: string', 'tags: string[]'],
          returnType: 'void',
          statements: [
            _cg.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              r'const tagKey = `${__GL_TAG_KEY_PREFIX__}${tag}`;',
              'const lock = this.$svTagLocks.get(tag) ?? (() => { const l = new GraphLinkLock(); this.$svTagLocks.set(tag, l); return l; })();',
              'await lock.synchronized(async () => {',
              '  const data = await this.$svStore.get(tagKey);',
              _cg.ifStatement(
                condition: 'data !== null',
                ifBlockStatements: [
                  '  const entry = GraphLinkTagEntry.decode(data);',
                  '  entry.remove(key);',
                  _cg.ifStatement(
                    condition: 'entry.keys.size === 0',
                    ifBlockStatements: ['await this.$svStore.invalidate(tagKey);'],
                    elseBlockStatements: [
                      'await this.$svStore.set(tagKey, entry.encode());',
                    ],
                  ),
                ],
              ),
              '});',
            ]),
          ],
        ),
        _cg.createMethod(
          methodName: 'assembleQuery',
          returnType: 'string',
          arguments: ['query: string', 'fragmentNames: string[]'],
          statements: [
            'let result = query;',
            _cg.forEachLoop(
              variable: 'name',
              iterable: 'fragmentNames',
              statements: [
                'const frag = this.$svFragMap[name];',
                _cg.ifStatement(
                  condition: 'frag',
                  ifBlockStatements: ["result += '\\n' + frag;"],
                ),
              ],
            ),
            'return result;',
          ],
        ),
      ],
    );
  }

  // ── Operation class builder ───────────────────────────────────────────────

  String? _buildClass(GLQueryType type) {
    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

    return _cg.createClass(
      className: '${classNameFromType(type)} extends GraphLinkResolverBase',
      exported: true,
      statements: [
        if (type != GLQueryType.subscription) ...[
          if (type == GLQueryType.mutation && _parser.hasUploadMutations)
            'private readonly $svMultipartAdapter?: GLMultipartAdapter;',
        ] else ...[
          'private readonly $svHandler: GraphLinkSubscriptionHandler;',
        ],
        _buildConstructor(type),
        if (type == GLQueryType.query) ...[
          _buildPayloadMethod(),
          _parseAndCacheMethod(),
        ],
        ...methods,
      ],
    );
  }

  String _buildConstructor(GLQueryType type) {
    final args = [
      if (type == GLQueryType.subscription)
        'adapter: GraphLinkWsAdapter'
      else
        'adapter: $_adapterType',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations)
        'multipartAdapter: GLMultipartAdapter | undefined',
      'fragMap: Record<string, string>',
      'store: $_cacheStoreType',
      'tagLocks: Map<string, GraphLinkLock>',
    ];
    final superCall = type == GLQueryType.subscription
        ? 'super(store, tagLocks, fragMap);'
        : 'super(store, tagLocks, fragMap, adapter);';
    return _cg.createMethod(
      methodName: 'constructor',
      arguments: args,
      statements: [
        superCall,
        if (type == GLQueryType.subscription) ...[
          'this.$svHandler = new GraphLinkSubscriptionHandler(adapter);',
        ] else ...[
          if (type == GLQueryType.mutation && _parser.hasUploadMutations)
            'this.$svMultipartAdapter = multipartAdapter;',
        ],
      ],
    );
  }

  String _buildPayloadMethod() {
    return '''
private _buildPayload(
  partQueries: GraphLinkPartialQuery[],
  operationName: string,
  directives: string,
): GraphLinkPayload {
  const variables: Record<string, unknown> = {};
  for (const pq of partQueries) Object.assign(variables, pq.variables);
  let query = `query \${operationName}`;
  const args = new Set(partQueries.flatMap(pq => pq.argumentDeclarations));
  if (args.size > 0) query += `(\${Array.from(args).join(', ')})`;
  if (directives) query += directives;
  query += '{';
  for (const pq of partQueries) query += pq.query + ' ';
  query += '}';
  const fragNames = new Set(partQueries.flatMap(pq => Array.from(pq.fragmentNames)));
  query += Array.from(fragNames).map(n => this.$svFragMap[n]!).join('');
  return { query, operationName, variables };
}''';
  }

  String _parseAndCacheMethod() {
    return _cg.createMethod(
      methodName: 'private _parseAndCache',
      returnType: 'Record<string, unknown>',
      arguments: [
        'data: string',
        'cachedResponse: Record<string, unknown>',
        'remainingQueries: GraphLinkPartialQuery[]',
        'captureErrors = false',
      ],
      statements: [
        'const result = JSON.parse(data);',
        "const dataMap: Record<string, unknown> = (result['data'] as Record<string, unknown>) ?? {};",
        _cg.forEachLoop(
          variable: 'q',
          iterable: 'remainingQueries',
          statements: [
            _cg.ifStatement(
              condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
              ifBlockStatements: [
                'const entry = new GraphLinkCacheEntry(JSON.stringify(dataMap[q.elementKey]), Date.now() + q.ttl * 1000);',
                'void this.$svStore.set(q.cacheKey!, JSON.stringify(entry.toJson()));',
                _cg.ifStatement(
                  condition: 'q.tags.length > 0',
                  ifBlockStatements: ['void this._addKeyToTags(q.cacheKey!, q.tags);'],
                ),
              ],
            ),
          ],
        ),
        'Object.assign(dataMap, cachedResponse);',
        "const fullResponse: Record<string, unknown> = { 'data': result['data'] != null ? dataMap : null, 'errors': result['errors'] ?? null };",
        _cg.ifStatement(
          condition: 'captureErrors',
          ifBlockStatements: ['return fullResponse;'],
        ),
        "const errors = result['errors'] as unknown[] | null | undefined;",
        _cg.ifStatement(
          condition: 'errors != null && errors.length > 0',
          ifBlockStatements: ["throw errors as GraphLinkError[];"],
        ),
        'return fullResponse;',
      ],
    );
  }

  // ── GraphLinkClient class ─────────────────────────────────────────────────

  String _graphLinkClientClass() {
    final hasQueries = _parser.hasQueries;
    final hasMutations = _parser.hasMutations;
    final hasSubs = _parser.hasSubscriptions;
    final allTags =
        _parser.getAllCacheTags().map((t) => "'$t'").join(', ');

    return _cg.createClass(
      className: 'GraphLinkClient',
      statements: [
        'private readonly $svFragMap: Record<string, string> = {};',
        'private readonly $svTagLocks: Map<string, GraphLinkLock> = new Map();',
        if (hasQueries)
          'readonly queries: ${classNameFromType(GLQueryType.query)};',
        if (hasMutations)
          'readonly mutations: ${classNameFromType(GLQueryType.mutation)};',
        if (hasSubs)
          'readonly subscriptions: ${classNameFromType(GLQueryType.subscription)};',
        'readonly store: $_cacheStoreType;',
        _buildClientConstructor(
          hasQueries: hasQueries,
          hasMutations: hasMutations,
          hasSubs: hasSubs,
          allTags: allTags,
        ),
      ],
    );
  }

  String _buildClientConstructor({
    required bool hasQueries,
    required bool hasMutations,
    required bool hasSubs,
    required String allTags,
  }) {
    final args = [
      'adapter: $_adapterType',
      if (hasSubs) 'wsAdapter: GraphLinkWsAdapter',
      if (hasMutations && _parser.hasUploadMutations)
        'multipartAdapter?: GLMultipartAdapter',
      'store?: $_cacheStoreType',
    ];

    final fragAssignments = _parser.usedFragments
        .where((f) => !oversizedFragmentNames.contains(f.tokenInfo.token))
        .map((f) =>
            "this.$svFragMap['${f.tokenInfo}'] = '${gqlSerializer.serializeFragmentDefinitionBase(f)}';")
        .toList();

    return _cg.createMethod(
      methodName: 'constructor',
      arguments: args,
      statements: [
        ...fragAssignments,
        'this.store = store ?? new $_inMemoryCacheStoreType();',
        "for (const tag of [$allTags]) this.$svTagLocks.set(tag, new GraphLinkLock());",
        if (hasQueries)
          'this.queries = new ${classNameFromType(GLQueryType.query)}(adapter, this.$svFragMap, this.store, this.$svTagLocks);',
        if (hasMutations)
          _parser.hasUploadMutations
            ? 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, multipartAdapter, this.$svFragMap, this.store, this.$svTagLocks);'
            : 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, this.$svFragMap, this.store, this.$svTagLocks);',
        if (hasSubs)
          'this.subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, this.$svFragMap, this.store, this.$svTagLocks);',
      ],
    );
  }

  // ── Adapters file ─────────────────────────────────────────────────────────

  GLClassModel? generateAdaptersFile(TypeScriptHttpAdapter httpAdapter) {
    if (httpAdapter == TypeScriptHttpAdapter.none) return null;
    final hasUploads = _parser.hasUploadMutations;
    final buffer = StringBuffer();
    buffer.writeln(
      "import type { $_adapterType } from './graph-link-adapter.js';",
    );
    if (hasUploads && httpAdapter == TypeScriptHttpAdapter.fetch) {
      buffer.writeln(
        "import type { GLUpload, GLMultipartAdapter, UploadProgressCallback } from './graph-link-uploads.js';",
      );
    }
    buffer.writeln();
    if (httpAdapter == TypeScriptHttpAdapter.fetch) {
      buffer.writeln(tsFetchAdapter(_parser.operationNameAsParameter));
      if (hasUploads) buffer.writeln(tsMultipartFetchAdapter);
    }
    if (httpAdapter == TypeScriptHttpAdapter.axios) {
      buffer.writeln(tsAxiosAdapter(_parser.operationNameAsParameter));
    }
    return GLClassModel(body: buffer.toString());
  }

  // ── Uploads file ──────────────────────────────────────────────────────────

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: tsUploadsFile);

  // ── GLClientSerializer overrides ──────────────────────────────────────────

  @override
  GLClassModel? getQueriesClass() {
    final body = _buildClass(GLQueryType.query);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getMutationsClass() {
    final body = _buildClass(GLQueryType.mutation);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getSubscriptionsClass() {
    final body = _buildClass(GLQueryType.subscription);
    return body != null ? GLClassModel(body: body) : null;
  }

  List<String> _errorImport() {
    final token = _parser.getTokenByKey('GraphLinkError');
    if (token == null) return const [];
    final imp = serializer.serializeImportToken(token);
    return imp.isNotEmpty ? [imp] : const [];
  }

  String get fileExtension => ".ts";
}
