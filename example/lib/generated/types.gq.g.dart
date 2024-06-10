// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'types.gq.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Inline_4ff46788_488c_dc02_5f2f_98101e709fbe___typename_firstName_lastName
    _$Inline_4ff46788_488c_dc02_5f2f_98101e709fbe___typename_firstName_lastNameFromJson(
            Map<String, dynamic> json) =>
        Inline_4ff46788_488c_dc02_5f2f_98101e709fbe___typename_firstName_lastName(
          lastName: json['lastName'] as String,
          firstName: json['firstName'] as String,
        );

Map<String, dynamic>
    _$Inline_4ff46788_488c_dc02_5f2f_98101e709fbe___typename_firstName_lastNameToJson(
            Inline_4ff46788_488c_dc02_5f2f_98101e709fbe___typename_firstName_lastName
                instance) =>
        <String, dynamic>{
          'firstName': instance.firstName,
          'lastName': instance.lastName,
        };

Client _$ClientFromJson(Map<String, dynamic> json) => Client(
      lastUpdate: (json['lastUpdate'] as num).toInt(),
      firstName: json['firstName'] as String,
    );

Map<String, dynamic> _$ClientToJson(Client instance) => <String, dynamic>{
      'firstName': instance.firstName,
      'lastUpdate': instance.lastUpdate,
    };

BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06
    _$BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06FromJson(
            Map<String, dynamic> json) =>
        BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06(
          firstName: json['firstName'] as String,
        );

Map<String,
    dynamic> _$BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06ToJson(
        BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06 instance) =>
    <String, dynamic>{
      'firstName': instance.firstName,
    };

Driver_firstName_lastName_middleName
    _$Driver_firstName_lastName_middleNameFromJson(Map<String, dynamic> json) =>
        Driver_firstName_lastName_middleName(
          firstName: json['firstName'] as String,
          lastName: json['lastName'] as String,
          middleName: json['middleName'] as String?,
        );

Map<String, dynamic> _$Driver_firstName_lastName_middleNameToJson(
        Driver_firstName_lastName_middleName instance) =>
    <String, dynamic>{
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'middleName': instance.middleName,
    };

Car_carFrag _$Car_carFragFromJson(Map<String, dynamic> json) => Car_carFrag(
      model: json['model'] as String,
      year: (json['year'] as num).toInt(),
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
          BasicUser_projection_cbb7f99c_ca2d_2f21_d42f_e6c8fd1cbd06.fromJson(
              json['getUser'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GetUserResponseToJson(GetUserResponse instance) =>
    <String, dynamic>{
      'getUser': instance.getUser.toJson(),
    };

GetDriverByIdResponse _$GetDriverByIdResponseFromJson(
        Map<String, dynamic> json) =>
    GetDriverByIdResponse(
      getDriverById: Driver_firstName_lastName_middleName.fromJson(
          json['getDriverById'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GetDriverByIdResponseToJson(
        GetDriverByIdResponse instance) =>
    <String, dynamic>{
      'getDriverById': instance.getDriverById.toJson(),
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
