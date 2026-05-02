// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'node.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NodeImpl _$$NodeImplFromJson(Map<String, dynamic> json) => _$NodeImpl(
  id: json['id'] as String,
  name: json['name'] as String,
  macAddress: json['macAddress'] as String,
  firmwareVersion: json['firmwareVersion'] as String?,
  lastSeen: (json['lastSeen'] as num?)?.toInt(),
  configJson: json['configJson'] as String?,
  configHash: json['configHash'] as String?,
  createdAt: (json['createdAt'] as num).toInt(),
);

Map<String, dynamic> _$$NodeImplToJson(_$NodeImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'macAddress': instance.macAddress,
      'firmwareVersion': instance.firmwareVersion,
      'lastSeen': instance.lastSeen,
      'configJson': instance.configJson,
      'configHash': instance.configHash,
      'createdAt': instance.createdAt,
    };
