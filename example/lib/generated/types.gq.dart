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
          
          factory Car_carFrag.fromJson(Map<String, dynamic> json) => _$Car_carFragFromJson(json);
          
          Map<String, dynamic> toJson() => _$Car_carFragToJson(this);
      }
    
      @JsonSerializable()
      class Driver_myFrag {
          final List<Car_carFrag> cars;
          final String firstName;
          final String id;
          
          Driver_myFrag({required this.cars, required this.firstName, required this.id});
          
          factory Driver_myFrag.fromJson(Map<String, dynamic> json) => _$Driver_myFragFromJson(json);
          
          Map<String, dynamic> toJson() => _$Driver_myFragToJson(this);
      }
    
      @JsonSerializable()
      class Car_year {
          final int year;
          
          Car_year({required this.year});
          
          factory Car_year.fromJson(Map<String, dynamic> json) => _$Car_yearFromJson(json);
          
          Map<String, dynamic> toJson() => _$Car_yearToJson(this);
      }
    
      @JsonSerializable()
      class Driver_DriverFragment {
          final List<Car_year> cars;
          final String firstName;
          final String id;
          final String lastName;
          
          Driver_DriverFragment({required this.cars, required this.firstName, required this.id, required this.lastName});
          
          factory Driver_DriverFragment.fromJson(Map<String, dynamic> json) => _$Driver_DriverFragmentFromJson(json);
          
          Map<String, dynamic> toJson() => _$Driver_DriverFragmentToJson(this);
      }
    
      @JsonSerializable()
      class WatchDriverResponse {
          final Driver_myFrag watchDriver;
          
          WatchDriverResponse({required this.watchDriver});
          
          factory WatchDriverResponse.fromJson(Map<String, dynamic> json) => _$WatchDriverResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$WatchDriverResponseToJson(this);
      }
    
      @JsonSerializable()
      class GetDriversResponse {
          final Driver_DriverFragment getDriverById;
          
          GetDriversResponse({required this.getDriverById});
          
          factory GetDriversResponse.fromJson(Map<String, dynamic> json) => _$GetDriversResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$GetDriversResponseToJson(this);
      }
    

