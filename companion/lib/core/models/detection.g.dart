// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DetectionImpl _$$DetectionImplFromJson(
  Map<String, dynamic> json,
) => _$DetectionImpl(
  id: json['id'] as String,
  sessionId: json['sessionId'] as String,
  nodeId: json['nodeId'] as String,
  macAddress: json['macAddress'] as String,
  engine: $enumDecode(_$EngineEnumMap, json['engine']),
  method: json['method'] as String,
  rssi: (json['rssi'] as num).toInt(),
  channel: (json['channel'] as num).toInt(),
  deviceTimestampMs: (json['deviceTimestampMs'] as num).toInt(),
  appTimestamp: DateTime.parse(json['appTimestamp'] as String),
  deviceName: json['deviceName'] as String? ?? '',
  ssid: json['ssid'] as String? ?? '',
  count: (json['count'] as num?)?.toInt() ?? 1,
  sourceNodeId: json['sourceNodeId'] as String? ?? '',
  latitude: (json['latitude'] as num?)?.toDouble(),
  longitude: (json['longitude'] as num?)?.toDouble(),
  altitude: (json['altitude'] as num?)?.toDouble(),
  speed: (json['speed'] as num?)?.toDouble(),
  heading: (json['heading'] as num?)?.toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
  satelliteCount: (json['satelliteCount'] as num?)?.toInt(),
  approxGps: json['approxGps'] as bool? ?? false,
  flock: json['flock'] == null
      ? null
      : FlockExtension.fromJson(json['flock'] as Map<String, dynamic>),
  odid: json['odid'] == null
      ? null
      : OdidExtension.fromJson(json['odid'] as Map<String, dynamic>),
  unipwn: json['unipwn'] == null
      ? null
      : UnipwnExtension.fromJson(json['unipwn'] as Map<String, dynamic>),
  detector: json['detector'] == null
      ? null
      : DetectorExtension.fromJson(json['detector'] as Map<String, dynamic>),
  wardrive: json['wardrive'] == null
      ? null
      : WardriveExtension.fromJson(json['wardrive'] as Map<String, dynamic>),
);

Map<String, dynamic> _$$DetectionImplToJson(_$DetectionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sessionId': instance.sessionId,
      'nodeId': instance.nodeId,
      'macAddress': instance.macAddress,
      'engine': _$EngineEnumMap[instance.engine]!,
      'method': instance.method,
      'rssi': instance.rssi,
      'channel': instance.channel,
      'deviceTimestampMs': instance.deviceTimestampMs,
      'appTimestamp': instance.appTimestamp.toIso8601String(),
      'deviceName': instance.deviceName,
      'ssid': instance.ssid,
      'count': instance.count,
      'sourceNodeId': instance.sourceNodeId,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'altitude': instance.altitude,
      'speed': instance.speed,
      'heading': instance.heading,
      'accuracy': instance.accuracy,
      'satelliteCount': instance.satelliteCount,
      'approxGps': instance.approxGps,
      'flock': instance.flock,
      'odid': instance.odid,
      'unipwn': instance.unipwn,
      'detector': instance.detector,
      'wardrive': instance.wardrive,
    };

const _$EngineEnumMap = {
  Engine.detector: 'detector',
  Engine.flockBle: 'flockBle',
  Engine.flockWifi: 'flockWifi',
  Engine.foxhunter: 'foxhunter',
  Engine.skySpy: 'skySpy',
  Engine.uniPwn: 'uniPwn',
  Engine.wardrive: 'wardrive',
  Engine.pcap: 'pcap',
};

_$FlockExtensionImpl _$$FlockExtensionImplFromJson(Map<String, dynamic> json) =>
    _$FlockExtensionImpl(
      isRaven: json['isRaven'] as bool? ?? false,
      ravenFirmware: json['ravenFirmware'] as String?,
    );

Map<String, dynamic> _$$FlockExtensionImplToJson(
  _$FlockExtensionImpl instance,
) => <String, dynamic>{
  'isRaven': instance.isRaven,
  'ravenFirmware': instance.ravenFirmware,
};

_$OdidExtensionImpl _$$OdidExtensionImplFromJson(Map<String, dynamic> json) =>
    _$OdidExtensionImpl(
      uavId: json['uavId'] as String?,
      operatorId: json['operatorId'] as String?,
      droneLat: (json['droneLat'] as num?)?.toDouble(),
      droneLon: (json['droneLon'] as num?)?.toDouble(),
      altitudeMsl: (json['altitudeMsl'] as num?)?.toInt(),
      heightAgl: (json['heightAgl'] as num?)?.toInt(),
      droneSpeed: (json['droneSpeed'] as num?)?.toInt(),
      droneHeading: (json['droneHeading'] as num?)?.toInt(),
      pilotLat: (json['pilotLat'] as num?)?.toDouble(),
      pilotLon: (json['pilotLon'] as num?)?.toDouble(),
      selfId: json['selfId'] as String?,
      altitudeBaro: (json['altitudeBaro'] as num?)?.toInt(),
      vertSpeed: (json['vertSpeed'] as num?)?.toInt(),
      operatorAlt: (json['operatorAlt'] as num?)?.toInt(),
      areaCount: (json['areaCount'] as num?)?.toInt(),
      areaRadius: (json['areaRadius'] as num?)?.toInt(),
      areaCeiling: (json['areaCeiling'] as num?)?.toInt(),
      areaFloor: (json['areaFloor'] as num?)?.toInt(),
      locTimestamp: (json['locTimestamp'] as num?)?.toInt(),
      uaType: (json['uaType'] as num?)?.toInt(),
      idType: (json['idType'] as num?)?.toInt(),
      opIdType: (json['opIdType'] as num?)?.toInt(),
      opLocationType: (json['opLocationType'] as num?)?.toInt(),
      classification: (json['classification'] as num?)?.toInt(),
      categoryEu: (json['categoryEu'] as num?)?.toInt(),
      classEu: (json['classEu'] as num?)?.toInt(),
      heightType: (json['heightType'] as num?)?.toInt(),
      status: (json['status'] as num?)?.toInt(),
      horizAcc: (json['horizAcc'] as num?)?.toInt(),
      vertAcc: (json['vertAcc'] as num?)?.toInt(),
      baroAcc: (json['baroAcc'] as num?)?.toInt(),
      speedAcc: (json['speedAcc'] as num?)?.toInt(),
      selfIdType: (json['selfIdType'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$OdidExtensionImplToJson(_$OdidExtensionImpl instance) =>
    <String, dynamic>{
      'uavId': instance.uavId,
      'operatorId': instance.operatorId,
      'droneLat': instance.droneLat,
      'droneLon': instance.droneLon,
      'altitudeMsl': instance.altitudeMsl,
      'heightAgl': instance.heightAgl,
      'droneSpeed': instance.droneSpeed,
      'droneHeading': instance.droneHeading,
      'pilotLat': instance.pilotLat,
      'pilotLon': instance.pilotLon,
      'selfId': instance.selfId,
      'altitudeBaro': instance.altitudeBaro,
      'vertSpeed': instance.vertSpeed,
      'operatorAlt': instance.operatorAlt,
      'areaCount': instance.areaCount,
      'areaRadius': instance.areaRadius,
      'areaCeiling': instance.areaCeiling,
      'areaFloor': instance.areaFloor,
      'locTimestamp': instance.locTimestamp,
      'uaType': instance.uaType,
      'idType': instance.idType,
      'opIdType': instance.opIdType,
      'opLocationType': instance.opLocationType,
      'classification': instance.classification,
      'categoryEu': instance.categoryEu,
      'classEu': instance.classEu,
      'heightType': instance.heightType,
      'status': instance.status,
      'horizAcc': instance.horizAcc,
      'vertAcc': instance.vertAcc,
      'baroAcc': instance.baroAcc,
      'speedAcc': instance.speedAcc,
      'selfIdType': instance.selfIdType,
    };

_$UnipwnExtensionImpl _$$UnipwnExtensionImplFromJson(
  Map<String, dynamic> json,
) => _$UnipwnExtensionImpl(
  robotType: json['robotType'] as String,
  exploited: json['exploited'] as bool? ?? false,
  serialNumber: json['serialNumber'] as String?,
);

Map<String, dynamic> _$$UnipwnExtensionImplToJson(
  _$UnipwnExtensionImpl instance,
) => <String, dynamic>{
  'robotType': instance.robotType,
  'exploited': instance.exploited,
  'serialNumber': instance.serialNumber,
};

_$WardriveExtensionImpl _$$WardriveExtensionImplFromJson(
  Map<String, dynamic> json,
) => _$WardriveExtensionImpl(
  ssid: json['ssid'] as String? ?? '',
  authMode: (json['authMode'] as num?)?.toInt() ?? 0,
  deviceName: json['deviceName'] as String? ?? '',
);

Map<String, dynamic> _$$WardriveExtensionImplToJson(
  _$WardriveExtensionImpl instance,
) => <String, dynamic>{
  'ssid': instance.ssid,
  'authMode': instance.authMode,
  'deviceName': instance.deviceName,
};

_$DetectorExtensionImpl _$$DetectorExtensionImplFromJson(
  Map<String, dynamic> json,
) => _$DetectorExtensionImpl(
  filterDescription: json['filterDescription'] as String?,
  isFullMac: json['isFullMac'] as bool? ?? false,
);

Map<String, dynamic> _$$DetectorExtensionImplToJson(
  _$DetectorExtensionImpl instance,
) => <String, dynamic>{
  'filterDescription': instance.filterDescription,
  'isFullMac': instance.isFullMac,
};
