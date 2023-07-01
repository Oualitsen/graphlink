// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'types.gq.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
      'cars': instance.cars,
      'firstName': instance.firstName,
      'id': instance.id,
    };

Car_year _$Car_yearFromJson(Map<String, dynamic> json) => Car_year(
      year: json['year'] as int,
    );

Map<String, dynamic> _$Car_yearToJson(Car_year instance) => <String, dynamic>{
      'year': instance.year,
    };

Driver_DriverFragment _$Driver_DriverFragmentFromJson(
        Map<String, dynamic> json) =>
    Driver_DriverFragment(
      cars: (json['cars'] as List<dynamic>)
          .map((e) => Car_year.fromJson(e as Map<String, dynamic>))
          .toList(),
      firstName: json['firstName'] as String,
      id: json['id'] as String,
      lastName: json['lastName'] as String,
    );

Map<String, dynamic> _$Driver_DriverFragmentToJson(
        Driver_DriverFragment instance) =>
    <String, dynamic>{
      'cars': instance.cars,
      'firstName': instance.firstName,
      'id': instance.id,
      'lastName': instance.lastName,
    };

WatchDriverResponse _$WatchDriverResponseFromJson(Map<String, dynamic> json) =>
    WatchDriverResponse(
      watchDriver:
          Driver_myFrag.fromJson(json['watchDriver'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$WatchDriverResponseToJson(
        WatchDriverResponse instance) =>
    <String, dynamic>{
      'watchDriver': instance.watchDriver,
    };

GetDriversResponse _$GetDriversResponseFromJson(Map<String, dynamic> json) =>
    GetDriversResponse(
      getDriverById: Driver_DriverFragment.fromJson(
          json['getDriverById'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GetDriversResponseToJson(GetDriversResponse instance) =>
    <String, dynamic>{
      'getDriverById': instance.getDriverById,
    };
