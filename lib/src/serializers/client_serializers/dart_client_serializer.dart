import 'dart:io';
import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/dart_code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/gl_client_serilaizer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';

const _operationNameParam = "operationName";
const _cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';

class DartClientSerializer extends GLClientSerilaizer {
  final GLParser _parser;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;
  final codeGenUtils = DartCodeGenUtils();

  DartClientSerializer(this._parser, GLSerializer dartSerializer,
      {this.generateAdapters = true, this.httpAdapter = DartHttpAdapter.http})
      : super(dartSerializer);

  bool get _useDio => httpAdapter == DartHttpAdapter.dio;

  // Safe generated local variable names — avoids clashing with user-defined method arguments.
  String get _svOperationName => codeGenUtils.safeLocalVar('operationName');
  String get _svFragsValues => codeGenUtils.safeLocalVar('fragsValues');
  String get _svQuery => codeGenUtils.safeLocalVar('query');
  String get _svPayload => codeGenUtils.safeLocalVar('payload');
  String get _svVariables => codeGenUtils.safeLocalVar('variables');
  String get _svResponse => codeGenUtils.safeLocalVar('response');
  String get _svResult => codeGenUtils.safeLocalVar('result');
  String get _svData => codeGenUtils.safeLocalVar('data');
  String get _svPartialQueries => codeGenUtils.safeLocalVar('partialQueries');
  String get _svResponseMap => codeGenUtils.safeLocalVar('responseMap');
  String get _svStaleData => codeGenUtils.safeLocalVar('staleData');
  String get _svCacheFetchFutures => codeGenUtils.safeLocalVar('cacheFetchFutures');
  String get _svRemaining => codeGenUtils.safeLocalVar('remaining');
  String get _svRemainingQueries => codeGenUtils.safeLocalVar('remainingQueries');
  String get _svResponseText => codeGenUtils.safeLocalVar('responseText');
  String get _svHandler => codeGenUtils.safeLocalVar('handler');
  String get _svFragMap => codeGenUtils.safeLocalVar('fragmentMap');
  String get _svTagLocks => codeGenUtils.safeLocalVar('tagLocks');
  String get _svStore => codeGenUtils.safeLocalVar('store');
  String get _svAdapter => codeGenUtils.safeLocalVar('adapter');
  String get _svUploadConverter => codeGenUtils.safeLocalVar('uploadConverter');
  String get _svUploadAdapter => codeGenUtils.safeLocalVar('uploadAdapter');
  String get _svMultipartMap => codeGenUtils.safeLocalVar('multipartMap');
  String get _svSlot => codeGenUtils.safeLocalVar('slot');
  String get _svFileParts => codeGenUtils.safeLocalVar('fileParts');
  String get _svParts => codeGenUtils.safeLocalVar('parts');

  @override
  @override
  GLClassModel generateClient(String importPrefix) {
    final dartImports = [
      "import 'dart:convert';",
      "import 'dart:async';",
      "import 'dart:math';",
      if (generateAdapters)
        _useDio
            ? "import 'graph_link_dio_adapter.dart';"
            : "import 'graph_link_http_adapter.dart';",
      if (generateAdapters && _parser.hasSubscriptions)
        "import 'graph_link_websocket_adapter.dart';",
      ...serializeImports(_parser, importPrefix)
          .split('\n')
          .where((l) => l.trim().isNotEmpty),
      if (_parser.hasMutations && _parser.hasUploadMutations)
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

    GLQueryType.values
        .map((e) => generateQueriesClassByType(e))
        .where((e) => e != null)
        .map((e) => e!)
        .forEach((line) {
      buffer.writeln(line);
    });

    buffer.writeln(
        codeGenUtils.createClass(className: "_ResolverBase", statements: [
      'late final GraphLinkCacheStore $_svStore;',
      'late final Map<String, _Lock> $_svTagLocks;',
      codeGenUtils.createMethod(
          methodName: '_ResolverBase',
          namedArguments: false,
          arguments: ['GraphLinkCacheStore store', 'Map<String, _Lock> locks'],
          statements: [
            'this.$_svStore = store;',
            'this.$_svTagLocks = locks;',
          ]),
      codeGenUtils.createMethod(
          methodName: "_getFromCache",
          async: true,
          namedArguments: false,
          arguments: ['String key', 'List<String> tags', 'bool staleIfOffline'],
          returnType: 'Future<_GraphLinkCacheEntry?>',
          statements: [
            'var result = await $_svStore.get(key);',
            codeGenUtils
                .ifStatement(condition: 'result != null', ifBlockStatements: [
              'var entryMap = jsonDecode(result);',
              'var entry = _GraphLinkCacheEntry.fromJson(entryMap);',
              codeGenUtils.ifStatement(
                  condition: 'entry.isExpired',
                  ifBlockStatements: [
                    codeGenUtils.ifStatement(
                        condition: 'staleIfOffline',
                        ifBlockStatements: ['return entry.asStale();']),
                    '$_svStore.invalidate(key);',
                    codeGenUtils.ifStatement(
                        condition: 'tags.isNotEmpty',
                        ifBlockStatements: [
                          '_removeKeyFromTags(key, tags);',
                        ]),
                    'return null;',
                  ],
                  elseBlockStatements: [
                    "return entry;"
                  ]),
            ]),
            'return null;'
          ]),
      codeGenUtils.createMethod(
          methodName: "_invalidateByTags",
          namedArguments: false,
          arguments: ["List<String> tags"],
          returnType: "Future<void>",
          async: true,
          statements: [
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = $_svTagLocks[tag]!;',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await $_svStore.get(tagKey);',
                codeGenUtils
                    .ifStatement(condition: "data != null", ifBlockStatements: [
                  'final entry = _GraphLinkTagEntry.decode(data);',
                  codeGenUtils.forEachLoop(
                      variable: 'key',
                      iterable: 'entry.keys',
                      statements: [
                        'await $_svStore.invalidate(key);',
                      ]),
                  'await $_svStore.invalidate(tagKey);'
                ])
              ]),
              ');'
            ])
          ]),
      codeGenUtils.createMethod(
          methodName: "_addKeyToTags",
          namedArguments: false,
          arguments: ["String key", "List<String> tags"],
          returnType: "Future<void>",
          async: true,
          statements: [
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = $_svTagLocks[tag]!;',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await $_svStore.get(tagKey);',
                'final entry = data != null ? _GraphLinkTagEntry.decode(data) : _GraphLinkTagEntry({});',
                'entry.add(key);',
                'await $_svStore.set(tagKey, entry.encode());'
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
            codeGenUtils
                .forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = $_svTagLocks.putIfAbsent(tag, () => _Lock());',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await $_svStore.get(tagKey);',
                codeGenUtils
                    .ifStatement(condition: "data != null", ifBlockStatements: [
                  'final entry = _GraphLinkTagEntry.decode(data);',
                  'entry.remove(key);',
                  codeGenUtils.ifStatement(
                      condition: 'entry.keys.isEmpty',
                      ifBlockStatements: [
                        'await $_svStore.invalidate(tagKey);'
                      ],
                      elseBlockStatements: [
                        'await $_svStore.set(tagKey, entry.encode());'
                      ])
                ])
              ]),
              ');'
            ])
          ])
    ]));

    buffer.writeln(
        codeGenUtils.createClass(className: 'GraphLinkClient', statements: [
      'final $_svFragMap = <String, String>{};',
      'final $_svTagLocks = <String, _Lock>{};',
      if (_parser.hasQueries)
        'late final ${classNameFromType(GLQueryType.query)} queries;',
      if (_parser.hasMutations)
        'late final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_parser.hasSubscriptions)
        'late final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      'late final $_cacheStoreClassName store;',
      codeGenUtils.createMethod(
        methodName: 'GraphLinkClient',
        arguments: [
          'required ${_adapterDeclaration()}',
          if (_parser.hasUploadMutations) ...[
            'GLUploadConverter uploadConverter = _defaultUploadConverter',
            'GLMultipartAdapter? uploadAdapter',
          ],
          if (_parser.hasSubscriptions) 'required GraphLinkWebSocketAdapter wsAdapter',
          '$_cacheStoreClassName? store'
        ],
        namedArguments: true,
        statements: [
          ..._parser.fragments.values.map((value) =>
              "$_svFragMap['${value.tokenInfo}'] = '${_parser.serializer.serializeFragmentDefinitionBase(value)}';"),
          'this.store = store ?? $_inMemorycacheStoreClassName();',
          'final tags = ${_parser.getAllCacheTags().map((e) => e.quote()).toList()};',
          codeGenUtils.forEachLoop(
              variable: 'tag',
              iterable: 'tags',
              statements: ['$_svTagLocks[tag] = _Lock();']),
          if (_parser.hasQueries)
            "queries = ${classNameFromType(GLQueryType.query)}(adapter, $_svFragMap, this.store, $_svTagLocks);",
          if (_parser.hasMutations)
            _parser.hasUploadMutations
                ? "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, uploadConverter, uploadAdapter, $_svFragMap, this.store, $_svTagLocks);"
                : "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, $_svFragMap, this.store, $_svTagLocks);",
          if (_parser.hasSubscriptions)
            "subscriptions = ${classNameFromType(GLQueryType.subscription)}(wsAdapter, $_svFragMap, this.store, $_svTagLocks);",
        ],
      ),
      if (_parser.hasSubscriptions && generateAdapters)
        _fromUrlConstructor(),
      if (generateAdapters)
        _withHttpConstructor(),
    ]));

    buffer.writeln(serializeSubscriptions().ident());
    return GLClassModel(imports: dartImports, body: buffer.toString());
  }

  String _withHttpConstructor() {
    final wsParams = _parser.hasSubscriptions
        ? 'required String wsUrl,\n  Future<Map<String, String>?> Function()? wsHeadersProvider,'
        : '';
    final wsArg = _parser.hasSubscriptions
        ? 'wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider),'
        : '';
    final adapterClass = _useDio ? 'GraphLinkDioAdapter' : 'GraphLinkHttpAdapter';
    const adapterArgs = 'url: url, headersProvider: headersProvider';

    if (_parser.hasUploadMutations) {
      return '''
factory GraphLinkClient.withHttp({
  required String url,
  $wsParams
  Future<Map<String, String>?> Function()? headersProvider,
  $_cacheStoreClassName? store,
}) {
  final _a = $adapterClass($adapterArgs);
  return GraphLinkClient(
    adapter: _a.call,
    uploadConverter: _defaultUploadConverter,
    uploadAdapter: _a.multipartCall,
    $wsArg
    store: store,
  );
}''';
    }

    return '''
GraphLinkClient.withHttp({
  required String url,
  $wsParams
  Future<Map<String, String>?> Function()? headersProvider,
  $_cacheStoreClassName? store,
}) : this(
  adapter: $adapterClass($adapterArgs).call,
  $wsArg
  store: store,
);''';
  }

  String _fromUrlConstructor() {
    final adapterDecl = _adapterDeclaration();
    return '''
GraphLinkClient.fromUrl({
  required $adapterDecl,
  required String wsUrl,
  Future<Map<String, String>?> Function()? wsHeadersProvider,
  $_cacheStoreClassName? store,
}) : this(
  adapter: adapter,
  wsAdapter: DefaultGraphLinkWebSocketAdapter(url: wsUrl, headersProvider: wsHeadersProvider),
  store: store,
);''';
  }

  String _adapterDeclaration() {
    if (_parser.operationNameAsParameter) {
      return 'Future<String> Function(String payload, String $_operationNameParam) adapter';
    }
    return 'Future<String> Function(String payload) adapter';
  }

  @override
  GLClassModel? getQueriesClass(String importPrefix) {
    final body = generateQueriesClassByType(GLQueryType.query);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getMutationsClass(String importPrefix) {
    final body = generateQueriesClassByType(GLQueryType.mutation);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getSubscriptionsClass(String importPrefix) {
    final body = generateQueriesClassByType(GLQueryType.subscription);
    return body != null ? GLClassModel(body: body) : null;
  }

  String? generateQueriesClassByType(GLQueryType type) {
    var queries = _parser.queries.values;
    var queryList = queries
        .where((element) => element.type == type && _parser.hasQueryType(type))
        .toList();
    if (queryList.isEmpty) {
      return null;
    }

    return codeGenUtils.createClass(
        className: "${classNameFromType(type)} extends _ResolverBase",
        statements: [
          'late final Map<String, String> $_svFragMap;',
          declareAdapter(type),
          codeGenUtils.createConstructor(
              className: classNameFromType(type),
              arguments: _declareConstructorArgs(type),
              superArguments: [
                'store',
                _svTagLocks
              ],
              statements: [
                '$_svFragMap = fragmentMap;',
                if (type == GLQueryType.subscription)
                  '$_svHandler = _SubscriptionHandler(adapter);',
              ]),
          ...queryList.map((e) => type == GLQueryType.query
              ? queryToMethod(e)
              : mutationToMethod(e)),
          if (type == GLQueryType.query) ...[
            codeGenUtils.createMethod(
                methodName: "_getFromSource",
                async: true,
                namedArguments: false,
                arguments: ['GraphLinkPayload payload'],
                returnType: 'Future<String>',
                statements: [
                  'return await $_svAdapter(json.encode(payload.toJson()));'
                ]),
            codeGenUtils.createMethod(
                returnType: "GraphLinkPayload",
                namedArguments: false,
                methodName: "_buildPayload",
                arguments: [
                  "List<_GraphLinkPartialQuery> partQueries",
                  "String operationName",
                  "String directives"
                ],
                statements: [
                  "final Map<String, dynamic> variables = {};",
                  codeGenUtils.forEachLoop(
                      variable: "partQuery",
                      iterable: "partQueries",
                      statements: ["variables.addAll(partQuery.variables);"]),
                  'final queryBuilder = StringBuffer("query \${operationName}");',
                  'final args = partQueries.expand((e) => e.argumentDeclarations).toSet();',
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
                      ]),
                  'queryBuilder.write("}");',
                  'final fragments = partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => $_svFragMap[fragName]!).join();',
                  'queryBuilder.write(fragments);',
                  'return GraphLinkPayload(query: queryBuilder.toString(), operationName: operationName, variables: variables);',
                ]),
            codeGenUtils.createMethod(
                methodName: '_parseToObjectAndCache<T>',
                arguments: [
                  'String data',
                  'Map<String, dynamic> cachedResponse',
                  'T Function(Map<String, dynamic> json) parser',
                  'Set<_GraphLinkPartialQuery> remainingQueries',
                ],
                returnType: 'T',
                namedArguments: false,
                statements: [
                  'final result = jsonDecode(data);',
                  codeGenUtils.ifStatement(
                      condition: 'result.containsKey("errors")',
                      ifBlockStatements: [
                        'throw result["errors"].map((error) => GraphLinkError.fromJson(error)).toList();'
                      ]),
                  'final dataMap = result["data"] as Map<String, dynamic>;',
                  codeGenUtils.forEachLoop(
                      variable: 'q',
                      iterable: 'remainingQueries',
                      statements: [
                        codeGenUtils.ifStatement(
                            condition:
                                'q.ttl > 0 && dataMap[q.elementKey] != null',
                            ifBlockStatements: [
                              'final entry = _GraphLinkCacheEntry(jsonEncode(dataMap[q.elementKey]), DateTime.now().millisecondsSinceEpoch + q.ttl * 1000);',
                              '$_svStore.set(q.cacheKey!, jsonEncode(entry.toJson()));',
                              codeGenUtils.ifStatement(
                                  condition: 'q.tags.isNotEmpty',
                                  ifBlockStatements: [
                                    '_addKeyToTags(q.cacheKey!, q.tags);',
                                  ]),
                            ])
                      ]),
                  'dataMap.addAll(cachedResponse);',
                  'return parser.call(dataMap);'
                ]),
          ],
        ]);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      if (type == GLQueryType.subscription)
        'GraphLinkWebSocketAdapter adapter'
      else
        'this.$_svAdapter',
      if (type == GLQueryType.mutation && _parser.hasUploadMutations) ...[
        'this.$_svUploadConverter',
        'this.$_svUploadAdapter',
      ],
      'Map<String, String> fragmentMap',
      'GraphLinkCacheStore store',
      'Map<String, _Lock> $_svTagLocks'
    ];
  }

  String declareAdapter(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
        return "final Future<String> Function(String payload${_parser.operationNameAsParameter ? ', String $_operationNameParam' : ''}) $_svAdapter;";
      case GLQueryType.mutation:
        final base = "final Future<String> Function(String payload${_parser.operationNameAsParameter ? ', String $_operationNameParam' : ''}) $_svAdapter;";
        if (_parser.hasUploadMutations) {
          return "$base\nfinal GLUploadConverter $_svUploadConverter;\nfinal GLMultipartAdapter? $_svUploadAdapter;";
        }
        return base;
      case GLQueryType.subscription:
        return "late final _SubscriptionHandler $_svHandler;";
    }
  }

  String mutationToMethod(GLQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        async: def.type != GLQueryType.subscription,
        statements: [
          if(!_parser.mutationHasUploads(def))
          "const $_svOperationName = '${def.tokenInfo}';",
          if (def.fragments(_parser).isNotEmpty) ...[
            "final $_svFragsValues = [",
            ...def.fragments(_parser).map((e) => '"${e.tokenInfo}",'),
            '].map((fragName) => $_svFragMap[fragName]!).join(' ');'
          ],
          if (def.fragments(_parser).isEmpty)
            "const $_svQuery = '''${_parser.serializer.serializeQueryDefinition(def)}''';"
          else
            "final $_svQuery = '''${_parser.serializer.serializeQueryDefinition(def)} \${$_svFragsValues}''';",
          generateVariables(def),
          if(!_parser.mutationHasUploads(def))
          "final $_svPayload = GraphLinkPayload(query: $_svQuery, operationName: $_svOperationName, variables: $_svVariables);",
          _serializeAdapterCall(def)
        ]);
  }

  String queryToMethod(GLQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        async: true,
        statements: [
          "const $_svOperationName = '${def.tokenInfo}';",
          generateVariables(def),

          // divided query for cache handling

          'final $_svPartialQueries = ${_parser.serializer.divideQueryDefinition(def, _parser).map((e) => serialzePartialQuery(e)).toList()};',
          'final $_svResponseMap = <String, dynamic>{};',
          'final $_svStaleData = <String, dynamic>{};',
          'final $_svCacheFetchFutures = <Future>[];',
          codeGenUtils.forEachLoop(
              variable: "partQuery",
              iterable: "$_svPartialQueries.where((e) => e.ttl > 0)",
              statements: [
                "$_svCacheFetchFutures.add(_getFromCache(partQuery.cacheKey!, partQuery.tags, partQuery.staleIfOffline)",
                ".asStream().where((e) => e != null).map((e) => e!).first.then((entry) ${codeGenUtils.block([
                      codeGenUtils.ifStatement(
                          condition: 'entry.stale',
                          ifBlockStatements: [
                            '$_svStaleData[partQuery.elementKey] = jsonDecode(entry.data);'
                          ],
                          elseBlockStatements: [
                            '$_svResponseMap[partQuery.elementKey] = jsonDecode(entry.data);'
                          ])
                    ])}));"
              ]),
          'await Future.wait($_svCacheFetchFutures.map((f) => f.catchError((_) => null)));',
          'var $_svRemaining = $_svPartialQueries.where((e) => !$_svResponseMap.containsKey(e.elementKey)).toSet();',
          codeGenUtils.ifStatement(
              condition: '$_svRemaining.isEmpty',
              ifBlockStatements: [
                'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson($_svResponseMap);'
              ]),
          "final $_svRemainingQueries = $_svPartialQueries.where((e) => !$_svResponseMap.containsKey(e.elementKey)).toList();",
          "final $_svPayload = _buildPayload($_svRemainingQueries, $_svOperationName, '${_parser.serializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}');",
          codeGenUtils.tryCatchFinally(tryStatements: [
            'final $_svResponseText = await _getFromSource($_svPayload);',
            'return _parseToObjectAndCache($_svResponseText, $_svResponseMap, ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson, $_svRemaining);',
          ], catchStatements: [
            "$_svResponseMap.addAll($_svStaleData);",
            'final remainingCount = $_svPartialQueries.where((e) => !$_svResponseMap.containsKey(e.elementKey)).length;',
            codeGenUtils.ifStatement(
                condition: 'remainingCount > 0',
                ifBlockStatements: [
                  "throw exception;",
                ]),
            'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson($_svResponseMap);'
          ], catchVariable: 'exception'),
        ]);
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return 'await $_svStore.invalidateAll();';
      }
    }

    var tags = def.elements.expand((e) => e.invalidateCacheTags).toSet();
    if (tags.isNotEmpty) {
      return 'await _invalidateByTags(${tags.map((e) => e.quote()).toList()});';
    }
    return '// no tag to invalidate';
  }

  String serialzePartialQuery(DividedQuery e) {
    final varBuffer = StringBuffer('{');
    for (var v in e.variables) {
      varBuffer.writeln();
      var dartArgName = v.substring(1);
      varBuffer.writeln("'${dartArgName}': $_svVariables['${dartArgName}'],");
    }
    varBuffer.write("}");
    return '''
_GraphLinkPartialQuery(
  query: '${e.query}',
  operationName: "${e.operationName}",
  tags: ${e.tags.map((e) => e.quote()).toList()},
  ttl: ${e.cacheTTL},
  elementKey: '${e.elementKey}',
  fragmentNames: ${e.fragmentNames.map((e) => '"${e}"').toSet()},
  argumentDeclarations: ${e.argumentDeclarations.map((e) => '"${e.dolarEscape()}"').toList()},
  variables: ${varBuffer},
  staleIfOffline: ${e.staleIfOffline}
)
''';
  }

  String generateVariables(GLQueryDefinition def) {
    var buffer = StringBuffer("final $_svVariables = <String, dynamic>{");
    buffer.writeln();
    def.arguments
        .map((e) =>
            "'${e.dartArgumentName}': ${_serializeArgumentValue(def, e.token)},")
        .forEach((line) {
      buffer.writeln(line.ident());
    });
    buffer.writeln("};");
    return buffer.toString();
  }

  String _serializeAdapterCall(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return """
return $_svHandler.handle($_svPayload)
.map((e) {
  return ${def.getGeneratedTypeDefinition().tokenInfo.token}.fromJson(e);
});
    """
          .trim()
          .ident();
    }
    if (_parser.mutationHasUploads(def)) {
      return _serializeMultipartAdapterCall(def);
    }
    return """
final $_svResponse = await $_svAdapter(json.encode($_svPayload.toJson())${_parser.operationNameAsParameter ? ', $_svOperationName' : ''});
Map<String, dynamic> $_svResult = jsonDecode($_svResponse);
if ($_svResult.containsKey("errors")) {
  throw $_svResult["errors"].map((error) => GraphLinkError.fromJson(error)).toList();
}
var $_svData = $_svResult["data"];
${_serializeInvalidationCall(def)}
return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson($_svData);
""";
  }

  String _serializeMultipartAdapterCall(GLQueryDefinition def) {
    final uploadNames = _parser.uploadScalarNames;
    final uploadArgs = def.arguments
        .where((a) => uploadNames.contains(a.type.firstType.token))
        .toList();

    final statements = <String>[
      'final $_svMultipartMap = <String, Object>{};',
      'final $_svFileParts = <String, Object>{};',
      'int $_svSlot = 0;',
    ];

    for (final arg in uploadArgs) {
      final name = arg.dartArgumentName;
      if (arg.type.isList) {
        statements.add(codeGenUtils.forEachLoop(
          variable: '_i',
          iterable: 'Iterable.generate($name.length)',
          statements: [
            "$_svMultipartMap['\${$_svSlot + _i}'] = ['variables.$name.\$_i'];",
            "$_svFileParts['\${$_svSlot + _i}'] = $_svUploadConverter($name[_i]);",
          ],
        ));
        statements.add('$_svSlot += $name.length;');
      } else {
        statements.addAll([
          "$_svMultipartMap['\$$_svSlot'] = ['variables.$name'];",
          "$_svFileParts['\$$_svSlot'] = $_svUploadConverter($name);",
          '$_svSlot++;',
        ]);
      }
    }

    statements.addAll([
      "final ${_svParts} = <String, Object>{"
          "\n  'operations': jsonEncode({'query': $_svQuery, 'variables': $_svVariables}),"
          "\n  'map': jsonEncode($_svMultipartMap),"
          "\n  ...${_svFileParts},"
          "\n};",
      'final $_svResponse = await $_svUploadAdapter!(${_svParts}, onProgress);',
      'Map<String, dynamic> $_svResult = jsonDecode($_svResponse);',
      codeGenUtils.ifStatement(
        condition: '$_svResult.containsKey("errors")',
        ifBlockStatements: [
          'throw $_svResult["errors"].map((error) => GraphLinkError.fromJson(error)).toList();',
        ],
      ),
      'var $_svData = $_svResult["data"];',
      _serializeInvalidationCall(def),
      'return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson($_svData);',
    ]);

    return statements.join('\n');
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    if (_parser.uploadScalarNames.contains(arg.type.firstType.token)) {
      if(arg.type.isList) {
        return '${arg.dartArgumentName}.map((e) => null).toList()';
      } else {
        return 'null';
      }
    }
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GLType type) {
    if (_parser.inputTypeRequiresProjection(type) || _parser.isEnum(type.token)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    } else {
      return argName;
    }
  }

  String _getNullableText(GLType type) {
    if (type.nullable) {
      return "?";
    }
    return "";
  }

  List<String> getArguments(GLQueryDefinition def) {
    final args = def.arguments
        .map((e) => "required ${_resolveArgType(e)} ${e.dartArgumentName}")
        .toList();
    if (_parser.mutationHasUploads(def)) {
      args.add('UploadProgressCallback? onProgress');
    }
    if (args.isEmpty) return [];
    return args;
  }

  String _resolveArgType(arg) {
    final uploadNames = _parser.uploadScalarNames;
    if (uploadNames.contains(arg.type.firstType.token)) {
      return arg.type.isList ? 'List<GLUpload>' : 'GLUpload';
    }
    return serializer.serializeType(arg.type, false);
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GLQueryType.subscription) {
      return "Stream<${gen.tokenInfo.token}>";
    }
    return "Future<${gen.tokenInfo.token}>";
  }

  String serializeSubscriptions() {
    if (!_parser.hasSubscriptions) {
      return "";
    }
    return """
$_subscriptionHandler
$_streamSink
$_webSocketAdapter
""";
  }

  String get fileExtension => '.dart';

  GLClassModel generateHttpAdapterFile() {
    if (_parser.hasUploadMutations) {
      stdout.writeln(
        '⚠️  Upload mutations detected with the http adapter.\n'
        '   Progress tracking buffers the entire request body in memory.\n'
        '   For large files, consider switching to the Dio adapter (httpAdapter: "dio").',
      );
    }
    final extraParam = _parser.operationNameAsParameter ? ', String operationName' : '';
    final multipartMethod = _parser.hasUploadMutations ? '''

  Future<String> multipartCall(Map<String, Object> parts, UploadProgressCallback? onProgress) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    final extraHeaders = await headersProvider?.call() ?? {};
    request.headers.addAll(extraHeaders);
    for (final entry in parts.entries) {
      if (entry.value is GLUpload) {
        final u = entry.value as GLUpload;
        request.files.add(http.MultipartFile(
          entry.key, u.stream, u.length ?? 0,
          filename: u.filename,
          contentType: MediaType.parse(u.mimeType),
        ));
      } else {
        request.fields[entry.key] = entry.value as String;
      }
    }

    if (onProgress == null) {
      final streamed = await request.send();
      return (await http.Response.fromStream(streamed)).body;
    }

    // Progress requested: buffer the full body to know total length,
    // then re-stream it with a counting wrapper.
    // Note: the entire request body is held in memory during upload.
    // For large files prefer the Dio adapter which supports native progress.
    final bodyBytes = await request.finalize().toBytes();
    final total = bodyBytes.length;
    int sent = 0;

    const chunkSize = 8192;
    final counted = Stream.fromIterable([
      for (var i = 0; i < bodyBytes.length; i += chunkSize)
        bodyBytes.sublist(i, (i + chunkSize).clamp(0, bodyBytes.length)),
    ]).map((chunk) {
      sent += chunk.length;
      onProgress(sent, total);
      return chunk;
    });

    final raw = http.StreamedRequest('POST', Uri.parse(url));
    raw.headers.addAll(extraHeaders);
    raw.headers['content-type'] = request.headers['content-type']!;
    raw.contentLength = total;
    counted.listen(raw.sink.add, onDone: raw.sink.close);

    final streamed = await raw.send();
    return (await http.Response.fromStream(streamed)).body;
  }''' : '';
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'package:http/http.dart' as http;",
        "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
      ],
      body: """
class GraphLinkHttpAdapter {
  final String url;
  final Future<Map<String, String>?> Function()? headersProvider;

  GraphLinkHttpAdapter({
    required this.url,
    this.headersProvider,
  });

  Future<String> call(String payload$extraParam) async {
    final extraHeaders = await headersProvider?.call();
    final requestHeaders = {
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    };
    final response = await http.post(
      Uri.parse(url),
      body: payload,
      headers: requestHeaders,
    );
    return response.body;
  }$multipartMethod
}
""",
    );
  }

  GLClassModel generateDioAdapterFile() {
    final extraParam = _parser.operationNameAsParameter ? ', String operationName' : '';
    final multipartMethod = _parser.hasUploadMutations ? '''

  Future<String> multipartCall(Map<String, Object> parts, UploadProgressCallback? onProgress) async {
    final converted = <String, dynamic>{};
    for (final entry in parts.entries) {
      if (entry.value is GLUpload) {
        final u = entry.value as GLUpload;
        converted[entry.key] = MultipartFile.fromStream(
          () => u.stream, u.length ?? 0,
          filename: u.filename,
          contentType: u.mimeType.isNotEmpty ? MediaType.parse(u.mimeType) : null,
        );
      } else {
        converted[entry.key] = entry.value;
      }
    }
    final formData = FormData.fromMap(converted);
    final response = await dio.post<dynamic>(url, data: formData,
        onSendProgress: onProgress != null ? (sent, total) => onProgress(sent, total) : null);
    final data = response.data;
    return data is String ? data : jsonEncode(data);
  }''' : '';
    return GLClassModel(
      imports: [
        "import 'dart:async';",
        "import 'dart:convert';",
        "import 'package:dio/dio.dart';",
        "import 'package:http_parser/http_parser.dart';",
        if (_parser.hasUploadMutations) "import 'graph_link_uploads.dart';",
      ],
      body: """
class GraphLinkDioAdapter {
  final String url;
  final Dio dio;

  GraphLinkDioAdapter({
    required this.url,
    Dio? dio,
    Future<Map<String, String>?> Function()? headersProvider,
    List<Interceptor> interceptors = const [],
    BaseOptions? options,
  }) : dio = dio ?? Dio(options ?? BaseOptions(contentType: 'application/json')) {
    if (dio == null) {
      if (headersProvider != null) {
        this.dio.interceptors.add(_HeadersInterceptor(headersProvider));
      }
      this.dio.interceptors.addAll(interceptors);
    }
  }

  Future<String> call(String payload$extraParam) async {
    final response = await dio.post<dynamic>(url, data: payload);
    final data = response.data;
    return data is String ? data : jsonEncode(data);
  }$multipartMethod
}

class _HeadersInterceptor extends Interceptor {
  final Future<Map<String, String>?> Function() _headersProvider;

  _HeadersInterceptor(this._headersProvider);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final headers = await _headersProvider();
    if (headers != null) {
      options.headers.addAll(headers);
    }
    handler.next(options);
  }
}
""",
    );
  }

  GLClassModel generateUploadsFile() => const GLClassModel(body: dartUploadsFile);

  GLClassModel generateDefaultWebSocketAdapterFile() =>
     const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:math';",
          "import 'package:web_socket_channel/web_socket_channel.dart';",
          "import 'graph_link_client.dart';",
        ],
        body: _defaultWebSocketAdapter,
      );

}

const _subscriptionHandler = """

class GraphqlWsMessageTypes {
  /// Client initializes connection.
  /// Example: { "type": "connection_init", "payload": { "authToken": "abc123" } }
  static const String connectionInit = 'connection_init';

  /// Server acknowledges connection.
  /// Example: { "type": "connection_ack" }
  static const String connectionAck = 'connection_ack';

  /// Client subscribes to an operation.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "subscribe",
  ///   "payload": { "query": "...", "variables": {} }
  /// }
  static const String subscribe = 'subscribe';

  /// Client or server pings for keep-alive.
  /// Example: { "type": "ping", "payload": {} }
  static const String ping = 'ping';

  /// Response to ping.
  /// Example: { "type": "pong" }
  static const String pong = 'pong';

  /// Server sends subscription data.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "next",
  ///   "payload": { "data": { "newMessage": { "id": "42", "content": "Hi" } } }
  /// }
  static const String next = 'next';

  /// Server sends a fatal error for a subscription.
  /// Example: { "id": "1", "type": "error", "payload": { "message": "Validation failed" } }
  static const String error = 'error';

  /// Client or server completes subscription.
  /// Example: { "id": "1", "type": "complete" }
  static const String complete = 'complete';
}


class _SubscriptionHandler {
  static const hexDigits = '0123456789abcdef';
  final _random = Random();
  final Map<String, StreamController<Map<String, dynamic>>> _map = {};
  final Map<String, StreamSubscription> _subs = {};
  final Map<String, GraphLinkPayload> _payloads = {};
  final GraphLinkWebSocketAdapter adapter;

  final pongMessage = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.pong).toJson());

  _SubscriptionHandler(this.adapter) {
    adapter.onReconnect.listen((_) => _onReconnect());
  }

  Completer<_StreamSink>? _sinkCompleter;

  late final _onMessageStream = adapter.onMessageStream;

  Future<_StreamSink> _initWs() {
    if (_sinkCompleter != null) return _sinkCompleter!.future;
    _sinkCompleter = Completer();
    _connect();
    return _sinkCompleter!.future;
  }

  Future<void> _connect() async {
    final completer = _sinkCompleter;
    try {
      await adapter.connect();
      completer?.complete(await _doHandshake());
    } catch (e) {
      completer?.completeError(e);
      _sinkCompleter = null;
    }
  }

  Future<_StreamSink> _doHandshake() async {
    final payload = await adapter.connectionInitPayload();
    final initMsg = jsonEncode({
      'type': GraphqlWsMessageTypes.connectionInit,
      if (payload != null) 'payload': payload,
    });
    await adapter.sendMessage(initMsg);
    await _onMessageStream
        .map(_parseEvent)
        .firstWhere(
          (msg) => msg.type == GraphqlWsMessageTypes.connectionAck,
          orElse: () => throw StateError('WebSocket closed before receiving connection_ack'),
        )
        .catchError((_) => GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.connectionAck));
    return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
  }

  Future<void> _onReconnect() async {
    if (_payloads.isEmpty) return;
    _sinkCompleter = Completer();
    final completer = _sinkCompleter;
    try {
      final sink = await _doHandshake();
      completer?.complete(sink);
    } catch (e) {
      completer?.completeError(e);
      _sinkCompleter = null;
      for (final uuid in _map.keys) {
        if (!_map[uuid]!.isClosed) _map[uuid]!.addError(e);
      }
    }
  }

  StreamController<Map<String, dynamic>> _createStremController(String uuid) {
    var controller = StreamController<Map<String, dynamic>>(
      onCancel: () {
        _removeController(uuid);
      },
    );
    _map[uuid] = controller;
    return controller;
  }

  Stream<Map<String, dynamic>> handle(GraphLinkPayload pl) {
    String uuid = _generateUuid();
    var controller = _createStremController(uuid);
    _payloads[uuid] = pl;

    _initWs().then((streamSink) async {
      var sub = streamSink.stream
          .map(_parseEvent)
          .where((event) => event.id == uuid)
          .listen((msg) => _handleMessage(msg, uuid));
      _subs[uuid] = sub;
      var message = GraphLinkSubscriptionMessage(
          id: uuid,
          type: GraphqlWsMessageTypes.subscribe,
          payload: GraphLinkSubscriptionPayload(
            query: pl.query,
            operationName: pl.operationName,
            variables: pl.variables,
          ));
      await streamSink.sendMessage(json.encode(message.toJson()));
    }).catchError((e) {
      if (!controller.isClosed) controller.addError(e);
      _removeController(uuid);
    });

    return controller.stream;
  }

  GraphLinkSubscriptionErrorMessageBase _parseEvent(String event) {
    var map = jsonDecode(event);
    var payload = map["payload"];
    if (payload is Map) {
      return GraphLinkSubscriptionMessage.fromJson(map);
    }
    return GraphLinkSubscriptionErrorMessage.fromJson(map);
  }

  void _handleMessage(GraphLinkSubscriptionErrorMessageBase msg, String uuid) {
    var controller = _map[uuid];
    if (controller == null) return;
    switch (msg.type!) {
      case GraphqlWsMessageTypes.ping:
        adapter.sendMessage(pongMessage);
        break;
      case GraphqlWsMessageTypes.next:
        if (!controller.isClosed) controller.add((msg as GraphLinkSubscriptionMessage).payload!.data!);
        break;
      case GraphqlWsMessageTypes.complete:
        _removeController(uuid);
        break;
      case GraphqlWsMessageTypes.error:
        var errorMsg = msg as GraphLinkSubscriptionErrorMessage;
        if (!controller.isClosed) controller.addError(errorMsg.payload as Object);
        _removeController(uuid);
        break;
      default:
    }
  }

  void _removeController(String uuid) {
    _subs.remove(uuid)?.cancel();
    _map.remove(uuid)?.close();
    _payloads.remove(uuid);
    if (_map.isEmpty) {
      _sinkCompleter = null;
    }
  }

  String _generateRandomString(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      final randomIndex = _random.nextInt(hexDigits.length);
      buffer.write(hexDigits[randomIndex]);
    }
    return buffer.toString();
  }

  String _generateUuid([String separator = "-"]) {
    return [
      _generateRandomString(8),
      _generateRandomString(4),
      _generateRandomString(4),
      _generateRandomString(4),
      _generateRandomString(12),
    ].join(separator);
  }
}

""";

const _streamSink = """
class _StreamSink {
  final Future<void> Function(String) sendMessage;
  final Stream<String> stream;

  _StreamSink({required this.sendMessage, required this.stream});
}
""";

const _webSocketAdapter = """
abstract class GraphLinkWebSocketAdapter {
  Future<void> connect();

  /// Must return a broadcast stream.
  Stream<String> get onMessageStream;

  Future<void> sendMessage(String message);

  Future<void> close();

  // Override to pass auth token or any connection metadata
  Future<Map<String, dynamic>?> connectionInitPayload() async => null;

  // Fires after a successful reconnect; used by the handler to re-subscribe
  Stream<void> get onReconnect => const Stream.empty();
}
""";

const _defaultWebSocketAdapter = """
class DefaultGraphLinkWebSocketAdapter extends GraphLinkWebSocketAdapter {
  final String url;
  final Future<Map<String, String>?> Function()? headersProvider;
  final bool reconnect;

  WebSocketChannel? _channel;
  final _messageController = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _connectionCompleter;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static final Random _random = Random();

  DefaultGraphLinkWebSocketAdapter({
    required this.url,
    this.headersProvider,
    this.reconnect = false,
  });

  @override
  Future<void> connect() async {
    await _connectOnce();
  }

  Future<void> _connectOnce() {
    if (_channel != null) return _channel!.ready;
    if (_connectionCompleter != null) return _connectionCompleter!.future;
    _connectionCompleter = Completer<void>();
    _createConnection();
    return _connectionCompleter!.future;
  }

  Future<void> _createConnection() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) => _messageController.add(data as String),
        onError: _onError,
        onDone: _onDone,
      );
      await _channel!.ready;
      _connectionCompleter?.complete();
    } catch (e) {
      _connectionCompleter?.completeError(e);
    } finally {
      _connectionCompleter = null;
    }
  }

  void _onError(Object error) {
    if (_subscription == null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect) _reconnect();
  }

  void _onDone() {
    if (_subscription == null) return;
    final closeCode = _channel?.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && closeCode != 1000) _reconnect();
  }

  Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    final delay = _backoffDelay(_reconnectAttempts);
    _reconnectAttempts++;
    await Future.delayed(delay);
    await _connectOnce();
    _reconnectAttempts = 0;
    _reconnectController.add(null);
  }

  Duration _backoffDelay(int attempt) {
    final exp = min(_initialDelay.inMilliseconds * pow(2, attempt), _maxDelay.inMilliseconds);
    final jitter = _random.nextInt(1000);
    return Duration(milliseconds: exp.toInt() + jitter);
  }

  @override
  Stream<String> get onMessageStream => _messageController.stream;

  @override
  Stream<void> get onReconnect => _reconnectController.stream;

  @override
  Future<Map<String, dynamic>?> connectionInitPayload() async {
    final headers = await headersProvider?.call();
    if (headers == null || headers.isEmpty) return null;
    return headers;
  }

  @override
  Future<void> sendMessage(String message) async => _channel!.sink.add(message);

  @override
  Future<void> close() async {
    _reconnectAttempts = 0;
    _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'normal closure');
    _channel = null;
  }
}
""";
