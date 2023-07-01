// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graphql_data_objects.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SubscriptionMessage _$SubscriptionMessageFromJson(Map<String, dynamic> json) =>
    SubscriptionMessage(
      id: json['id'] as String?,
      type: $enumDecodeNullable(_$SubscriptionMessageTypeEnumMap, json['type']),
      payload: json['payload'] == null
          ? null
          : SubscriptionPayload.fromJson(
              json['payload'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SubscriptionMessageToJson(
        SubscriptionMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$SubscriptionMessageTypeEnumMap[instance.type],
      'payload': instance.payload,
    };

const _$SubscriptionMessageTypeEnumMap = {
  SubscriptionMessageType.connection_init: 'connection_init',
  SubscriptionMessageType.connection_ack: 'connection_ack',
  SubscriptionMessageType.subscribe: 'subscribe',
  SubscriptionMessageType.next: 'next',
  SubscriptionMessageType.complete: 'complete',
  SubscriptionMessageType.error: 'error',
};

SubscriptionErrorMessage _$SubscriptionErrorMessageFromJson(
        Map<String, dynamic> json) =>
    SubscriptionErrorMessage(
      id: json['id'] as String?,
      type: $enumDecodeNullable(_$SubscriptionMessageTypeEnumMap, json['type']),
      payload: (json['payload'] as List<dynamic>)
          .map((e) => GraphQLError.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SubscriptionErrorMessageToJson(
        SubscriptionErrorMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$SubscriptionMessageTypeEnumMap[instance.type],
      'payload': instance.payload,
    };

SubscriptionPayload _$SubscriptionPayloadFromJson(Map<String, dynamic> json) =>
    SubscriptionPayload(
      query: json['query'] as String?,
      operationName: json['operationName'] as String?,
      variables: json['variables'] as Map<String, dynamic>?,
      data: json['data'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$SubscriptionPayloadToJson(
        SubscriptionPayload instance) =>
    <String, dynamic>{
      'query': instance.query,
      'operationName': instance.operationName,
      'variables': instance.variables,
      'data': instance.data,
    };

GraphQLError _$GraphQLErrorFromJson(Map<String, dynamic> json) => GraphQLError(
      json['message'] as String,
      locations: (json['locations'] as List<dynamic>?)
          ?.map((e) => GraphQLErrorLocation.fromJson(e as Map<String, dynamic>))
          .toList(),
      extensions: json['extensions'] as Map<String, dynamic>?,
      path: json['path'] as List<dynamic>?,
    );

Map<String, dynamic> _$GraphQLErrorToJson(GraphQLError instance) =>
    <String, dynamic>{
      'message': instance.message,
      'locations': instance.locations,
      'path': instance.path,
      'extensions': instance.extensions,
    };

GraphQLErrorLocation _$GraphQLErrorLocationFromJson(
        Map<String, dynamic> json) =>
    GraphQLErrorLocation(
      json['line'] as int,
      json['column'] as int,
    );

Map<String, dynamic> _$GraphQLErrorLocationToJson(
        GraphQLErrorLocation instance) =>
    <String, dynamic>{
      'line': instance.line,
      'column': instance.column,
    };

GQPayload _$GQPayloadFromJson(Map<String, dynamic> json) => GQPayload(
      query: json['query'] as String,
      operationName: json['operationName'] as String,
      variables: json['variables'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$GQPayloadToJson(GQPayload instance) => <String, dynamic>{
      'query': instance.query,
      'variables': instance.variables,
      'operationName': instance.operationName,
    };
