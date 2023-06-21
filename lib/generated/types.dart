 import 'package:json_annotation/json_annotation.dart';
 import 'enums.dart';
  part 'types.g.dart';

@JsonSerializable()
      class HemodialysisGroup_designation_id {
          final String? designation;
          final String id;
          
          HemodialysisGroup_designation_id({required this.designation, required this.id});
          
          factory HemodialysisGroup_designation_id.fromJson(Map<String, dynamic> json) => _$HemodialysisGroup_designation_idFromJson(json);
          
          Map<String, dynamic> toJson() => _$HemodialysisGroup_designation_idToJson(this);
      }
    
@JsonSerializable()
      class Position_startTime {
          final int? startTime;
          
          Position_startTime({required this.startTime});
          
          factory Position_startTime.fromJson(Map<String, dynamic> json) => _$Position_startTimeFromJson(json);
          
          Map<String, dynamic> toJson() => _$Position_startTimeToJson(this);
      }
    
@JsonSerializable()
      class HemodialysisGroup_id {
          final String id;
          
          HemodialysisGroup_id({required this.id});
          
          factory HemodialysisGroup_id.fromJson(Map<String, dynamic> json) => _$HemodialysisGroup_idFromJson(json);
          
          Map<String, dynamic> toJson() => _$HemodialysisGroup_idToJson(this);
      }
    

@JsonSerializable()
      class HemodialysisGroupListResponse {
          final List<HemodialysisGroup_designation_id> hemodialysisGroupList;
          
          HemodialysisGroupListResponse({required this.hemodialysisGroupList});
          
          factory HemodialysisGroupListResponse.fromJson(Map<String, dynamic> json) => _$HemodialysisGroupListResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$HemodialysisGroupListResponseToJson(this);
      }
    
@JsonSerializable()
      class SavePositionResponse {
          final Position_startTime savePosition;
          final HemodialysisGroup_id saveHemodialysisGroup;
          
          SavePositionResponse({required this.savePosition, required this.saveHemodialysisGroup});
          
          factory SavePositionResponse.fromJson(Map<String, dynamic> json) => _$SavePositionResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$SavePositionResponseToJson(this);
      }
      

