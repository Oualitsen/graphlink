// GENERATED CODE - DO NOT MODIFY BY HAND.

// ignore_for_file: camel_case_types, constant_identifier_names, unused_import, non_constant_identifier_names

  import 'package:json_annotation/json_annotation.dart';
  import 'enums.gq.dart';
  part 'inputs.gq.g.dart';

    @JsonSerializable(explicitToJson: true)
      class PageInfo {
          final int index;
          final int size;
          
          PageInfo({required this.index, required this.size});
          
          factory PageInfo.fromJson(Map<String, dynamic> json) => _$PageInfoFromJson(json);
          
          Map<String, dynamic> toJson() => _$PageInfoToJson(this);
      }

