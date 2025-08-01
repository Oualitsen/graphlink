import 'package:retrofit_graphql/src/gq_grammar.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/serializers/dart_serializer.dart';
import 'package:retrofit_graphql/src/serializers/gq_client_serilaizer.dart';
import 'package:retrofit_graphql/src/serializers/gq_serializer.dart';

const _operationNameParam = "operationName";

const String enumsFileName = "enums.gq";
const String typesFileName = "types.gq";
const String clientFileName = "client.gq";
const String inputsFileName = "inputs.gq";


class DartClientSerializer extends ClientSerilaizer {
  final GqSerializer _serializer;
  final GQGrammar _grammar;

  DartClientSerializer(this._grammar ): _serializer = DartSerializer(_grammar);

   String generateEnums(GqSerializer serializer) {
    return """
 ${_grammar.enums.values.toList().map((e) => serializer.serializeEnumDefinition(e)).join("\n")}
 """;
  }

  String generateInputs(GqSerializer serializer) {
    var inputs = _grammar.inputs.values.toList().map((e) => serializer.serializeInputDefinition(e)).join("\n");
    return """
import 'package:json_annotation/json_annotation.dart';
import '$enumsFileName.dart';
part '$inputsFileName.g.dart';

$inputs
""";
  }

  String generateTypes(GqSerializer serializer) {
    var data = _grammar.projectedTypes.values.toSet().map((e) => serializer.serializeTypeDefinition(e)).join("\n");

    return """
import 'package:json_annotation/json_annotation.dart';
import '$enumsFileName.dart';
part '$typesFileName.g.dart';

$data

""";
  }

  @override
  String generateClient() {
    return """
import '$enumsFileName.dart';
import '$inputsFileName.dart';
import '$typesFileName.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
${_grammar.hasSubscriptions ? "import 'package:web_socket_channel/web_socket_channel.dart';" : ""}



final _fragmMap = <String, String>{};

String _getFragment(String fragName) {
  return _fragmMap[fragName]!;
}

    ${GQQueryType.values.map((e) => _serializeQueriesClassByType(e)).join("\n")}

class GQClient {
  
  ${_grammar.hasQueries ? 'final Queries queries;' : ''}
  ${_grammar.hasMutations ? 'final Mutations mutations;' : ''}
  ${_grammar.hasSubscriptions ? 'final Subscriptions subscriptions;' : ''}
  GQClient(Future<String> Function(String payload${_grammar.operationNameAsParameter ? ', String $_operationNameParam' : ''}) adapter${_grammar.hasSubscriptions ? ', WebSocketAdapter wsAdapter' : ''})
      :${[
      if (_grammar.hasQueries) 'queries = Queries(adapter)',
      if (_grammar.hasMutations) ' mutations = Mutations(adapter)',
      if (_grammar.hasSubscriptions) 'subscriptions = Subscriptions(wsAdapter)'
    ].where((element) => element.isNotEmpty).join(", ")} {
      
      ${_grammar.fragments.values.map((value) => "_fragmMap['${value.token}'] = '${_grammar.serializer.serializeFragmentDefinitionBase(value)}';").toList().join("\n")}
         
    }
}
  $_graphqlError


  $_graphQLErrorLocation

  $_gqPayload


${_serializeSubscriptions()}
    """
        .trim();
  }

  String _serializeQueriesClassByType(GQQueryType type) {
    var queries = _grammar.queries.values;
    var queryList = queries
        .where((element) => element.type == type && _grammar.hasQueryType(type))
        .toList();
    if (queryList.isEmpty) {
      return "";
    }
    return """
      class ${classNameFromType(type)} {
        ${_declareAdapter(type)}
        ${classNameFromType(type)}${_declareConstructorArgs(type)}
        ${queryList.map((e) => _queryToMethod(e)).join("\n")}

}

    """
        .trim();
  }

  String _declareConstructorArgs(GQQueryType type) {
    if (type == GQQueryType.subscription) {
      return "(WebSocketAdapter adapter) : _handler = SubscriptionHandler(adapter);";
    }
    return "(this._adapter);";
  }

  String _declareAdapter(GQQueryType type) {
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

  String _queryToMethod(GQQueryDefinition def) {
    return """
      ${_returnTypeByQueryType(def)} ${def.token}(${_serializeArgs(def)}) {
        const operationName = "${def.token}";
        ${def.fragments(_grammar).isEmpty ? 'const' : 'final'} fragsValues = ${def.fragments(_grammar).isEmpty ? '"";' : '[${def.fragments(_grammar).map((e) => '"${e.token}"').toList().join(", ")}].map((fragName) => _getFragment(fragName)).join(" ");'}
        ${def.fragments(_grammar).isEmpty ? 'const' : 'final'} query = \"\"\"${_grammar.serializer.serializeQueryDefinition(def)}\$fragsValues\"\"\";

        final variables = <String, dynamic>{
          ${def.arguments.map((e) => "'${e.dartArgumentName}': ${_serializeArgumentValue(def, e.token)}").toList().join(", ")}
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
        ${_serializeAdapterCall(def)}
      }
    """
        .trim();
  }

  String _serializeAdapterCall(GQQueryDefinition def) {
    if (def.type == GQQueryType.subscription) {
      return """
      return _handler.handle(payload)
        .map((e) => ${def.getGeneratedTypeDefinition().token}.fromJson(e));
    """;
    }
    return """
    return _adapter(payload.toString()${_grammar.operationNameAsParameter ? ', operationName' : ''}).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return ${def.getGeneratedTypeDefinition().token}.fromJson(data);
      }).first;
""";
  }

  String _serializeArgumentValue(GQQueryDefinition def, String argName) {
    var arg = def.findByName(argName);
    return _callToJson(arg.dartArgumentName, arg.type);
  }

  String _callToJson(String argName, GQType type) {
    if (_grammar.inputTypeRequiresProjection(type)) {
      if (type is GQListType) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.type)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.toJson()";
      }
    }
    if (_grammar.enums.containsKey(type.token)) {
      if (type is GQListType) {
        return "$argName${_getNullableText(type)}.map((e) => ${_callToJson("e", type.type)}).toList()";
      } else {
        return "$argName${_getNullableText(type)}.name";
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

  String _serializeArgs(GQQueryDefinition def) {
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

  String _returnTypeByQueryType(GQQueryDefinition def) {
    var gen = def.getGeneratedTypeDefinition();

    if (def.type == GQQueryType.subscription) {
      return "Stream<${gen.token}>";
    }
    return "Future<${gen.token}>";
  }

  String _serializeSubscriptions() {
    if (!_grammar.hasSubscriptions) {
      return "";
    }
    return """
    $_subscriptionMessageTypes
    $_subscriptionMessageBase
    $_subscriptionMessage
    $_subscriptionErrorMessage
    $_subscriptionPayload
    $_ackStatusEnum
    $_subscriptionHandler
    $_streamSink
    $_webSocketAdapter

    $_generateUuid

    $_webSocketChannelAdapter

""";
  }
}

const _gqPayload = """
class GQPayload {
  final String query;
  final Map<String, dynamic> variables;
  final String operationName;
  GQPayload({
    required this.query,
    required this.operationName,
    required this.variables,
  });
  factory GQPayload.fromJson(Map<String, dynamic> json) => GQPayload(
        query: json['query'] as String,
        operationName: json['operationName'] as String,
        variables: json['variables'] as Map<String, dynamic>,
      );
  Map<String, dynamic> toJson() => <String, dynamic>{
        'query': query,
        'variables': variables,
        'operationName': operationName,
      };

  @override
  String toString() => jsonEncode(toJson());
}
  """;
const _graphQLErrorLocation = """
  class GraphQLErrorLocation {
  final int line;
  final int column;

  GraphQLErrorLocation(this.line, this.column);

  factory GraphQLErrorLocation.fromJson(Map<String, dynamic> json) => GraphQLErrorLocation(
        json['line'] as int,
        json['column'] as int,
      );
  Map<String, dynamic> toJson() => <String, dynamic>{
        'line': line,
        'column': column,
      };
}
""";
const _graphqlError = """
  class GraphQLError {
  final String message;
  final List<GraphQLErrorLocation>? locations;
  final List<dynamic>? path;
  final Map<String, dynamic>? extensions;

  GraphQLError(this.message, {this.locations, this.extensions, this.path});

  factory GraphQLError.fromJson(Map<String, dynamic> json) => GraphQLError(
        json['message'] as String,
        locations: (json['locations'] as List<dynamic>?)
            ?.map((e) => GraphQLErrorLocation.fromJson(e as Map<String, dynamic>))
            .toList(),
        extensions: json['extensions'] as Map<String, dynamic>?,
        path: json['path'] as List<dynamic>?,
      );
  Map<String, dynamic> toJson() => <String, dynamic>{
        'message': message,
        'locations': locations?.map((e) => e.toJson()).toList(),
        'path': path,
        'extensions': extensions,
      };

  @override
  String toString() {
    return 'GraphQLError: \$message';
  }
}
""";

const _subscriptionMessage = """
  class SubscriptionMessage extends SubscriptionMessageBase {
  final SubscriptionPayload? payload;

  SubscriptionMessage({super.id, super.type, this.payload});

  static SubscriptionMessage fromQuery(String id, GQPayload query) => SubscriptionMessage(
      id: id,
      type: SubscriptionMessageTypes.subscribe,
      payload: SubscriptionPayload(
        query: query.query,
        operationName: query.operationName,
        variables: query.variables,
      ));

  static final connectionInit =
      SubscriptionMessage(type: SubscriptionMessageTypes.connection_init, payload: SubscriptionPayload());

  factory SubscriptionMessage.fromJson(Map<String, dynamic> json) => SubscriptionMessage(
        id: json['id'] as String?,
        type: json['type'] as String?,
        payload: json['payload'] == null
            ? null
            : SubscriptionPayload.fromJson(json['payload'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'payload': payload?.toJson(),
      };

  String toJsonText() => jsonEncode(toJson());
}
""";
const _subscriptionMessageBase = """
    class SubscriptionMessageBase {
  final String? id;
  final String? type;

  SubscriptionMessageBase({this.id, this.type});
}

""";
const _subscriptionMessageTypes = """
  class SubscriptionMessageTypes {
  static const connection_init = "connection_init";
  static const connection_ack = "connection_ack";
  static const subscribe = "subscribe";
  static const next = "next";
  static const complete = "complete";
  static const error = "error";
}

""";

const _subscriptionPayload = """
class SubscriptionPayload {
  final String? query;
  final String? operationName;
  final Map<String, dynamic>? variables;

  final Map<String, dynamic>? data;

  SubscriptionPayload({
    this.query,
    this.operationName,
    this.variables,
    this.data,
  });
  factory SubscriptionPayload.fromJson(Map<String, dynamic> json) => SubscriptionPayload(
        query: json['query'] as String?,
        operationName: json['operationName'] as String?,
        variables: json['variables'] as Map<String, dynamic>?,
        data: json['data'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'query': query,
        'operationName': operationName,
        'variables': variables,
        'data': data,
      };
}
""";
const _ackStatusEnum = """
  enum _AckStatus { none, progress, acknoledged }
""";
const _subscriptionErrorMessage = """
  class SubscriptionErrorMessage extends SubscriptionMessageBase {
  final List<GraphQLError> payload;

  SubscriptionErrorMessage({super.id, super.type, required this.payload});

  factory SubscriptionErrorMessage.fromJson(Map<String, dynamic> json) => SubscriptionErrorMessage(
        id: json['id'] as String?,
        type: json['type'] as String,
        payload: (json['payload'] as List<dynamic>)
            .map((e) => GraphQLError.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'payload': payload,
      };
}

""";

const _subscriptionHandler = """
  class SubscriptionHandler {
  final Map<String, StreamController<Map<String, dynamic>>> _map = {};
  final WebSocketAdapter adapter;
  final connectionInit = SubscriptionMessage(type: SubscriptionMessageTypes.connection_init);

  SubscriptionHandler(this.adapter);

  var ack = StreamController<_StreamSink>();
  var ackStatus = _AckStatus.none;

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
      case _AckStatus.none:
        ackStatus = _AckStatus.progress;
        return adapter.onConnectionReady().asStream().asyncMap((_) {
          var broadcasStream = createBroadcaseStream();
          var r = broadcasStream.map((event) {
            var decoded = jsonDecode(event);
            if (decoded is Map<String, dynamic>) {
              return SubscriptionMessage.fromJson(decoded);
            } else {
              return SubscriptionErrorMessage(payload: decoded);
            }
          }).map((event) {
            switch (event.type) {
              case SubscriptionMessageTypes.connection_ack:
                return broadcasStream;
              case SubscriptionMessageTypes.error:
                throw (event as SubscriptionErrorMessage).payload;
              default:
                return broadcasStream;
            }
          }).map((bs) {
            var streamSink = _StreamSink(sendMessage: adapter.sendMessage, stream: bs);
            ackStatus = _AckStatus.acknoledged;
            ack.sink.add(streamSink);
            return streamSink;
          }).first;
          adapter.sendMessage(connectionInit.toJsonText());
          return r;
        }).first;

      case _AckStatus.progress:
      case _AckStatus.acknoledged:
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
              return SubscriptionMessage.fromJson(map);
            } else if (payload is List) {
              return SubscriptionErrorMessage.fromJson(map);
            }
          })
          .map((event) => event!)
          .where((event) => event.id == uuid)
          .listen((msg) {
            var msgId = msg.id!;
            switch (msg.type!) {
              case SubscriptionMessageTypes.next:
                var msg2 = msg as SubscriptionMessage;
                var ctrl = _map[msgId]!;
                ctrl.add(msg2.payload!.data!);
                break;
              case SubscriptionMessageTypes.complete:
                removeController(msgId);

                break;
              case SubscriptionMessageTypes.error:
                var errorMsg = msg as SubscriptionErrorMessage;
                var ctrl = _map[msgId]!;
                ctrl.addError(errorMsg.payload);
                removeController(msgId);

                break;
              default:
            }
          });

      streamSink.sendMessage(SubscriptionMessage.fromQuery(uuid, pl).toJsonText());
    });

    return controller.stream;
  }

  void removeController(String uuid) {
    var removed = _map.remove(uuid);
    removed?.close();
    if (_map.isEmpty) {
      adapter.close();
      ackStatus = _AckStatus.none;
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
