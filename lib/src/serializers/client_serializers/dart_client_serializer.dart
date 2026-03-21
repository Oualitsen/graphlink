import 'package:graphlink/src/cache_store_dart.dart';
import 'package:graphlink/src/code_gen_utils.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/gl_grammar.dart';
import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/gl_client_serilaizer.dart';
import 'package:graphlink/src/serializers/gl_serializer.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';

const _operationNameParam = "operationName";
const _cacheStoreClassName = 'GraphLinkCacheStore';
const _inMemorycacheStoreClassName = 'InMemoryGraphLinkCacheStore';

class DartClientSerializer extends GLClientSerilaizer {
  final GLGrammar _grammar;
  final codeGenUtils = DartCodeGenUtils();

  DartClientSerializer(this._grammar, GLSerializer dartSerializer) : super(dartSerializer);

  @override
  String generateClient(String importPrefix) {
    var imports = serializeImports(_grammar, importPrefix);

    var buffer = StringBuffer();
    buffer.writeln("import 'dart:convert';");
    buffer.writeln("import 'dart:async';");
    buffer.writeln("import 'dart:math';");
    buffer.writeln(imports);

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

    GLQueryType.values.map((e) => generateQueriesClassByType(e)).where((e) => e != null).map((e) => e!).forEach((line) {
      buffer.writeln(line);
    });

    buffer.writeln(codeGenUtils.createClass(className: "_ResolverBase", statements: [
      'final Map<String, String> fragmentMap;',
      'final GraphLinkCacheStore store;',
      'final Map<String, _Lock> _tagLocks;',
      codeGenUtils.createMethod(
          methodName: '_ResolverBase',
          namedArguments: false,
          arguments: ['this.fragmentMap', 'this.store', 'this._tagLocks']),
      codeGenUtils.createMethod(
          methodName: "_getFromCache",
          async: true,
          namedArguments: false,
          arguments: ['String key', 'List<String> tags'],
          returnType: 'Future<String?>',
          statements: [
            'var result = await store.get(key);',
            codeGenUtils.ifStatement(condition: 'result != null', ifBlockStatements: [
              'var entryMap = jsonDecode(result);',
              'var entry = _GraphLinkCacheEntry.fromJson(entryMap);',
              codeGenUtils.ifStatement(condition: 'entry.isExpired', ifBlockStatements: [
                'store.invalidate(key);',
                codeGenUtils.ifStatement(condition: 'tags.isEmpty', ifBlockStatements: [
                  '_removeKeyFromTags(key, tags);',
                ]),
                'return null;',
              ], elseBlockStatements: [
                "return entry.data;"
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
            codeGenUtils.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = _tagLocks[tag]!;',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await store.get(tagKey);',
                codeGenUtils.ifStatement(condition: "data != null", ifBlockStatements: [
                  'final entry = _GraphLinkTagEntry.decode(data);',
                  codeGenUtils.forEachLoop(variable: 'key', iterable: 'entry.keys', statements: [
                    'await store.invalidate(key);',
                  ]),
                  'await store.invalidate(tagKey);'
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
            codeGenUtils.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = _tagLocks[tag]!;',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await store.get(tagKey);',
                'final entry = data != null ? _GraphLinkTagEntry.decode(data) : _GraphLinkTagEntry({});',
                'entry.add(key);',
                'await store.set(tagKey, entry.encode());'
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
            codeGenUtils.forEachLoop(variable: 'tag', iterable: 'tags', statements: [
              'final tagKey = "\${tagKeyPrefix}\${tag}";',
              'final lock = _tagLocks.putIfAbsent(tag, () => _Lock());',
              'await lock.synchronized(() async',
              codeGenUtils.block([
                'final data = await store.get(tagKey);',
                codeGenUtils.ifStatement(condition: "data != null", ifBlockStatements: [
                  'final entry = _GraphLinkTagEntry.decode(data);',
                  'entry.remove(key);',
                  codeGenUtils.ifStatement(
                      condition: 'entry.keys.isEmpty',
                      ifBlockStatements: ['await store.invalidate(tagKey);'],
                      elseBlockStatements: ['await store.set(tagKey, entry.encode());'])
                ])
              ]),
              ');'
            ])
          ])
    ]));

    buffer.writeln(codeGenUtils.createClass(className: 'GraphLinkClient', statements: [
      'final _fragmMap = <String, String>{};',
      'final _tagLocks = <String, _Lock>{};',
      if (_grammar.hasQueries) 'late final ${classNameFromType(GLQueryType.query)} queries;',
      if (_grammar.hasMutations) 'late final ${classNameFromType(GLQueryType.mutation)} mutations;',
      if (_grammar.hasSubscriptions) 'late final ${classNameFromType(GLQueryType.subscription)} subscriptions;',
      'late final $_cacheStoreClassName store;',
      codeGenUtils.createMethod(
        methodName: 'GraphLinkClient',
        arguments: [
          _adapterDeclaration(),
          if (_grammar.hasSubscriptions) 'GraphLinkWebSocketAdapter wsAdapter',
          '$_cacheStoreClassName? store'
        ],
        namedArguments: false,
        statements: [
          ..._grammar.fragments.values.map((value) =>
              "_fragmMap['${value.tokenInfo}'] = '${_grammar.serializer.serializeFragmentDefinitionBase(value)}';"),
          'this.store = store ?? $_inMemorycacheStoreClassName();',
          'final tags = ${_grammar.getAllCacheTags().map((e) => e.quote()).toList()};',
          codeGenUtils.forEachLoop(variable: 'tag', iterable: 'tags', statements: ['_tagLocks[tag] = _Lock();']),
          if (_grammar.hasQueries)
            "queries = ${classNameFromType(GLQueryType.query)}(adapter, _fragmMap, this.store, _tagLocks);",
          if (_grammar.hasMutations)
            "mutations = ${classNameFromType(GLQueryType.mutation)}(adapter, _fragmMap, this.store, _tagLocks);",
          if (_grammar.hasSubscriptions)
            "subscriptions = ${classNameFromType(GLQueryType.subscription)}(wsAdapter, _fragmMap, this.store, _tagLocks);",
        ],
      ),
    ]));

    buffer.writeln(serializeSubscriptions().ident());
    return buffer.toString();
  }

  String _adapterDeclaration() {
    if (_grammar.operationNameAsParameter) {
      return 'Future<String> Function(String payload, String $_operationNameParam) adapter';
    }
    return 'Future<String> Function(String payload) adapter';
  }

  String? generateQueriesClassByType(GLQueryType type) {
    var queries = _grammar.queries.values;
    var queryList = queries.where((element) => element.type == type && _grammar.hasQueryType(type)).toList();
    if (queryList.isEmpty) {
      return null;
    }

    return codeGenUtils.createClass(className: "${classNameFromType(type)} extends _ResolverBase", statements: [
      declareAdapter(type),
      codeGenUtils.createConstructor(
          className: classNameFromType(type),
          arguments: _declareConstructorArgs(type),
          superArguments: [
            'fragmentMap',
            'store',
            '_tagLocks'
          ],
          statements: [
            if (type == GLQueryType.subscription) '_handler = _SubscriptionHandler(adapter);',
          ]),
      ...queryList.map((e) => type == GLQueryType.query ? queryToMethod(e) : mutationToMethod(e)),
      if (type == GLQueryType.query) ...[
        codeGenUtils.createMethod(
            methodName: "_getFromSource",
            async: true,
            namedArguments: false,
            arguments: ['GraphLinkPayload payload'],
            returnType: 'Future<String>',
            statements: ['var result = await _adapter(json.encode(payload.toJson()));', 'return result;']),
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
              codeGenUtils.ifStatement(condition: 'args.isNotEmpty', ifBlockStatements: [
                'queryBuilder.write("(");',
                'queryBuilder.writeAll(args, ", ");',
                'queryBuilder.write(")");'
              ]),
              codeGenUtils.ifStatement(
                  condition: 'directives.isNotEmpty', ifBlockStatements: ['queryBuilder.write(directives);']),
              'queryBuilder.write("{");',
              codeGenUtils.forEachLoop(variable: 'partQuery', iterable: 'partQueries', statements: [
                'queryBuilder.write(partQuery.query);',
              ]),
              'queryBuilder.write("}");',
              'final fragments = partQueries.expand((e) => e.fragmentNames).toSet().map((fragName) => fragmentMap[fragName]!).join();',
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
              codeGenUtils.ifStatement(condition: 'result.containsKey("errors")', ifBlockStatements: [
                'throw result["errors"].map((error) => GraphLinkError.fromJson(error)).toList();'
              ]),
              'final dataMap = result["data"] as Map<String, dynamic>;',
              codeGenUtils.forEachLoop(variable: 'q', iterable: 'remainingQueries', statements: [
                codeGenUtils.ifStatement(condition: 'q.ttl > 0 && dataMap[q.elementKey] != null', ifBlockStatements: [
                  'final entry = _GraphLinkCacheEntry(jsonEncode(dataMap[q.elementKey]), DateTime.now().millisecondsSinceEpoch + q.ttl * 1000);',
                  'store.set(q.cacheKey!, jsonEncode(entry.toJson()));',
                  codeGenUtils.ifStatement(condition: 'q.tags.isNotEmpty', ifBlockStatements: [
                    '_addKeyToTags(q.cacheKey!, q.tags);',
                  ]),
                ])
              ]),
              'return parser.call(dataMap);'
            ]),
      ],
    ]);
  }

  List<String> _declareConstructorArgs(GLQueryType type) {
    return [
      if (type == GLQueryType.subscription) 'GraphLinkWebSocketAdapter adapter' else 'this._adapter',
      'Map<String, String> fragmentMap',
      'GraphLinkCacheStore store',
      'Map<String, _Lock> _tagLocks'
    ];
  }

  String declareAdapter(GLQueryType type) {
    switch (type) {
      case GLQueryType.query:
      case GLQueryType.mutation:
        return "final Future<String> Function(String payload${_grammar.operationNameAsParameter ? ', String $_operationNameParam' : ''}) _adapter;";
      case GLQueryType.subscription:
        return "late final _SubscriptionHandler _handler;";
    }
  }

  String mutationToMethod(GLQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
        async: def.type != GLQueryType.subscription,
        statements: [
          "const operationName = '${def.tokenInfo}';",
          if (def.fragments(_grammar).isNotEmpty) ...[
            "final fragsValues = [",
            ...def.fragments(_grammar).map((e) => '"${e.tokenInfo}",'),
            '].map((fragName) => fragmentMap[fragName]!).join(' ');'
          ],
          if (def.fragments(_grammar).isEmpty)
            "const query = '''${_grammar.serializer.serializeQueryDefinition(def)}''';"
          else
            "final query = '''${_grammar.serializer.serializeQueryDefinition(def)} \${fragsValues}''';",
          generateVariables(def),
          "final payload = GraphLinkPayload(query: query, operationName: operationName, variables: variables);",
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
          "const operationName = '${def.tokenInfo}';",
          generateVariables(def),

          // divided query for cache handling

          'final partialQueries = ${_grammar.serializer.divideQueryDefinition(def, _grammar).map((e) => serialzePartialQuery(e)).toList()};',
          'final responseMap = <String, dynamic>{};',
          'final cacheFetchFutures = <Future>[];',
          codeGenUtils
              .forEachLoop(variable: "partQuery", iterable: "partialQueries.where((e) => e.ttl > 0)", statements: [
            "cacheFetchFutures.add(_getFromCache(partQuery.cacheKey!, partQuery.tags)",
            ".asStream().where((e) => e != null).map((e) => e!).first.then((data) ${codeGenUtils.block([
                  'responseMap[partQuery.elementKey] = jsonDecode(data);'
                ])}));"
          ]),
          'await Future.wait(cacheFetchFutures.map((f) => f.catchError((_) => null)));',
          'var remaining = partialQueries.where((e) => !responseMap.containsKey(e.elementKey)).toSet();',
          codeGenUtils.ifStatement(
              condition: 'remaining.isEmpty',
              ifBlockStatements: ['return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson(responseMap);']),
          "final remainingQueries = partialQueries.where((e) => !responseMap.containsKey(e.elementKey)).toList();",
          "final payload = _buildPayload(remainingQueries, operationName, '${_grammar.serializer.serializeDirectiveValueList(def.getDirectives(skipGenerated: true))}');",
          'final responseText = await _getFromSource(payload);',
          'return _parseToObjectAndCache(responseText, responseMap, ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson, remaining);',
        ]);
  }

  String _serializeInvalidationCall(GLQueryDefinition def) {
    for (var e in def.elements) {
      if (e.cacheInvalidateAll) {
        return 'await store.invalidateAll();';
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
      varBuffer.writeln("'${dartArgName}': variables['${dartArgName}'],");
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
)
''';
  }

  String generateVariables(GLQueryDefinition def) {
    var buffer = StringBuffer("final variables = <String, dynamic>{");
    buffer.writeln();
    def.arguments.map((e) => "'${e.dartArgumentName}': ${_serializeArgumentValue(def, e.token)},").forEach((line) {
      buffer.writeln(line.ident());
    });
    buffer.writeln("};");
    return buffer.toString();
  }

  String _serializeAdapterCall(GLQueryDefinition def) {
    if (def.type == GLQueryType.subscription) {
      return """
return _handler.handle(payload)
.map((e) {
  return ${def.getGeneratedTypeDefinition().tokenInfo.token}.fromJson(e);
});
    """
          .trim()
          .ident();
    }
    return """
final response = await _adapter(json.encode(payload.toJson())${_grammar.operationNameAsParameter ? ', operationName' : ''});
Map<String, dynamic> result = jsonDecode(response);
if (result.containsKey("errors")) {
  throw result["errors"].map((error) => GraphLinkError.fromJson(error)).toList();
}
var data = result["data"];
${_serializeInvalidationCall(def)}
return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson(data);
""";
  }

  String _serializeArgumentValue(GLQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GLType type) {
    if (_grammar.inputTypeRequiresProjection(type)) {
      if (type.isList) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.inlineType)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    }
    if (_grammar.isEnum(type.token)) {
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
    if (def.arguments.isEmpty) {
      return [];
    }
    return def.arguments
        .map((e) => "${serializer.serializeType(e.type, false)} ${e.dartArgumentName}")
        .map((e) => "required $e")
        .toList();
  }

  String returnTypeByQueryType(GLQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GLQueryType.subscription) {
      return "Stream<${gen.tokenInfo.token}>";
    }
    return "Future<${gen.tokenInfo.token}>";
  }

  String serializeSubscriptions() {
    if (!_grammar.hasSubscriptions) {
      return "";
    }
    return """
$_subscriptionHandler
$_streamSink
$_webSocketAdapter
""";
  }

  String get fileExtension => '.dart';
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
  final GraphLinkWebSocketAdapter adapter;

  final connectionInit = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.connectionInit).toJson());
  final pingMessage = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.ping).toJson());
  final pongMessage = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.pong).toJson());

  _SubscriptionHandler(this.adapter);

  var _ackStatus = GQAckStatus.none;

  Stream<String> get _onMessageStream {
    var stream = adapter.onMessageStream;
    if (stream.isBroadcast) {
      return stream;
    }
    return stream.asBroadcastStream();
  }

  Future<_StreamSink> _initWs() async {
    switch (_ackStatus) {
      case GQAckStatus.none:
        {
          _ackStatus = GQAckStatus.progress;
          await adapter.onConnectionReady();
          adapter.sendMessage(connectionInit);
          return _onMessageStream.map((event) {
            var decoded = jsonDecode(event);
            if (decoded is Map<String, dynamic>) {
              return GraphLinkSubscriptionMessage.fromJson(decoded);
            } else {
              return GraphLinkSubscriptionErrorMessage(payload: decoded);
            }
          }).map((event) {
            switch (event.type) {
              case GraphqlWsMessageTypes.connectionAck:
                _ackStatus = GQAckStatus.acknoledged;
                return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
              case GraphqlWsMessageTypes.error:
                _ackStatus = GQAckStatus.none;
                throw (event as GraphLinkSubscriptionErrorMessage).payload!;
              default:
                return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
            }
          }).first;
        }
      case GQAckStatus.progress:
      case GQAckStatus.acknoledged:
        return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
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

    _initWs().then((streamSink) {
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

      streamSink.sendMessage(json.encode(message.toJson()));
    });

    return controller.stream;
  }

  GraphLinkSubscriptionErrorMessageBase _parseEvent(String event) {
    var map = jsonDecode(event);
    var payload = map["payload"];
    GraphLinkSubscriptionErrorMessageBase result;
    if (payload is Map) {
      result = GraphLinkSubscriptionMessage.fromJson(map);
    } else {
      result = GraphLinkSubscriptionErrorMessage.fromJson(map);
    }
    return result;
  }

  void _sendPingMessage() {
    adapter.sendMessage(pingMessage);
  }

  void _sendPongMessage() {
    adapter.sendMessage(pongMessage);
  }

  void _handleMessage(GraphLinkSubscriptionErrorMessageBase msg, String uuid) {
    var controller = _map[uuid]!;
    switch (msg.type!) {
      case GraphqlWsMessageTypes.ping:
        _sendPingMessage();
        break;
      case GraphqlWsMessageTypes.pong:
        _sendPongMessage();
        break;
      case GraphqlWsMessageTypes.next:
        controller.add((msg as GraphLinkSubscriptionMessage).payload!.data!);
        break;
      case GraphqlWsMessageTypes.complete:
        _removeController(uuid);
        break;
      case GraphqlWsMessageTypes.error:
        var errorMsg = msg as GraphLinkSubscriptionErrorMessage;
        var ctrl = _map[uuid]!;
        ctrl.addError(errorMsg.payload as Object);
        _removeController(uuid);
        break;
      default:
    }
  }

  void _removeController(String uuid) {
    _subs.remove(uuid)?.cancel();
    _map.remove(uuid)?.close();
    if (_map.isEmpty) {
      adapter.close();
      _ackStatus = GQAckStatus.none;
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
  final Function(String) sendMessage;
  final Stream<String> stream;

  _StreamSink({required this.sendMessage, required this.stream});
}
""";

const _webSocketAdapter = """
abstract class GraphLinkWebSocketAdapter {
  Future<void> onConnectionReady();

  Stream<String> get onMessageStream;

  void sendMessage(String message);

  void close();
}
""";
