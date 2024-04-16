import 'dart:convert';

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

class SubscriptionMessageTypes {
  // ignore: constant_identifier_names
  static const connection_init = "connection_init";
  // ignore: constant_identifier_names
  static const connection_ack = "connection_ack";
  static const subscribe = "subscribe";
  static const next = "next";
  static const complete = "complete";
  static const error = "error";
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
