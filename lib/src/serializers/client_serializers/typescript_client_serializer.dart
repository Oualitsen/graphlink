import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript_client_constants.dart';
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

  // Safe local variable names
  String get _svOperationName => _cg.safeLocalVar('operationName');
  String get _svVariables => _cg.safeLocalVar('variables');
  String get _svPartialQueries => _cg.safeLocalVar('partialQueries');
  String get _svResponseMap => _cg.safeLocalVar('responseMap');
  String get _svStaleData => _cg.safeLocalVar('staleData');
  String get _svCacheFutures => _cg.safeLocalVar('cacheFutures');
  String get _svRemaining => _cg.safeLocalVar('remaining');
  String get _svRemainingCount => _cg.safeLocalVar('remainingCount');
  String get _svPayload => _cg.safeLocalVar('payload');
  String get _svResponseText => _cg.safeLocalVar('responseText');
  String get _svResponse => _cg.safeLocalVar('response');
  String get _svResult => _cg.safeLocalVar('result');
  String get _svData => _cg.safeLocalVar('data');
  String get _svQuery => _cg.safeLocalVar('query');
  String get _svFragsValues => _cg.safeLocalVar('fragsValues');
  String get _svFragMap => _cg.safeLocalVar('fragMap');
  String get _svTagLocks => _cg.safeLocalVar('tagLocks');
  String get _svStore => _cg.safeLocalVar('store');
  String get _svAdapter => _cg.safeLocalVar('adapter');
  String get _svHandler => _cg.safeLocalVar('handler');
  String get _svMultipartAdapter => _cg.safeLocalVar('multipartAdapter');
  String get _svMap => _cg.safeLocalVar('map');
  String get _svParts => _cg.safeLocalVar('parts');
  String get _svSlot => _cg.safeLocalVar('slot');
  String get _svAllParts => _cg.safeLocalVar('allParts');
  String get _svGen => _cg.safeLocalVar('gen');

  TypeScriptClientSerializer(
    this._parser,
    GLSerializer tsSerializer, {
    this.generateDefaultWsAdapter = true,
    this.observables = false,
  }) : super(tsSerializer, GLGraphqlSerializer(_parser, false));

  @override
  String renderQueryMethod(GLQueryDefinition def) => _queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) => _mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) => _mutationToMultipartMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) => _subscriptionToMethod(def);

  bool get _hasFullResponseSupport =>
      _parser.getTypeByName('GraphLinkError') != null;

  String _returnTypeName(GLQueryDefinition def) {
    if (def.isCaptureErrors(_parser) && _hasFullResponseSupport) {
      return def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    }
    return def.getGeneratedTypeDefinition().tokenInfo.token;
  }

  // ── Top-level client file ─────────────────────────────────────────────────

  @override
  GLClassModel generateClient() {
    final imports = _buildImports();
    final buffer = StringBuffer();

    buffer.writeln(_adapterTypeAlias());
    buffer.writeln(tsCacheStore);
    buffer.writeln(tsCacheInfra);
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

  // ── Resolver base class ───────────────────────────────────────────────────

  String _resolverBase() {
    return _cg.createClass(
      className: '_ResolverBase',
      exported: false,
      statements: [
        'protected readonly $_svStore: $_cacheStoreType;',
        'protected readonly $_svTagLocks: Map<string, _Lock>;',
        'protected readonly $_svAdapter?: $_adapterType;',
        _cg.createMethod(
          methodName: 'constructor',
          arguments: ['store: $_cacheStoreType', 'tagLocks: Map<string, _Lock>', 'adapter?: $_adapterType'],
          statements: [
            'this.$_svStore = store;',
            'this.$_svTagLocks = tagLocks;',
            'this.$_svAdapter = adapter;',
          ],
        ),
        _cg.createMethod(
          methodName: '_glCallAdapter',
          async: true,
          returnType: 'string',
          arguments: ['payload: GraphLinkPayload'],
          statements: [
            if (_parser.operationNameAsParameter)
              'return await this.$_svAdapter!(JSON.stringify(payload), payload.operationName);'
            else
              'return await this.$_svAdapter!(JSON.stringify(payload));'
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
          returnType: '_GraphLinkCacheEntry | null',
          statements: [
            'const result = await this.$_svStore.get(key);',
            _cg.ifStatement(
              condition: 'result !== null',
              ifBlockStatements: [
                'const entry = _GraphLinkCacheEntry.fromJson(JSON.parse(result));',
                _cg.ifStatement(
                  condition: 'entry.isExpired',
                  ifBlockStatements: [
                    _cg.ifStatement(
                      condition: 'staleIfOffline',
                      ifBlockStatements: ['return entry.asStale();'],
                    ),
                    'void this.$_svStore.invalidate(key);',
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
              'const lock = this.$_svTagLocks.get(tag)!;',
              'await lock.synchronized(async () => {',
              '  const data = await this.$_svStore.get(tagKey);',
              _cg.ifStatement(
                condition: 'data !== null',
                ifBlockStatements: [
                  'const entry = _GraphLinkTagEntry.decode(data);',
                  _cg.forEachLoop(
                    variable: 'k',
                    iterable: 'entry.keys',
                    statements: ['await this.$_svStore.invalidate(k);'],
                  ),
                  'await this.$_svStore.invalidate(tagKey);',
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
              'const lock = this.$_svTagLocks.get(tag)!;',
              'await lock.synchronized(async () => {',
              '  const data = await this.$_svStore.get(tagKey);',
              '  const entry = data !== null ? _GraphLinkTagEntry.decode(data) : new _GraphLinkTagEntry(new Set());',
              '  entry.add(key);',
              '  await this.$_svStore.set(tagKey, entry.encode());',
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
              'const lock = this.$_svTagLocks.get(tag) ?? (() => { const l = new _Lock(); this.$_svTagLocks.set(tag, l); return l; })();',
              'await lock.synchronized(async () => {',
              '  const data = await this.$_svStore.get(tagKey);',
              _cg.ifStatement(
                condition: 'data !== null',
                ifBlockStatements: [
                  '  const entry = _GraphLinkTagEntry.decode(data);',
                  '  entry.remove(key);',
                  _cg.ifStatement(
                    condition: 'entry.keys.size === 0',
                    ifBlockStatements: ['await this.$_svStore.invalidate(tagKey);'],
                    elseBlockStatements: [
                      'await this.$_svStore.set(tagKey, entry.encode());',
                    ],
                  ),
                ],
              ),
              '});',
            ]),
          ],
        ),
      ],
    );
  }

  // ── Queries class ─────────────────────────────────────────────────────────

  String? _buildClass(GLQueryType type) {
    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

    return _cg.createClass(
      className: '${classNameFromType(type)} extends _ResolverBase',
      exported: false,
      statements: [
        if (type != GLQueryType.subscription) ...[
          if (type == GLQueryType.mutation && _parser.hasUploadMutations)
            'private readonly $_svMultipartAdapter?: GLMultipartAdapter;',
        ] else ...[
          'private readonly $_svHandler: _SubscriptionHandler;',
        ],
        if (type == GLQueryType.query) 'private readonly $_svFragMap: Record<string, string>;',
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
      if (type == GLQueryType.query) 'fragMap: Record<string, string>',
      'store: $_cacheStoreType',
      'tagLocks: Map<string, _Lock>',
    ];
    final superCall = type == GLQueryType.subscription
        ? 'super(store, tagLocks);'
        : 'super(store, tagLocks, adapter);';
    return _cg.createMethod(
      methodName: 'constructor',
      arguments: args,
      statements: [
        superCall,
        if (type == GLQueryType.subscription) ...[
          'this.$_svHandler = new _SubscriptionHandler(adapter);',
        ] else ...[
          if (type == GLQueryType.mutation && _parser.hasUploadMutations)
            'this.$_svMultipartAdapter = multipartAdapter;',
        ],
        if (type == GLQueryType.query) 'this.$_svFragMap = fragMap;',
      ],
    );
  }

  String _buildPayloadMethod() {
    return '''
private _buildPayload(
  partQueries: _GraphLinkPartialQuery[],
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
  query += Array.from(fragNames).map(n => this.$_svFragMap[n]!).join('');
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
        'remainingQueries: _GraphLinkPartialQuery[]',
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
                'const entry = new _GraphLinkCacheEntry(JSON.stringify(dataMap[q.elementKey]), Date.now() + q.ttl * 1000);',
                'void this.$_svStore.set(q.cacheKey!, JSON.stringify(entry.toJson()));',
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

  // ── Query method ──────────────────────────────────────────────────────────

  String _queryToMethod(GLQueryDefinition def) {
    final returnTypeName = _returnTypeName(def);
    final fullResponseTypeName = def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final isCE = def.isCaptureErrors(_parser);
    final cacheHitValue = isCE ? '{ data: $_svResponseMap, errors: null }' : '$_svResponseMap';
    final parseAndCacheCall = isCE
        ? 'this._parseAndCache($_svResponseText, $_svResponseMap, $_svRemaining, true)'
        : 'this._parseAndCache($_svResponseText, $_svResponseMap, $_svRemaining)';

    final args = _getMethodArgs(def);
    final dividedQueries = gqlSerializer.divideQueryDefinition(def, _parser);
    final hasFrags = def.fragments(_parser).isNotEmpty;
    final directives = gqlSerializer
        .serializeDirectiveValueList(def.getDirectives(skipGenerated: true));

    final innerStatements = [
      "const $_svOperationName = '${def.tokenInfo}';",
      _generateVariables(def),
      'const $_svPartialQueries = [',
      ...dividedQueries.map((dq) => '  ${_serializePartialQuery(dq, hasFrags)},'),
      '];',
      'const $_svResponseMap: Record<string, unknown> = {};',
      'const $_svStaleData: Record<string, unknown> = {};',
      'const $_svCacheFutures = $_svPartialQueries',
      '  .filter(pq => pq.ttl > 0)',
      '  .map(pq => this._getFromCache(pq.cacheKey!, pq.tags, pq.staleIfOffline).then(entry => {',
      '    if (!entry) return;',
      '    if (entry.stale) $_svStaleData[pq.elementKey] = JSON.parse(entry.data);',
      '    else $_svResponseMap[pq.elementKey] = JSON.parse(entry.data);',
      '  }).catch(() => {}));',
      'await Promise.all($_svCacheFutures);',
      'const $_svRemaining = $_svPartialQueries.filter(pq => !(pq.elementKey in $_svResponseMap));',
      _cg.ifStatement(
        condition: '$_svRemaining.length === 0',
        ifBlockStatements: [
          '${observables ? 'subscriber.next' : 'return'}($cacheHitValue as unknown as $returnTypeName);',
          if (observables) 'subscriber.complete(); return;',
        ],
      ),
      'const $_svPayload = this._buildPayload($_svRemaining, $_svOperationName, ${directives.isEmpty ? "''" : "'${directives}'"}); ',
      _cg.tryCatchFinally(
        tryStatements: [
          'const $_svResponseText = await this._glCallAdapter($_svPayload);',
          'const $_svResult = $parseAndCacheCall as unknown as $fullResponseTypeName;',
          if (observables) ...[
            isCE ? 'subscriber.next($_svResult);' : "subscriber.next($_svResult['data'] as $returnTypeName);",
            'subscriber.complete();',
          ] else
            isCE ? 'return $_svResult;' : "return $_svResult['data'] as $returnTypeName;",
        ],
        catchVariable: 'e',
        catchStatements: [
          'Object.assign($_svResponseMap, $_svStaleData);',
          'const $_svRemainingCount = $_svPartialQueries.filter(pq => !(pq.elementKey in $_svResponseMap)).length;',
          _cg.ifStatement(
            condition: '$_svRemainingCount > 0',
            ifBlockStatements: [
              observables ? 'subscriber.error(e); return;' : 'throw e;',
            ],
          ),
          if (observables) ...[
            'subscriber.next($cacheHitValue as unknown as $returnTypeName);',
            'subscriber.complete();',
          ] else
            'return $cacheHitValue as unknown as $returnTypeName;',
        ],
      ),
    ];

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return new Observable<$returnTypeName>(subscriber => {',
          '  (async () => {',
          ...innerStatements.map((s) => '    $s'),
          '  })();',
          '});',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: innerStatements,
    );
  }

  // ── Mutation method ───────────────────────────────────────────────────────

  String _mutationToMethod(GLQueryDefinition def) {
    if (isUploadMutation(def)) return _mutationToMultipartMethod(def);

    final returnTypeName = _returnTypeName(def);
    final fullResponseTypeName = def.getFullResponseTypeDefinition(_parser).tokenInfo.token;
    final isCaptureErrors = def.isCaptureErrors(_parser);
    final args = _getMethodArgs(def);
    final invalidation = _serializeInvalidation(def);

    final statements = <String>[
      "const $_svOperationName = '${def.tokenInfo}';",
      _generateVariables(def),
      "const $_svQuery = '${buildQueryString(def)}';",
    ];

    statements.addAll([
      "const $_svPayload: GraphLinkPayload = { query: $_svQuery, operationName: $_svOperationName, variables: $_svVariables };",
      "const $_svResponse = await this._glCallAdapter($_svPayload);",
      "const $_svResult = JSON.parse($_svResponse) as $fullResponseTypeName;",
      if (isCaptureErrors)
        "if (!($_svResult as any)['errors']) ($_svResult as any)['errors'] = null;",
      if (!isCaptureErrors)
        "if ($_svResult['errors']) ${observables ? "{ subscriber.error($_svResult['errors']); return; }" : "throw $_svResult['errors'] as GraphLinkError[];"}",
      if (invalidation.isNotEmpty)
        isCaptureErrors ? "if (!($_svResult as any)['errors']) { $invalidation }" : invalidation,
      if (observables) ...[
        isCaptureErrors ? "subscriber.next($_svResult);" : "subscriber.next($_svResult['data'] as $returnTypeName);",
        "subscriber.complete();",
      ] else
        isCaptureErrors ? "return $_svResult;" : "return $_svResult['data'] as $returnTypeName;",
    ]);

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return new Observable<$returnTypeName>(subscriber => {',
          '  (async () => {',
          ...statements.map((s) => '    $s'),
          '  })();',
          '});',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: statements,
    );
  }

  // ── Multipart mutation method ─────────────────────────────────────────────

  String _mutationToMultipartMethod(GLQueryDefinition def) {
    final returnTypeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    final args = _getMethodArgs(def);
    final invalidation = _serializeInvalidation(def);
    final uploadNames = _parser.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();

    final statements = <String>[
      "const $_svOperationName = '${def.tokenInfo}';",
      _generateVariables(def, nullifyUploads: true),
      "const $_svQuery = '${buildQueryString(def)}';",
    ];

    statements.addAll([
      "const $_svMap: Record<string, string[]> = {};",
      "const $_svParts: Record<string, unknown> = {};",
      "let $_svSlot = 0;",
    ]);

    for (final arg in uploadArgs) {
      final name = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.addAll([
          "for (let _i = 0; _i < args.$name.length; _i++) {",
          "  $_svMap[String($_svSlot + _i)] = ['variables.$name.' + _i];",
          "  $_svParts[String($_svSlot + _i)] = args.$name[_i];",
          "}",
          "$_svSlot += args.$name.length;",
        ]);
      } else {
        statements.addAll([
          "$_svMap[String($_svSlot)] = ['variables.$name'];",
          "$_svParts[String($_svSlot)] = args.$name;",
          "$_svSlot++;",
        ]);
      }
    }

    final innerStatements = [
      "const $_svAllParts: Record<string, unknown> = {",
      "  'operations': JSON.stringify({ query: $_svQuery, operationName: $_svOperationName, variables: $_svVariables }),",
      "  'map': JSON.stringify($_svMap),",
      "  ...$_svParts,",
      "};",
      "const $_svResponse = await this.$_svMultipartAdapter!($_svAllParts, onProgress);",
      "const $_svResult = JSON.parse($_svResponse);",
      "if ($_svResult['errors']) ${observables ? "{ subscriber.error($_svResult['errors']); return; }" : "throw $_svResult['errors'] as GraphLinkError[];"}",
      if (invalidation.isNotEmpty) invalidation,
      if (observables) ...[
        "subscriber.next($_svResult['data'] as $returnTypeName);",
        "subscriber.complete();",
      ] else
        "return $_svResult['data'] as $returnTypeName;",
    ];
    statements.addAll(innerStatements);

    if (observables) {
      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        async: false,
        arguments: args.isEmpty ? null : args,
        statements: [
          'return new Observable<$returnTypeName>(subscriber => {',
          '  (async () => {',
          ...statements.map((s) => '    $s'),
          '  })();',
          '});',
        ],
      );
    }

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: returnTypeName,
      async: true,
      arguments: args.isEmpty ? null : args,
      statements: statements,
    );
  }

  // ── Subscription method ───────────────────────────────────────────────────

  String _subscriptionToMethod(GLQueryDefinition def) {
    final returnTypeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    final queryArgs = _getMethodArgs(def);

    final statements = <String>[_generateVariables(def)];
    statements.add("const $_svQuery = '${buildQueryString(def)}';");

    statements.addAll([
      "const $_svPayload: GraphLinkPayload = {",
      "  query: $_svQuery,",
      "  operationName: '${def.tokenInfo}',",
      "  variables: $_svVariables,",
      "};",
      "const $_svGen = this.$_svHandler.handle($_svPayload);",
    ]);

    if (observables) {
      statements.addAll([
        "return new Observable<$returnTypeName>(subscriber => {",
        "  (async () => {",
        "    try {",
        "      for await (const $_svData of $_svGen) {",
        "        subscriber.next($_svData as unknown as $returnTypeName);",
        "      }",
        "      subscriber.complete();",
        "    } catch (e) {",
        "      subscriber.error(e);",
        "    }",
        "  })();",
        "  return () => { void $_svGen.return(undefined); };",
        "});",
      ]);

      return _cg.createMethod(
        methodName: def.tokenInfo.token,
        returnType: 'Observable<$returnTypeName>',
        arguments: queryArgs.isEmpty ? null : queryArgs,
        statements: statements,
      );
    }

    statements.addAll([
      "(async () => {",
      "  try {",
      "    for await (const $_svData of $_svGen) {",
      "      onEvent($_svData as unknown as $returnTypeName);",
      "    }",
      "  } catch (e) {",
      "    onError?.(e);",
      "  }",
      "})();",
      "return () => { void $_svGen.return(undefined); };",
    ]);

    final allArgs = [
      ...queryArgs,
      'onEvent: (data: $returnTypeName) => void',
      'onError?: (error: unknown) => void',
    ];

    return _cg.createMethod(
      methodName: def.tokenInfo.token,
      returnType: '() => void',
      arguments: allArgs,
      statements: statements,
    );
  }

  // ── Partial query serialization ───────────────────────────────────────────

  String _serializePartialQuery(DividedQuery dq, bool hasFrags) {
    final varBuffer = StringBuffer('{');
    for (final v in dq.variables) {
      if (!v.startsWith(r'$')) continue;
      final argName = v.substring(1);
      varBuffer.write(" '$argName': $_svVariables['$argName'],");
    }
    varBuffer.write(' }');

    final fragSet = hasFrags && dq.fragmentNames.isNotEmpty
        ? 'new Set([${dq.fragmentNames.map((n) => "'$n'").join(', ')}])'
        : 'new Set<string>()';

    return '''new _GraphLinkPartialQuery(
    '${dq.query}',
    $varBuffer,
    ${dq.cacheTTL},
    [${dq.tags.map((t) => "'$t'").join(', ')}],
    '${dq.operationName}',
    '${dq.elementKey}',
    $fragSet,
    [${dq.argumentDeclarations.map((a) => "'${a}'").join(', ')}],
    ${dq.staleIfOffline},
  )''';
  }

  // ── Variables ─────────────────────────────────────────────────────────────

  String _generateVariables(GLQueryDefinition def, {bool nullifyUploads = false}) {
    if (def.arguments.isEmpty) {
      return 'const $_svVariables: Record<string, unknown> = {};';
    }
    final uploadNames = nullifyUploads ? _parser.uploadScalarNames : <String>{};
    final buffer = StringBuffer(
        'const $_svVariables: Record<string, unknown> = {\n');
    for (final arg in def.arguments) {
      final name = arg.dartArgumentName;
      final isUpload = uploadNames.contains(arg.type.firstType.token);
      if (isUpload) {
        buffer.writeln("  '$name': ${arg.type.isList ? 'args.$name.map(() => null)' : 'null'},");
      } else {
        buffer.writeln("  '$name': args.$name,");
      }
    }
    buffer.write('};');
    return buffer.toString();
  }

  // ── Method arguments ──────────────────────────────────────────────────────

  List<String> _getMethodArgs(GLQueryDefinition def) {
    final result = <String>[];
    if (def.arguments.isNotEmpty) {
      final fields = def.arguments.map((arg) {
        final tsType = _resolveArgType(arg);
        return '${arg.dartArgumentName}: $tsType';
      }).join('; ');
      result.add('args: { $fields }');
    }
    if (isUploadMutation(def)) {
      result.add('onProgress?: UploadProgressCallback');
    }
    return result;
  }

  String _resolveArgType(arg) {
    final uploadNames = _parser.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'GLUpload[]' : 'GLUpload';
    }
    return serializer.serializeType(arg.type, false);
  }

  // ── Invalidation ─────────────────────────────────────────────────────────

  String _serializeInvalidation(GLQueryDefinition def) {
    if (shouldInvalidateAll(def)) {
      return 'await this.$_svStore.invalidateAll();';
    }
    final tags = getInvalidationTags(def);
    if (tags.isNotEmpty) {
      return 'await this._invalidateByTags([${tags.map((t) => "'$t'").join(', ')}]);';
    }
    return '';
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
        'private readonly $_svFragMap: Record<string, string> = {};',
        'private readonly $_svTagLocks: Map<string, _Lock> = new Map();',
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

    final fragAssignments = _parser.fragments.values
        .map((f) =>
            "this.$_svFragMap['${f.tokenInfo}'] = '${gqlSerializer.serializeFragmentDefinitionBase(f)}';")
        .toList();

    return _cg.createMethod(
      methodName: 'constructor',
      arguments: args,
      statements: [
        ...fragAssignments,
        'this.store = store ?? new $_inMemoryCacheStoreType();',
        "for (const tag of [$allTags]) this.$_svTagLocks.set(tag, new _Lock());",
        if (hasQueries)
          'this.queries = new ${classNameFromType(GLQueryType.query)}(adapter, this.$_svFragMap, this.store, this.$_svTagLocks);',
        if (hasMutations)
          _parser.hasUploadMutations
            ? 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, multipartAdapter, this.store, this.$_svTagLocks);'
            : 'this.mutations = new ${classNameFromType(GLQueryType.mutation)}(adapter, this.store, this.$_svTagLocks);',
        if (hasSubs)
          'this.subscriptions = new ${classNameFromType(GLQueryType.subscription)}(wsAdapter, this.store, this.$_svTagLocks);',
      ],
    );
  }

  // ── Adapters file ─────────────────────────────────────────────────────────

  GLClassModel? generateAdaptersFile(TypeScriptHttpAdapter httpAdapter) {
    if (httpAdapter == TypeScriptHttpAdapter.none) return null;
    final hasUploads = _parser.hasUploadMutations;
    final buffer = StringBuffer();
    buffer.writeln(
      "import type { $_adapterType } from './graph-link-client.js';",
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
    if (httpAdapter == TypeScriptHttpAdapter.axios) buffer.writeln(tsAxiosAdapter(_parser.operationNameAsParameter));
    return GLClassModel(body: buffer.toString());
  }

  // ── Uploads file (v2) ────────────────────────────────────────────────────

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: tsUploadsFile);

  // ── GLClientSerilaizer overrides ──────────────────────────────────────────

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

  String get fileExtension => ".ts";
}
