// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

import 'enums.gq.dart';
import 'inputs.gq.dart';
import 'types.gq.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';



final _fragmMap = <String, String>{};

String _getFragment(String fragName) {
  return _fragmMap[fragName]!;
}

    class Queries {
        final Future<String> Function(String payload) _adapter;
        Queries(this._adapter);
        Future<GetUserResponse> getUser({required String id, required bool? client}) {
        const operationName = "getUser";
        const fragsValues = "";
        const query = """query getUser(\$id:ID!,\$client:Boolean){getUser(id:\$id,client:\$client){... on Driver  {firstName lastName __typename}  ... on Client  {lastUpdate firstName __typename}}}$fragsValues""";

        final variables = <String, dynamic>{
          'id': id, 'client': client
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
            return _adapter(payload.toString()).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return GetUserResponse.fromJson(data);
      }).first;

      }
Future<GetDriverByIdResponse> getDriverById({required String id}) {
        const operationName = "getDriverById";
        const fragsValues = "";
        const query = """query getDriverById(\$id:ID!){getDriverById(id:\$id){firstName lastName middleName}}$fragsValues""";

        final variables = <String, dynamic>{
          'id': id
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
            return _adapter(payload.toString()).asStream().map((response) {
          Map<String, dynamic> result = jsonDecode(response);
          if (result.containsKey("errors")) {
            throw result["errors"].map((error) => GraphQLError.fromJson(error)).toList();
          }
          var data = result["data"];
          return GetDriverByIdResponse.fromJson(data);
      }).first;

      }

}

class Subscriptions {
                final SubscriptionHandler _handler;
        
        Subscriptions(WebSocketAdapter adapter) : _handler = SubscriptionHandler(adapter);
        Stream<WatchDriverResponse> watchDriver({required String id}) {
        const operationName = "watchDriver";
        final fragsValues = ["myFrag", "carFrag"].map((fragName) => _getFragment(fragName)).join(" ");
        final query = """subscription watchDriver(\$id:ID!){watchDriver(id:\$id){...myFrag}}$fragsValues""";

        final variables = <String, dynamic>{
          'id': id
        };
        
        final payload = GQPayload(query: query, operationName: operationName, variables: variables);
              return _handler.handle(payload)
        .map((e) => WatchDriverResponse.fromJson(e));
    
      }

}

class GQClient {
  
  final Queries queries;
  
  final Subscriptions subscriptions;
  GQClient(Future<String> Function(String payload) adapter, WebSocketAdapter wsAdapter)
      :queries = Queries(adapter), subscriptions = Subscriptions(wsAdapter) {
      
      _fragmMap['Inline_e6a98805_9c1e_b4b1_3829_30bad3cbe47b'] = '... on Driver  {firstName lastName __typename} ';
_fragmMap['Inline_5b1aad20_c975_e940_991f_2a434c27f6fe'] = '... on Client  {lastUpdate firstName __typename} ';
_fragmMap['DriverFragment'] = 'fragment DriverFragment on Driver{firstName lastName id cars{year}}';
_fragmMap['myFrag'] = 'fragment myFrag on Driver{id firstName cars{...carFrag}}';
_fragmMap['carFrag'] = 'fragment carFrag on Car{model year}';
_fragmMap['_all_fields_BasicEntity'] = 'fragment _all_fields_BasicEntity on BasicEntity{creationDate id lastUpdate}';
_fragmMap['_all_fields_BasicUser'] = 'fragment _all_fields_BasicUser on BasicUser{creationDate dateOfBirth firstName gender id lastName lastUpdate middleName}';
_fragmMap['_all_fields_Driver'] = 'fragment _all_fields_Driver on Driver{cars{..._all_fields_Car} creationDate dateOfBirth email email3 firstName gender id lastName lastUpdate middleName phoneNumber}';
_fragmMap['_all_fields_Client'] = 'fragment _all_fields_Client on Client{creationDate dateOfBirth email firstName gender id lastName lastUpdate middleName phoneNumber}';
_fragmMap['_all_fields_Car'] = 'fragment _all_fields_Car on Car{brand imageUrl model year}';
_fragmMap['_all_fields_Home'] = 'fragment _all_fields_Home on Home{address lat lng owner{..._all_fields_BasicUser}}';
         
    }
}

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
    return 'GraphQLError: $message';
  }
}

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

    class SubscriptionMessageTypes {
  static const connection_init = "connection_init";
  static const connection_ack = "connection_ack";
  static const subscribe = "subscribe";
  static const next = "next";
  static const complete = "complete";
  static const error = "error";
}


class SubscriptionMessageBase {
  final String? id;
  final String? type;

  SubscriptionMessageBase({this.id, this.type});
}

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
enum _AckStatus { none, progress, acknoledged }

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

class _StreamSink {
  final Function(String) sendMessage;
  final Stream<dynamic> stream;

  _StreamSink({required this.sendMessage, required this.stream});
}

abstract class WebSocketAdapter {
  Future<void> onConnectionReady();

  Stream<String> get onMessageStream;

  void sendMessage(String message);

  void close();
}

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
