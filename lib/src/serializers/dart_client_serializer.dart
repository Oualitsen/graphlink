import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_client_serilaizer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';

const _operationNameParam = "operationName";




class DartClientSerializer extends ClientSerilaizer {
  final GqSerializer _serializer;
  final GQGrammar _grammar;

  DartClientSerializer(this._grammar, [GqSerializer? dartSerializer]): _serializer = dartSerializer ?? DartSerializer(_grammar);

 

  @override
  String generateClient() {
    return """
import 'dart:convert';
import 'dart:async';
import 'dart:math';
${_grammar.hasSubscriptions ? "import 'package:web_socket_channel/web_socket_channel.dart';" : ""}






${GQQueryType.values.map((e) => generateQueriesClassByType(e)).where((e) => e!= null).join("\n").ident()}

class GQClient {

  final _fragmMap = <String, String>{};
  
  ${_grammar.hasQueries ? 'late final ${classNameFromType(GQQueryType.query)} queries;' : ''}
  ${_grammar.hasMutations ? 'late final ${classNameFromType(GQQueryType.mutation)} mutations;' : ''}
  ${_grammar.hasSubscriptions ? 'late final ${classNameFromType(GQQueryType.subscription)} subscriptions;' : ''}
  GQClient(Future<String> Function(String payload${_grammar.operationNameAsParameter ? ', String $_operationNameParam' : ''}) adapter${_grammar.hasSubscriptions ? ', WebSocketAdapter wsAdapter' : ''}) {
      
${_grammar.fragments.values.map((value) => "_fragmMap['${value.tokenInfo}'] = '${_grammar.serializer.serializeFragmentDefinitionBase(value)}';").toList().join("\n").ident(2)}
${[
if (_grammar.hasQueries) 'queries = ${classNameFromType(GQQueryType.query)}(adapter, _fragmMap)',
if (_grammar.hasMutations) 'mutations = ${classNameFromType(GQQueryType.mutation)}(adapter, _fragmMap)',
if (_grammar.hasSubscriptions) 'subscriptions = ${classNameFromType(GQQueryType.subscription)}(wsAdapter, _fragmMap)'
].map((e) => e.ident(2)).where((element) => element.isNotEmpty).join(";\n")}; 
    }
}


${serializeSubscriptions().ident()}
    """
        .trim();
  }

  String? generateQueriesClassByType(GQQueryType type) {
    var queries = _grammar.queries.values;
    var queryList = queries
        .where((element) => element.type == type && _grammar.hasQueryType(type))
        .toList();
    if (queryList.isEmpty) {
      return null;
    }

    var buffer = StringBuffer();
    buffer.writeln("class ${classNameFromType(type)} {");
    buffer.writeln(declareAdapter(type).ident());
    buffer.writeln("final Map<String, String> fragmentMap;");
    buffer.write(classNameFromType(type).ident());
    buffer.writeln(_declareConstructorArgs(type));
    buffer.writeln(queryList.map((e) => queryToMethod(e)).join("\n").ident());
    buffer.writeln('}');
    return buffer.toString();
   
  }

  String _declareConstructorArgs(GQQueryType type) {
    if (type == GQQueryType.subscription) {
      return "(WebSocketAdapter adapter, this.fragmentMap): _handler = SubscriptionHandler(adapter);";
    }
    return "(this._adapter, this.fragmentMap);";
  }

  String declareAdapter(GQQueryType type) {
    switch (type) {
      case GQQueryType.query:
      case GQQueryType.mutation:
        return "final Future<String> Function(String payload${_grammar.operationNameAsParameter ? ', String $_operationNameParam' : ''}) _adapter;";
      case GQQueryType.subscription:
        return """
        final SubscriptionHandler _handler;
        """;
    }
  }

  String queryToMethod(GQQueryDefinition def) {
     return """
${returnTypeByQueryType(def)} ${def.tokenInfo}(${serializeArgs(def)}) {
    const operationName = "${def.tokenInfo}";
    ${def.fragments(_grammar).isEmpty ? 'const' : 'final'} fragsValues = ${def.fragments(_grammar).isEmpty ? '"";' : '[${def.fragments(_grammar).map((e) => '"${e.tokenInfo}"').toList().join(", ")}].map((fragName) => fragmentMap[fragName]!).join(" ");'}
    ${def.fragments(_grammar).isEmpty ? 'const' : 'final'} query = \"\"\"${_grammar.serializer.serializeQueryDefinition(def)}\$fragsValues\"\"\";

${generateVariables(def).ident()}
        
    final payload = GQPayload(query: query, operationName: operationName, variables: variables);
    ${_serializeAdapterCall(def)}
}
    """
        .trim();
    
  }

  String generateVariables(GQQueryDefinition def) {
    return '''
final variables = <String, dynamic>{
${def.arguments.map((e) => "'${e.dartArgumentName}': ${_serializeArgumentValue(def, e.token)}").map((e) => e.ident()).toList().join(", ")}
};
'''.trim();
  }

  String _serializeAdapterCall(GQQueryDefinition def) {
    if (def.type == GQQueryType.subscription) {
      return """
return _handler.handle(payload).map((e) => ${def.getGeneratedTypeDefinition().tokenInfo.token}.fromJson(e));
    """.trim().ident();
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
    if(type.nullable) {
      return "?";
    }
    return "";
  }

  String serializeArgs(GQQueryDefinition def) {
    if (def.arguments.isEmpty) {
      return "";
    }
    var result = def.arguments
        .map((e) =>
            "${_serializer.serializeType(e.type, false)} ${e.dartArgumentName}")
        .map((e) => "required $e")
        .toList()
        .join(", ");
    return "{$result}";
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
$_generateUuid
$_webSocketChannelAdapter
""";
  }

  String get fileExtension => '.dart';
}


const _subscriptionHandler = """
class SubscriptionHandler {
  final Map<String, StreamController<Map<String, dynamic>>> _map = {};
  final WebSocketAdapter adapter;
  final connectionInit = GQSubscriptionErrorMessage(type: GQSubscriptionMessageType.connection_init);

  SubscriptionHandler(this.adapter);

  var ack = StreamController<_StreamSink>();
  var ackStatus = GQAckStatus.none;

  Stream<String>? _cahce;

  Stream<String> createBroadcaseStream() {
    var stream = adapter.onMessageStream;
    if (stream.isBroadcast) {
      return stream;
    }
    if (_cahce != null) {
      return _cahce!;
    }
    return _cahce = stream.asBroadcastStream();
  }

  Future<_StreamSink> _initWs() async {
    switch (ackStatus) {
      case GQAckStatus.none:
        ackStatus = GQAckStatus.progress;
        return adapter.onConnectionReady().asStream().asyncMap((_) {
          var broadcasStream = createBroadcaseStream();
          var r = broadcasStream.map((event) {
            var decoded = jsonDecode(event);
            if (decoded is Map<String, dynamic>) {
              return GQSubscriptionMessage.fromJson(decoded);
            } else {
              return GQSubscriptionErrorMessage(payload: decoded);
            }
          }).map((event) {
            switch (event.type) {
              case GQSubscriptionMessageType.connection_ack:
                return broadcasStream;
              case GQSubscriptionMessageType.error:
                throw (event as GQSubscriptionErrorMessage).payload!;
              default:
                return broadcasStream;
            }
          }).map((bs) {
            var streamSink = _StreamSink(sendMessage: adapter.sendMessage, stream: bs);
            ackStatus = GQAckStatus.acknoledged;
            ack.sink.add(streamSink);
            return streamSink;
          }).first;
          adapter.sendMessage(json.encode(connectionInit.toJson()));
          return r;
        }).first;

      case GQAckStatus.progress:
      case GQAckStatus.acknoledged:
        return ack.stream.first;
    }
  }

  Stream<Map<String, dynamic>> handle(GQPayload pl) {
    var controller = StreamController<Map<String, dynamic>>();
    String uuid = generateUuid();
    _map[uuid] = controller;
    _initWs().then((streamSink) {
      streamSink.stream
          .map((event) {
            var map = jsonDecode(event);
            var payload = map["payload"];
            if (payload is Map) {
              return GQSubscriptionMessage.fromJson(map);
            } else if (payload is List) {
              return GQSubscriptionErrorMessage.fromJson(map);
            }
          })
          .map((event) => event!)
          .where((event) => event.id == uuid)
          .listen((msg) {
            var msgId = msg.id!;
            switch (msg.type!) {
              case GQSubscriptionMessageType.next:
                var msg2 = msg as GQSubscriptionMessage;
                var ctrl = _map[msgId]!;
                ctrl.add(msg2.payload!.data!);
                break;
              case GQSubscriptionMessageType.complete:
                removeController(msgId);

                break;
              case GQSubscriptionMessageType.error:
                var errorMsg = msg as GQSubscriptionErrorMessage;
                var ctrl = _map[msgId]!;
                ctrl.addError(errorMsg.payload as Object);
                removeController(msgId);

                break;
              default:
            }
          });
          var message =  GQSubscriptionMessage(
        id: uuid,
        type: GQSubscriptionMessageType.subscribe,
        payload: GQSubscriptionPayload(
          query: pl.query,
          operationName: pl.operationName,
          variables: pl.variables,
        )).toJson();

      streamSink.sendMessage(json.encode(message));
    });

    return controller.stream;
  }

  void removeController(String uuid) {
    var removed = _map.remove(uuid);
    removed?.close();
    if (_map.isEmpty) {
      adapter.close();
      ackStatus = GQAckStatus.none;
      ack.close();
      _cahce = null;
      ack = StreamController<_StreamSink>();
    }
  }
}
""";

const _streamSink = """
  class _StreamSink {
  final Function(String) sendMessage;
  final Stream<dynamic> stream;

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
const _generateUuid = """
String generateUuid([String separator = "-"]) {
  final random = Random();
  const hexDigits = '0123456789abcdef';

  String generateRandomString(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      final randomIndex = random.nextInt(hexDigits.length);
      buffer.write(hexDigits[randomIndex]);
    }
    return buffer.toString();
  }

  return [
    generateRandomString(8),
    generateRandomString(4),
    generateRandomString(4),
    generateRandomString(4),
    generateRandomString(12),
  ].join(separator);
}

""";

const _webSocketChannelAdapter = """
  class WebSocketChannelAdapter implements WebSocketAdapter {
  final String url;
  WebSocketChannelAdapter(this.url);

  WebSocketChannel? channel;

  @override
  Future<void> onConnectionReady() async {
    if (channel != null) {
      return;
    }
    channel = WebSocketChannel.connect(Uri.parse(url));
    return channel!.ready;
  }

  @override
  sendMessage(String message) {
    channel!.sink.add(message);
  }

  @override
  Stream<String> get onMessageStream =>
      channel!.stream.map((event) => event as String);

  @override
  void close() {
    channel?.sink.close();
    channel = null;
  }
}
""";
