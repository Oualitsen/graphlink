import 'package:graphlink/src/parser_extensions/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_scalar_codec_extension.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';

import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_operation_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_rest_operation_serializer.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_vars.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_runtime_serializer.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_adapters_serializer.dart';

const adapterType = 'GraphLinkAdapter';
const cacheStoreType = 'GraphLinkCacheStore';
const _inMemoryCacheStoreType = 'InMemoryGraphLinkCacheStore';

class TypeScriptClientSerializer extends GLClientSerializer {
  late final runtime = TypeScriptClientRuntimeSerializer(this);
  late final adapters = TypeScriptClientAdaptersSerializer(this);

  final GLParser _parser;

  final bool generateDefaultWsAdapter;

  final bool observables;

  final TypeScriptHttpAdapter restHttpAdapter;

  final _cg = TypeScriptCodeGenUtils();

  late final TypeScriptClientOperationSerializer _opSer;

  late final TypeScriptRestOperationSerializer _restSer;

  TypeScriptClientSerializer(
    this._parser,
    GLSerializer tsSerializer, {
    this.generateDefaultWsAdapter = true,
    this.observables = false,
    this.restHttpAdapter = TypeScriptHttpAdapter.fetch,
    bool commaQueryLists = false,
    bool bracketFormNesting = false,
  }) : super(tsSerializer, GLGraphqlSerializer(_parser, false)) {
    _opSer = TypeScriptClientOperationSerializer(
      _parser, _cg, gqlSerializer, serializer as TypeScriptSerializer,
      observables: observables,
    );
    _restSer = TypeScriptRestOperationSerializer(
      _parser, _cg, serializer as TypeScriptSerializer,
      observables: observables,
      commaLists: commaQueryLists,
      bracketNesting: bracketFormNesting,
    );
  }

  List<GLRestOperation> _restOperations(GLQueryType type) =>
      _parser.restOperations.values.where((o) => o.type == type).toList();

  bool _hasOperations(GLQueryType type) => _parser.hasQueryType(type) || _restOperations(type).isNotEmpty;

  bool get hasRest => _parser.restOperations.isNotEmpty;

  bool get _hasGraphQL => GLQueryType.values.any(_parser.hasQueryType);

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
      "import { GraphLinkRestResolver } from './graph-link-rest-resolver.js';",
      "import { GLDownload, restEncode, restEntries, restSpreadEntries, restHeader, restHeaders, restParts } from './graph-link-rest.js';",
      "import type { DownloadProgressCallback, RestBody, RestPart, RestRequest } from './graph-link-rest.js';",
      if (!(type == GLQueryType.mutation && _parser.hasUploadMutations))
        "import type { GLUpload, UploadProgressCallback } from './graph-link-uploads.js';",
    ];
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

  String adapterTypeAlias() {
    if (_parser.operationNameAsParameter) {
      return 'export type $adapterType = (payload: string, operationName: string) => Promise<string>;';
    }
    return 'export type $adapterType = (payload: string) => Promise<string>;';
  }

  @override
  GLClassModel generateClient() {
    final imports = _buildImports();
    final buffer = StringBuffer();

    buffer.writeln(adapterTypeAlias());
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
    if (_parser.persistedQueries) {
      buffer.writeln(tsSha256);
      buffer.writeln(tsPersistedQueries);
      if (_parser.persistedQueriesUseGet) buffer.writeln(tsPersistedQueriesGet);
    }
    buffer.writeln(runtime.resolverBase());
    for (final type in GLQueryType.values) {
      final cls = _buildClass(type);
      if (cls != null) buffer.writeln(cls);
    }
    buffer.writeln(_graphLinkClientClass());

    return GLClassModel(imports: imports, body: buffer.toString());
  }

  // ── Per-file generators ───────────────────────────────────────────────────

  GLClassModel? generateQueriesFile() {
    final body = _buildClass(GLQueryType.query);
    if (body == null) return null;
    return GLClassModel(
      imports: {
        ..._parser.scalarImportsOfOperationType(GLQueryType.query),
        ..._errorImport(),
        if (observables) "import { Observable } from 'rxjs';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $adapterType } from './graph-link-adapter.js';",
        "import type { $cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
        "import { GraphLinkCacheEntry } from './graph-link-cache-entry.js';",
        "import { GraphLinkPartialQuery } from './graph-link-partial-query.js';",
        ..._restImportsFor(GLQueryType.query),
      }.toList(),
      importDepencies: {...schemaTokensFor(GLQueryType.query), ..._restTokensFor(GLQueryType.query)}.toList(),
      body: body,
    );
  }

  GLClassModel? generateMutationsFile() {
    final body = _buildClass(GLQueryType.mutation);
    if (body == null) return null;
    return GLClassModel(
      imports: {
        ..._parser.scalarImportsOfOperationType(GLQueryType.mutation),
        ..._errorImport(),
        if (observables) "import { Observable } from 'rxjs';",
        if (_parser.hasUploadMutations)
          "import { GLUpload, GLMultipartAdapter, UploadProgressCallback } from './graph-link-uploads.js';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $adapterType } from './graph-link-adapter.js';",
        "import type { $cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
        ..._restImportsFor(GLQueryType.mutation),
      }.toList(),
      importDepencies: {...schemaTokensFor(GLQueryType.mutation), ..._restTokensFor(GLQueryType.mutation)}.toList(),
      body: body,
    );
  }

  GLClassModel? generateSubscriptionsFile() {
    final body = _buildClass(GLQueryType.subscription);
    if (body == null) return null;
    return GLClassModel(
      imports: [
        ..._parser.scalarImportsOfOperationType(GLQueryType.subscription),
        if (observables) "import { Observable } from 'rxjs';",
        "import { GraphLinkResolverBase } from './graph-link-resolver-base.js';",
        "import type { $cacheStoreType } from './graph-link-cache-store.js';",
        "import type { GraphLinkLock } from './graph-link-lock.js';",
        "import { GraphLinkSubscriptionHandler } from './graph-link-subscription-handler.js';",
        "import type { GraphLinkWsAdapter } from './graph-link-ws-adapter.js';",
      ],
      importDepencies: {...schemaTokensFor(GLQueryType.subscription), ..._restTokensFor(GLQueryType.subscription)}.toList(),
      body: body,
    );
  }

  GLClassModel generateClientOnlyFile() {
    final imports = [
      "import type { $adapterType } from './graph-link-adapter.js';",
      "import type { GraphLinkCacheStore } from './graph-link-cache-store.js';",
      "import { InMemoryGraphLinkCacheStore } from './graph-link-in-memory-cache-store.js';",
      "import { GraphLinkLock } from './graph-link-lock.js';",
      if (hasRest) ...[
        "import { glNoGraphQL__ } from './graph-link-rest.js';",
        "import type { GLRestAdapter } from './graph-link-rest.js';",
      ],
      if (_hasOperations(GLQueryType.query))
        "import { GraphLinkQueries } from './graph-link-queries.js';",
      if (_hasOperations(GLQueryType.mutation))
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


  // ── Operation class builder ───────────────────────────────────────────────

  String? _buildClass(GLQueryType type) {
    final restOperations = _restOperations(type);
    final methods = [
      ...buildOperationMethods(type),
      ...restOperations.map(_restSer.operationToMethod),
    ];
    if (methods.isEmpty) return null;

    final base = restOperations.isEmpty ? 'GraphLinkResolverBase' : 'GraphLinkRestResolver';
    return _cg.createClass(
      className: '${classNameFromType(type)} extends $base',
      exported: true,
      statements: [
        if (type != GLQueryType.subscription) ...[
          if (type == GLQueryType.mutation && _parser.hasUploadMutations)
            'private readonly $svMultipartAdapter?: GLMultipartAdapter;',
        ] else ...[
          'private readonly $svHandler: GraphLinkSubscriptionHandler;',
        ],
        _buildConstructor(type),
        if (type == GLQueryType.query && _parser.hasQueryType(GLQueryType.query)) ...[
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
        'adapter: $adapterType',
      if (type != GLQueryType.subscription && _parser.persistedQueriesUseGet)
        'getAdapter: $adapterType',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations)
        'multipartAdapter: GLMultipartAdapter | undefined',
      'fragMap: Record<string, string>',
      'store: $cacheStoreType',
      'tagLocks: Map<string, GraphLinkLock>',
    ];
    final superCall = type == GLQueryType.subscription
        ? '${_cg.callExpression('super', ['store', 'tagLocks', 'fragMap'])};'
        : '${_cg.callExpression('super', ['store', 'tagLocks', 'fragMap', 'adapter', if (_parser.persistedQueriesUseGet) 'getAdapter'])};';
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
    return _cg.createMethod(
      methodName: 'private _buildPayload',
      returnType: 'GraphLinkPayload',
      arguments: [
        'partQueries: GraphLinkPartialQuery[]',
        'operationName: string',
        'directives: string',
      ],
      statements: [
        _cg.constDecl('variables', '{}', type: 'Record<string, unknown>'),
        _cg.forEachLoop(
          variable: 'pq',
          iterable: 'partQueries',
          statements: ['Object.assign(variables, pq.variables);'],
        ),
        'let query = `query \${operationName}`;',
        _cg.constDecl('args', 'new Set(partQueries.flatMap(pq => pq.argumentDeclarations))'),
        _cg.ifStatement(
          condition: 'args.size > 0',
          ifBlockStatements: ["query += `(\${Array.from(args).join(', ')})`;"],
        ),
        _cg.ifStatement(condition: 'directives', ifBlockStatements: ['query += directives;']),
        "query += '{';",
        _cg.forEachLoop(
          variable: 'pq',
          iterable: 'partQueries',
          statements: ["query += pq.query + ' ';"],
        ),
        "query += '}';",
        _cg.constDecl('fragNames', 'new Set(partQueries.flatMap(pq => Array.from(pq.fragmentNames)))'),
        "query += Array.from(fragNames).map(n => this.$svFragMap[n]!).join('');",
        'return { query, operationName, variables };',
      ],
    );
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
        _cg.constDecl('result', 'JSON.parse(data)'),
        _cg.constDecl("dataMap", "(result['data'] as Record<string, unknown>) ?? {}", type: "Record<string, unknown>"),
        _cg.forEachLoop(
          variable: 'q',
          iterable: 'remainingQueries',
          statements: [
            _cg.ifStatement(
              condition: 'q.ttl > 0 && dataMap[q.elementKey] != null',
              ifBlockStatements: [
                _cg.constDecl('entry', 'new GraphLinkCacheEntry(JSON.stringify(dataMap[q.elementKey]), Date.now() + q.ttl * 1000)'),
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
        _cg.constDecl("fullResponse", "{ 'data': result['data'] != null ? dataMap : null, 'errors': Array.isArray(result['errors']) && result['errors'].length > 0 ? result['errors'] : null }", type: "Record<string, unknown>"),
        _cg.ifStatement(
          condition: 'captureErrors',
          ifBlockStatements: ['return fullResponse;'],
        ),
        _cg.constDecl("errors", "result['errors'] as unknown[] | null | undefined"),
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
    final hasQueries = _hasOperations(GLQueryType.query);
    final hasMutations = _hasOperations(GLQueryType.mutation);
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
        'readonly store: $cacheStoreType;',
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
      if (_hasGraphQL) 'adapter: $adapterType',
      if (_hasGraphQL && _parser.persistedQueriesUseGet) 'getAdapter: $adapterType',
      if (hasSubs) 'wsAdapter: GraphLinkWsAdapter',
      if (hasRest) 'restAdapter: GLRestAdapter',
      if (hasMutations && _parser.hasUploadMutations)
        'multipartAdapter?: GLMultipartAdapter',
      'store?: $cacheStoreType',
    ];
    final adapterRef = _hasGraphQL ? 'adapter' : 'glNoGraphQL__';
    final getAdapterRef = _hasGraphQL ? 'getAdapter' : 'glNoGraphQL__';

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
        _cg.forEachLoop(
          variable: 'tag',
          iterable: '[$allTags]',
          statements: ['this.$svTagLocks.set(tag, new GraphLinkLock());'],
        ),
        if (hasQueries) ...[
          'this.queries = new ${classNameFromType(GLQueryType.query)}($adapterRef,${_parser.persistedQueriesUseGet ? ' $getAdapterRef,' : ''} this.$svFragMap, this.store, this.$svTagLocks);',
          if (_restOperations(GLQueryType.query).isNotEmpty) 'this.queries.restAdapter = restAdapter;',
        ],
        if (hasMutations) ...[
          _parser.hasUploadMutations
            ? 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}($adapterRef,${_parser.persistedQueriesUseGet ? ' $getAdapterRef,' : ''} multipartAdapter, this.$svFragMap, this.store, this.$svTagLocks);'
            : 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}($adapterRef,${_parser.persistedQueriesUseGet ? ' $getAdapterRef,' : ''} this.$svFragMap, this.store, this.$svTagLocks);',
          if (_restOperations(GLQueryType.mutation).isNotEmpty) 'this.mutations.restAdapter = restAdapter;',
        ],
        if (hasSubs)
          'this.subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, this.$svFragMap, this.store, this.$svTagLocks);',
      ],
    );
  }

  // ── Adapters file ─────────────────────────────────────────────────────────

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

  GLParser get parser => _parser;

  TypeScriptCodeGenUtils get cg => _cg;
}
