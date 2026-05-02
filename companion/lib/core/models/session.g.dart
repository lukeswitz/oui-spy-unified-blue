// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SessionImpl _$$SessionImplFromJson(Map<String, dynamic> json) =>
    _$SessionImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      nodeId: json['nodeId'] as String,
      startedAt: (json['startedAt'] as num).toInt(),
      endedAt: (json['endedAt'] as num?)?.toInt(),
      enginesActive: (json['enginesActive'] as num?)?.toInt() ?? 0,
      detectionCount: (json['detectionCount'] as num?)?.toInt() ?? 0,
      uniqueMacCount: (json['uniqueMacCount'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      exported: json['exported'] as bool? ?? false,
      isWardrive: json['isWardrive'] as bool? ?? false,
    );

Map<String, dynamic> _$$SessionImplToJson(_$SessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'nodeId': instance.nodeId,
      'startedAt': instance.startedAt,
      'endedAt': instance.endedAt,
      'enginesActive': instance.enginesActive,
      'detectionCount': instance.detectionCount,
      'uniqueMacCount': instance.uniqueMacCount,
      'distanceKm': instance.distanceKm,
      'exported': instance.exported,
      'isWardrive': instance.isWardrive,
    };
