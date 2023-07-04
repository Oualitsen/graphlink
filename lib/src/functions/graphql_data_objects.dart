import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'graphql_data_objects.g.dart';

class SubscriptionMessageBase {
  final String? id;
  final SubscriptionMessageType? type;

  SubscriptionMessageBase({this.id, this.type});
}

@JsonSerializable()
class SubscriptionMessage extends SubscriptionMessageBase {
  final SubscriptionPayload? payload;

  SubscriptionMessage({super.id, super.type, this.payload});

  static SubscriptionMessage fromQuery(String id, GQPayload query) =>
      SubscriptionMessage(
          id: id,
          type: SubscriptionMessageType.subscribe,
          payload: SubscriptionPayload(
            query: query.query,
            operationName: query.operationName,
            variables: query.variables,
          ));

  static final connectionInit = SubscriptionMessage(
      type: SubscriptionMessageType.connection_init,
      payload: SubscriptionPayload());

  factory SubscriptionMessage.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionMessageFromJson(json);

  Map<String, dynamic> toJson() => _$SubscriptionMessageToJson(this);

  String toJsonText() => jsonEncode(toJson());
}

@JsonSerializable()
class SubscriptionErrorMessage extends SubscriptionMessageBase {
  final List<GraphQLError> payload;

  SubscriptionErrorMessage({super.id, super.type, required this.payload});

  factory SubscriptionErrorMessage.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionErrorMessageFromJson(json);

  Map<String, dynamic> toJson() => _$SubscriptionErrorMessageToJson(this);
}

@JsonSerializable()
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
  factory SubscriptionPayload.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionPayloadFromJson(json);

  Map<String, dynamic> toJson() => _$SubscriptionPayloadToJson(this);
}

enum SubscriptionMessageType {
  // ignore: constant_identifier_names
  connection_init,
  // ignore: constant_identifier_names
  connection_ack,
  subscribe,
  next,
  complete,
  error
}

@JsonSerializable()
class GraphQLError {
  final String message;
  final List<GraphQLErrorLocation>? locations;
  final List<dynamic>? path;
  final Map<String, dynamic>? extensions;

  GraphQLError(this.message, {this.locations, this.extensions, this.path});

  factory GraphQLError.fromJson(Map<String, dynamic> json) =>
      _$GraphQLErrorFromJson(json);
  Map<String, dynamic> toJson() => _$GraphQLErrorToJson(this);

  @override
  String toString() {
    return 'GraphQLError: $message';
  }
}

@JsonSerializable()
class GraphQLErrorLocation {
  final int line;
  final int column;

  GraphQLErrorLocation(this.line, this.column);

  factory GraphQLErrorLocation.fromJson(Map<String, dynamic> json) =>
      _$GraphQLErrorLocationFromJson(json);
  Map<String, dynamic> toJson() => _$GraphQLErrorLocationToJson(this);
}

@JsonSerializable()
class GQPayload {
  final String query;
  final Map<String, dynamic> variables;
  final String operationName;
  GQPayload({
    required this.query,
    required this.operationName,
    required this.variables,
  });
  factory GQPayload.fromJson(Map<String, dynamic> json) =>
      _$GQPayloadFromJson(json);
  Map<String, dynamic> toJson() => _$GQPayloadToJson(this);

  @override
  String toString() => jsonEncode(toJson());
}
