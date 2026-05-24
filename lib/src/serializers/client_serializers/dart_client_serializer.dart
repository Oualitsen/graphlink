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
import 'package:graphlink/src/capture_errors_utils.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/client_serializers/dart_client_constants.dart';
import 'package:graphlink/src/serializers/gl_client_serializer.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
const _operationNameParam = "operationName";
const _cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';

class DartClientSerializer extends GLClientSerializer {
  final GLParser _parser;
  final bool generateAdapters;
  final DartHttpAdapter httpAdapter;
  final codeGenUtils = DartCodeGenUtils();

  DartClientSerializer(this._parser, GLSerializer dartSerializer,
      {this.generateAdapters = true, this.httpAdapter = DartHttpAdapter.http})
      : super(dartSerializer, _parser.serializer);

  bool get _useDio => httpAdapter == DartHttpAdapter.dio;

  @override
  String renderQueryMethod(GLQueryDefinition def) => queryToMethod(def);

  @override
  String renderMutationMethod(GLQueryDefinition def) => mutationToMethod(def);

  @override
  String renderUploadMutationMethod(GLQueryDefinition def) => mutationToMethod(def);

  @override
  String renderSubscriptionMethod(GLQueryDefinition def) => mutationToMethod(def);

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
  GLClassModel generateClient() {
    final dartImports = [
      "import 'dart:convert';",
      "import 'dart:async';",
      if (_parser.hasSubscriptions) "import 'dart:math';",
      if (generateAdapters && httpAdapter != DartHttpAdapter.none)
        _useDio
            ? "import 'graph_link_dio_adapter.dart';"
            : "import 'graph_link_http_adapter.dart';",
      if (generateAdapters && _parser.hasSubscriptions)
        "import 'graph_link_websocket_adapter.dart';",
      ...serializeImports(_parser)
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
      declareHttpAdapter(),
      codeGenUtils.createMethod(
          methodName: '_ResolverBase',
          namedArguments: false,
          arguments: ['GraphLinkCacheStore store', 'Map<String, _Lock> locks', 'this.$_svAdapter'],
          statements: [
            '$_svStore = store;',
            '$_svTagLocks = locks;',
          ]),
      codeGenUtils.createMethod(returnType: 'Future<String>', methodName: "glCallAdapter", async: true, namedArguments: false, arguments: [
        'GraphLinkPayload payload',
      ], statements: [
        if(_parser.operationNameAsParameter)
          'return await $_svAdapter(json.encode(payload.toJson()), payload.operationName);'
        else
          'return await $_svAdapter(json.encode(payload.toJson()));'
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
              "$_svFragMap['${value.tokenInfo}'] = '${gqlSerializer.serializeFragmentDefinitionBase(value)}';"),
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
            "subscriptions = ${classNameFromType(GLQueryType.subscription)}(adapter, wsAdapter, $_svFragMap, this.store, $_svTagLocks);",
        ],
      ),
      if (_parser.hasSubscriptions && generateAdapters && httpAdapter != DartHttpAdapter.none)
        _fromUrlConstructor(),
      if (generateAdapters && httpAdapter != DartHttpAdapter.none)
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
  GLClassModel? getQueriesClass() {
    final body = generateQueriesClassByType(GLQueryType.query);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getMutationsClass() {
    final body = generateQueriesClassByType(GLQueryType.mutation);
    return body != null ? GLClassModel(body: body) : null;
  }

  @override
  GLClassModel? getSubscriptionsClass() {
    final body = generateQueriesClassByType(GLQueryType.subscription);
    return body != null ? GLClassModel(body: body) : null;
  }

  String? generateQueriesClassByType(GLQueryType type) {
    final methods = buildOperationMethods(type);
    if (methods.isEmpty) return null;

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
                _svTagLocks,
                'httpAdapter',
              ],
              statements: [
                '$_svFragMap = fragmentMap;',
                if (type == GLQueryType.subscription)
                  '$_svHandler = _SubscriptionHandler(adapter);',
              ]),
          ...methods,
          if (type == GLQueryType.query) ...[
            codeGenUtils.createMethod(
                methodName: "_getFromSource",
                async: true,
                namedArguments: false,
                arguments: ['GraphLinkPayload payload'],
                returnType: 'Future<String>',
                statements: [
                  'return await glCallAdapter(payload);'
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
                        'queryBuilder.write(" ");',
                      ]),
                  'queryBuilder.write("}");',
                  'final fragments = partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => $_svFragMap[fragName]!).join();',
                  'queryBuilder.write(fragments);',
                  'return GraphLinkPayload(query: queryBuilder.toString(), operationName: operationName, variables: variables);',
                ]),
            codeGenUtils.createMethod(
                methodName: '_parseToObjectAndCache<T extends GraphLinkFullResponse>',
                arguments: [
                  'String data',
                  'Map<String, dynamic> cachedResponse',
                  'T Function(Map<String, dynamic> json) parser',
                  'Set<_GraphLinkPartialQuery> remainingQueries',
                  'bool captureErrors',
                ],
                returnType: 'T',
                namedArguments: false,
                statements: [
                  'final result = jsonDecode(data) as Map<String, dynamic>;',
                  'final rawData = result["data"];',
                  'final dataMap = rawData as Map<String, dynamic>? ?? <String, dynamic>{};',
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
                  "final fullResponse = <String, dynamic>{'data': rawData != null ? dataMap : null};",
                  codeGenUtils.ifStatement(
                      condition: 'result["errors"] != null',
                      ifBlockStatements: [
                        'fullResponse["errors"] = result["errors"];',
                      ]),
                  'final parsed = parser.call(fullResponse);',
                  codeGenUtils.ifStatement(
                      condition: 'captureErrors',
                      ifBlockStatements: ['return parsed;']),
                  'final errors = result["errors"] as List?;',
                  codeGenUtils.ifStatement(
                      condition: 'errors != null && errors.isNotEmpty',
                      ifBlockStatements: [
                        'throw parsed.errors!;',
                      ]),
                  'return parsed;',
                ]),
          ],
        ]);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      '${delcareHttpAdapterFunction()} httpAdapter',
      if (type == GLQueryType.subscription)
        'GraphLinkWebSocketAdapter adapter',
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
        return '';
      case GLQueryType.mutation:
        if (_parser.hasUploadMutations) {
          return "final GLUploadConverter $_svUploadConverter;\nfinal GLMultipartAdapter? $_svUploadAdapter;";
        }
        return '';
      case GLQueryType.subscription:
        return "late final _SubscriptionHandler $_svHandler;";
    }
  }

  String declareHttpAdapter() {
    return "final ${delcareHttpAdapterFunction()} $_svAdapter;";
  }

  String delcareHttpAdapterFunction() {
    return 'Future<String> Function(String payload${_parser.operationNameAsParameter ? ', String $_operationNameParam' : ''})';
  }

  String mutationToMethod(GLQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        async: def.type != GLQueryType.subscription,
        statements: [
          if (!isUploadMutation(def))
            "const $_svOperationName = '${def.tokenInfo}';",
          if (hasFragments(def)) ...[
            "final $_svFragsValues = [",
            ...getFragmentsForDef(def).map((e) => '"${e.tokenInfo}",'),
            '].map((fragName) => $_svFragMap[fragName]!).join(' ');'
          ],
          if (!hasFragments(def))
            "const $_svQuery = '''${serializeQueryString(def)}''';"
          else
            "final $_svQuery = '''${serializeQueryString(def)} \${$_svFragsValues}''';",
          generateVariables(def),
          if (!isUploadMutation(def))
            "final $_svPayload = GraphLinkPayload(query: $_svQuery, operationName: $_svOperationName, variables: $_svVariables);",
          _serializeAdapterCall(def)
        ]);
  }

  String queryToMethod(GLQueryDefinition def) {
    final cacheHitReturn = StringBuffer();
    final parseAndCacheCall = StringBuffer();
    final fullResponseToken = def.getFullResponseTypeDefinition(_parser).tokenInfo;
    final isCaptureErrors = def.isCaptureErrors(_parser);

    cacheHitReturn.write("return $fullResponseToken.fromJson({'data': $_svResponseMap})");
    parseAndCacheCall.write("return _parseToObjectAndCache($_svResponseText, $_svResponseMap, $fullResponseToken.fromJson, $_svRemaining, ${def.isCaptureErrors(_parser) ? 'true': 'false'})");
    if(!isCaptureErrors) {
      cacheHitReturn.write(".data!");
      parseAndCacheCall.write(".data!");
    }
    cacheHitReturn.write(";");
    parseAndCacheCall.write(";");


    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        async: true,
        statements: [
          "const $_svOperationName = '${def.tokenInfo}';",
          generateVariables(def),

          // divided query for cache handling

          'final $_svPartialQueries = ${divideQuery(def).map((e) => serialzePartialQuery(e)).toList()};',
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
              ifBlockStatements: [cacheHitReturn.toString()]),
          "final $_svRemainingQueries = $_svPartialQueries.where((e) => !$_svResponseMap.containsKey(e.elementKey)).toList();",
          "final $_svPayload = _buildPayload($_svRemainingQueries, $_svOperationName, '${gqlSerializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}');",
          codeGenUtils.tryCatchFinally(tryStatements: [
            'final $_svResponseText = await _getFromSource($_svPayload);',
            parseAndCacheCall.toString(),
          ], catchStatements: [
            "$_svResponseMap.addAll($_svStaleData);",
            'final remainingCount = $_svPartialQueries.where((e) => !$_svResponseMap.containsKey(e.elementKey)).length;',
            codeGenUtils.ifStatement(
                condition: 'remainingCount > 0',
                ifBlockStatements: [
                  "rethrow;",
                ]),
            cacheHitReturn.toString(),
          ], catchVariable: 'exception'),
        ]);
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    if (shouldInvalidateAll(def)) {
      return 'await $_svStore.invalidateAll();';
    }
    final tags = getInvalidationTags(def);
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
    if (isUploadMutation(def)) {
      return _serializeMultipartAdapterCall(def);
    }
    final fullResponseToken = def.getFullResponseTypeDefinition(_parser).tokenInfo;
    if (def.isCaptureErrors(_parser)) {
      return """
final $_svResponse = await glCallAdapter($_svPayload);
final $_svResult = $fullResponseToken.fromJson(jsonDecode($_svResponse));
if ($_svResult.errors == null) {
  ${_serializeInvalidationCall(def)}
}
return $_svResult;
""";
    }
    const dataSuffix =  '!';
    return """
final $_svResponse = await glCallAdapter($_svPayload);
final $_svResult = $fullResponseToken.fromJson(jsonDecode($_svResponse));
if ($_svResult.errors != null) {
  throw $_svResult.errors!;
}
${_serializeInvalidationCall(def)}
return $_svResult.data$dataSuffix;
""";
  }

  String _serializeMultipartAdapterCall(GLQueryDefinition def) {
    final uploadArgs = getUploadArgs(def);

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
    if (isUploadMutation(def)) {
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
    if (def.type == GLQueryType.subscription) {
      return "Stream<${def.getGeneratedTypeDefinition().tokenInfo.token}>";
    }
    if (def.isCaptureErrors(_parser)) {
      return "Future<${def.getFullResponseTypeDefinition(_parser).tokenInfo.token}>";
    }
    final typeName = def.getGeneratedTypeDefinition().tokenInfo.token;
    return "Future<$typeName>";
  }

  String serializeSubscriptions() {
    if (!_parser.hasSubscriptions) {
      return "";
    }
    return """
$dartSubscriptionHandler
$dartGraphqlMessageTypes
$streamSink
$webSocketAdapter
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
      Uri.parse(${_parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url'}),
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
        converted[entry.key] = MultipartFile(
          u.stream, u.length ?? 0,
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
        if (_parser.hasUploadMutations) "import 'package:http_parser/http_parser.dart';",
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
    final response = await dio.post<dynamic>(${_parser.operationNameAsParameter ? "'\$url?operationName=\$operationName'" : 'url'}, data: payload);
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

  @override
  GLClassModel generateUploadsFile() => const GLClassModel(body: dartUploadsFile);

  GLClassModel generateDefaultWebSocketAdapterFile() =>
     const GLClassModel(
        imports: [
          "import 'dart:async';",
          "import 'dart:math';",
          "import 'package:web_socket_channel/web_socket_channel.dart';",
          "import 'graph_link_client.dart';",
        ],
        body: defaultWebSocketAdapter,
      );

}


