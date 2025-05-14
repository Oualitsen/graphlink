// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inputs.gq.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PageInfo _$PageInfoFromJson(Map<String, dynamic> json) => PageInfo(
      index: (json['index'] as num).toInt(),
      size: (json['size'] as num).toInt(),
    );

Map<String, dynamic> _$PageInfoToJson(PageInfo instance) => <String, dynamic>{
      'index': instance.index,
      'size': instance.size,
    };

TestInput _$TestInputFromJson(Map<String, dynamic> json) => TestInput(
      name: json['name'] as String,
      midName: json['midName'] as String?,
    );

Map<String, dynamic> _$TestInputToJson(TestInput instance) => <String, dynamic>{
      'name': instance.name,
      'midName': instance.midName,
    };
