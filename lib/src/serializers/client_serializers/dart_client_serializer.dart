import 'package:retrofit_graphql/src/code_gen_utils.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/serializers/gq_client_serilaizer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';

const _operationNameParam = "operationName";

class DartClientSerializer extends ClientSerilaizer {
  final GQGrammar _grammar;
  final codeGenUtils = DartCodeGenUtils();

  DartClientSerializer(this._grammar, GqSerializer dartSerializer) : super(dartSerializer);

  @override
  String generateClient(String importPrefix) {
    var imports = serializeImports(_grammar, importPrefix);

    var buffer = StringBuffer();
    buffer.writeln("import 'dart:convert';");
    buffer.writeln("import 'dart:async';");
    buffer.writeln("import 'dart:math';");
    buffer.writeln(imports);

    GQQueryType.values
        .map((e) => generateQueriesClassByType(e))
        .where((e) => e != null)
        .map((e) => e!)
        .forEach((line) {
      buffer.writeln(line);
    });

    buffer.writeln(codeGenUtils.createClass(className: 'GQClient', statements: [
      'final _fragmMap = <String, String>{};',
      if (_grammar.hasQueries) 'late final ${classNameFromType(GQQueryType.query)} queries;',
      if (_grammar.hasMutations) 'late final ${classNameFromType(GQQueryType.mutation)} mutations;',
      if (_grammar.hasSubscriptions)
        'late final ${classNameFromType(GQQueryType.subscription)} subscriptions;',
      codeGenUtils.createMethod(
        methodName: 'GQClient',
        arguments: [
          _adapterDeclaration(),
          if (_grammar.hasSubscriptions) 'WebSocketAdapter wsAdapter'
        ],
        namedArguments: false,
        statements: [
          ..._grammar.fragments.values.map((value) =>
              "_fragmMap['${value.tokenInfo}'] = '${_grammar.serializer.serializeFragmentDefinitionBase(value)}';"),
          if (_grammar.hasQueries)
            "queries = ${classNameFromType(GQQueryType.query)}(adapter, _fragmMap);",
          if (_grammar.hasMutations)
            "mutations = ${classNameFromType(GQQueryType.mutation)}(adapter, _fragmMap);",
          if (_grammar.hasSubscriptions)
            "subscriptions = ${classNameFromType(GQQueryType.subscription)}(wsAdapter, _fragmMap);",
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

  String? generateQueriesClassByType(GQQueryType type) {
    var queries = _grammar.queries.values;
    var queryList =
        queries.where((element) => element.type == type && _grammar.hasQueryType(type)).toList();
    if (queryList.isEmpty) {
      return null;
    }

    return codeGenUtils.createClass(className: classNameFromType(type), statements: [
      declareAdapter(type),
      "final Map<String, String> fragmentMap;",
      codeGenUtils.createMethod(
          methodName: classNameFromType(type),
          arguments: _declareConstructorArgs(type),
          namedArguments: false,
          statements: [
            if (type == GQQueryType.subscription) '_handler = _SubscriptionHandler(adapter);',
          ]),
      ...queryList.map((e) => queryToMethod(e))
    ]);
  }

  List<String> _declareConstructorArgs(GQQueryType type) {
    if (type == GQQueryType.subscription) {
      return ['WebSocketAdapter adapter', 'this.fragmentMap'];
    }
    return ['this._adapter', 'this.fragmentMap'];
  }

  String declareAdapter(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
      case GQQueryType.mutation:
        return "final Future<String> Function(String payload${_grammar.operationNameAsParameter ? ', String $_operationNameParam' : ''}) _adapter;";
      case GQQueryType.subscription:
        return "late final _SubscriptionHandler _handler;";
    }
  }

  String queryToMethod(GQQueryDefinition def) {
    return codeGenUtils.createMethod(
        returnType: returnTypeByQueryType(def),
        methodName: def.tokenInfo.token,
        arguments: getArguments(def),
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
          "final payload = GQPayload(query: query, operationName: operationName, variables: variables);",
          _serializeAdapterCall(def)
        ]);
  }

  String generateVariables(GQQueryDefinition def) {
    var buffer = StringBuffer("final variables = <String, dynamic>{");
    buffer.writeln();
    def.arguments
        .map((e) => "'${e.dartArgumentName}': ${_serializeArgumentValue(def, e.token)},")
        .forEach((line) {
      buffer.writeln(line.ident());
    });
    buffer.writeln("};");
    return buffer.toString();
  }

  String _serializeAdapterCall(GQQueryDefinition def) {
    if (def.type == GQQueryType.subscription) {
      return """
return _handler.handle(payload).map((e) => ${def.getGeneratedTypeDefinition().tokenInfo.token}.fromJson(e));
    """
          .trim()
          .ident();
    }
    return """
return _adapter(json.encode(payload.toJson())${_grammar.operationNameAsParameter ? ', operationName' : ''}).asStream().map((response) {
    Map<String, dynamic> result = jsonDecode(response);
    if (result.containsKey("errors")) {
      throw result["errors"].map((error) => GQError.fromJson(error)).toList();
    }
    var data = result["data"];
    return ${def.getGeneratedTypeDefinition().tokenInfo}.fromJson(data);
}).first;
""";
  }

  String _serializeArgumentValue(GQQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GQType type) {
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

  String _getNullableText(GQType type) {
    if (type.nullable) {
      return "?";
    }
    return "";
  }

  List<String> getArguments(GQQueryDefinition def) {
    if (def.arguments.isEmpty) {
      return [];
    }
    return def.arguments
        .map((e) => "${serializer.serializeType(e.type, false)} ${e.dartArgumentName}")
        .map((e) => "required $e")
        .toList();
  }

  String returnTypeByQueryType(GQQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GQQueryType.subscription) {
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
  final WebSocketAdapter adapter;

  final connectionInit = jsonEncode(GQSubscriptionErrorMessage(type: GraphqlWsMessageTypes.connectionInit).toJson());
  final pingMessage = jsonEncode(GQSubscriptionErrorMessage(type: GraphqlWsMessageTypes.ping).toJson());
  final pongMessage = jsonEncode(GQSubscriptionErrorMessage(type: GraphqlWsMessageTypes.pong).toJson());

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
              return GQSubscriptionMessage.fromJson(decoded);
            } else {
              return GQSubscriptionErrorMessage(payload: decoded);
            }
          }).map((event) {
            switch (event.type) {
              case GraphqlWsMessageTypes.connectionAck:
                _ackStatus = GQAckStatus.acknoledged;
                return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
              case GraphqlWsMessageTypes.error:
                _ackStatus = GQAckStatus.none;
                throw (event as GQSubscriptionErrorMessage).payload!;
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

  Stream<Map<String, dynamic>> handle(GQPayload pl) {
    String uuid = _generateUuid();
    var controller = _createStremController(uuid);

    _initWs().then((streamSink) {
      var sub = streamSink.stream
          .map(_parseEvent)
          .where((event) => event.id == uuid)
          .listen((msg) => _handleMessage(msg, uuid));
      _subs[uuid] = sub;
      var message = GQSubscriptionMessage(
          id: uuid,
          type: GraphqlWsMessageTypes.subscribe,
          payload: GQSubscriptionPayload(
            query: pl.query,
            operationName: pl.operationName,
            variables: pl.variables,
          ));

      streamSink.sendMessage(json.encode(message.toJson()));
    });

    return controller.stream;
  }

  GQSubscriptionErrorMessageBase _parseEvent(String event) {
    var map = jsonDecode(event);
    var payload = map["payload"];
    GQSubscriptionErrorMessageBase result;
    if (payload is Map) {
      result = GQSubscriptionMessage.fromJson(map);
    } else {
      result = GQSubscriptionErrorMessage.fromJson(map);
    }
    return result;
  }

  void _sendPingMessage() {
    adapter.sendMessage(pingMessage);
  }

  void _sendPongMessage() {
    adapter.sendMessage(pongMessage);
  }

  void _handleMessage(GQSubscriptionErrorMessageBase msg, String uuid) {
    var controller = _map[uuid]!;
    switch (msg.type!) {
      case GraphqlWsMessageTypes.ping:
        _sendPingMessage();
        break;
      case GraphqlWsMessageTypes.pong:
        _sendPongMessage();
        break;
      case GraphqlWsMessageTypes.next:
        controller.add((msg as GQSubscriptionMessage).payload!.data!);
        break;
      case GraphqlWsMessageTypes.complete:
        _removeController(uuid);
        break;
      case GraphqlWsMessageTypes.error:
        var errorMsg = msg as GQSubscriptionErrorMessage;
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
abstract class WebSocketAdapter {
  Future<void> onConnectionReady();

  Stream<String> get onMessageStream;

  void sendMessage(String message);

  void close();
}
""";
