// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

 import 'package:json_annotation/json_annotation.dart';
 import 'enums.gq.dart';
  part 'types.gq.g.dart';

      @JsonSerializable()
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
    
      @JsonSerializable()
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
    
      @JsonSerializable()
      class Driver extends BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106 {
        
          final String lastName;
          
          Driver({required this.lastName, required final String firstName}): super(firstName: firstName);
          
          factory Driver.fromJson(Map<String, dynamic> json) {
             return _$DriverFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$DriverToJson(this);
          }
      }
    
      @JsonSerializable()
      class Client extends BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106 {
        
          final int lastUpdate;
          
          Client({required this.lastUpdate, required final String firstName}): super(firstName: firstName);
          
          factory Client.fromJson(Map<String, dynamic> json) {
             return _$ClientFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$ClientToJson(this);
          }
      }
    
      @JsonSerializable()
      class BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106 {
        
          final String firstName;
          
          BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106({required this.firstName});
          
          factory BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106.fromJson(Map<String, dynamic> json) {
                   var typename = json["__typename"];
      switch(typename) {
        
        case "Driver": return _$DriverFromJson(json);
        case "Client": return _$ClientFromJson(json);
      }
      return _$BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106FromJson(json);
    
          }
          
          Map<String, dynamic> toJson() {
            return _$BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106ToJson(this);
          }
      }
    
      @JsonSerializable()
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
    
      @JsonSerializable()
      class GetUserResponse {
        
          final BasicUser_projection_d10ee51b_dcca_a04d_a552_5937b721d106 getUser;
          
          GetUserResponse({required this.getUser});
          
          factory GetUserResponse.fromJson(Map<String, dynamic> json) {
             return _$GetUserResponseFromJson(json);
          }
          
          Map<String, dynamic> toJson() {
            return _$GetUserResponseToJson(this);
          }
      }
    

