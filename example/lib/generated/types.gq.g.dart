// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'types.gq.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Driver _$DriverFromJson(Map<String, dynamic> json) => Driver(
      lastName: json['lastName'] as String,
      firstName: json['firstName'] as String,
    );

Map<String, dynamic> _$DriverToJson(Driver instance) => <String, dynamic>{
      'firstName': instance.firstName,
      'lastName': instance.lastName,
    };

Client _$ClientFromJson(Map<String, dynamic> json) => Client(
      lastUpdate: json['lastUpdate'] as int,
      firstName: json['firstName'] as String,
    );

Map<String, dynamic> _$ClientToJson(Client instance) => <String, dynamic>{
      'firstName': instance.firstName,
      'lastUpdate': instance.lastUpdate,
    };

BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390a
    _$BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390aFromJson(
            Map<String, dynamic> json) =>
        BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390a(
          firstName: json['firstName'] as String,
        );

Map<String,
    dynamic> _$BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390aToJson(
        BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390a instance) =>
    <String, dynamic>{
      'firstName': instance.firstName,
    };

Car_carFrag _$Car_carFragFromJson(Map<String, dynamic> json) => Car_carFrag(
      model: json['model'] as String,
      year: json['year'] as int,
    );

Map<String, dynamic> _$Car_carFragToJson(Car_carFrag instance) =>
    <String, dynamic>{
      'model': instance.model,
      'year': instance.year,
    };

Driver_myFrag _$Driver_myFragFromJson(Map<String, dynamic> json) =>
    Driver_myFrag(
      cars: (json['cars'] as List<dynamic>)
          .map((e) => Car_carFrag.fromJson(e as Map<String, dynamic>))
          .toList(),
      firstName: json['firstName'] as String,
      id: json['id'] as String,
    );

Map<String, dynamic> _$Driver_myFragToJson(Driver_myFrag instance) =>
    <String, dynamic>{
      'cars': instance.cars.map((e) => e.toJson()).toList(),
      'firstName': instance.firstName,
      'id': instance.id,
    };

GetUserResponse _$GetUserResponseFromJson(Map<String, dynamic> json) =>
    GetUserResponse(
      getUser:
          BasicUser_projection_6e4cbe57_500e_f574_cd0a_124b2162390a.fromJson(
              json['getUser'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GetUserResponseToJson(GetUserResponse instance) =>
    <String, dynamic>{
      'getUser': instance.getUser.toJson(),
    };

WatchDriverResponse _$WatchDriverResponseFromJson(Map<String, dynamic> json) =>
    WatchDriverResponse(
      watchDriver:
          Driver_myFrag.fromJson(json['watchDriver'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$WatchDriverResponseToJson(
        WatchDriverResponse instance) =>
    <String, dynamic>{
      'watchDriver': instance.watchDriver.toJson(),
    };
