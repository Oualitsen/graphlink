// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

 import 'package:json_annotation/json_annotation.dart';
 import 'enums.gq.dart';
  part 'types.gq.g.dart';

      @JsonSerializable(explicitToJson: true)
      class Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastName extends BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac {
        
          final String lastName;
          
          Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastName({required this.lastName, required final String firstName}): super(firstName: firstName);
          
          factory Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastName.fromJson(Map<String, dynamic> json) {
             return _$Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastNameFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastNameToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class Client extends BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac {
        
          final int lastUpdate;
          
          Client({required this.lastUpdate, required final String firstName}): super(firstName: firstName);
          
          factory Client.fromJson(Map<String, dynamic> json) {
             return _$ClientFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$ClientToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac {
        
          final String firstName;
          
          BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac({required this.firstName});
          
          factory BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac.fromJson(Map<String, dynamic> json) {
                   var typename = json["__typename"];
      switch(typename) {
        
        case "Driver": return _$Inline_b5e8ad64_03a4_abb8_336d_26cb5a169b67___typename_firstName_lastNameFromJson(json);
        case "Client": return _$ClientFromJson(json);
      }
      return _$BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8acFromJson(json);
    
          }
          
          Map<String, dynamic> toJson() {
            return _$BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8acToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class Driver_firstName_lastName_middleName {
        
          final String firstName;
          final String lastName;
          final String? middleName;
          
          Driver_firstName_lastName_middleName({required this.firstName, required this.lastName, this.middleName});
          
          factory Driver_firstName_lastName_middleName.fromJson(Map<String, dynamic> json) {
             return _$Driver_firstName_lastName_middleNameFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$Driver_firstName_lastName_middleNameToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class Car_carFrag {
        
          final String model;
          final int year;
          
          Car_carFrag({required this.model, required this.year});
          
          factory Car_carFrag.fromJson(Map<String, dynamic> json) {
             return _$Car_carFragFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$Car_carFragToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class Driver_myFrag {
        
          final List<Car_carFrag> cars;
          final String firstName;
          final String id;
          
          Driver_myFrag({required this.cars, required this.firstName, required this.id});
          
          factory Driver_myFrag.fromJson(Map<String, dynamic> json) {
             return _$Driver_myFragFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$Driver_myFragToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class GetUserResponse {
        
          final BasicUser_projection_e5638224_9ccb_4679_2564_2f2b8e87d8ac getUser;
          
          GetUserResponse({required this.getUser});
          
          factory GetUserResponse.fromJson(Map<String, dynamic> json) {
             return _$GetUserResponseFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$GetUserResponseToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class GetDriverByIdResponse {
        
          final Driver_firstName_lastName_middleName getDriverById;
          
          GetDriverByIdResponse({required this.getDriverById});
          
          factory GetDriverByIdResponse.fromJson(Map<String, dynamic> json) {
             return _$GetDriverByIdResponseFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$GetDriverByIdResponseToJson(this);
          }
      }
    
      @JsonSerializable(explicitToJson: true)
      class WatchDriverResponse {
        
          final Driver_myFrag watchDriver;
          
          WatchDriverResponse({required this.watchDriver});
          
          factory WatchDriverResponse.fromJson(Map<String, dynamic> json) {
             return _$WatchDriverResponseFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$WatchDriverResponseToJson(this);
          }
      }
    

