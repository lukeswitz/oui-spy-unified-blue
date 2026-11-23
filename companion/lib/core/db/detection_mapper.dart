import 'package:drift/drift.dart' as drift;
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

DetectionsCompanion detectionCompanion(Detection detection, String sessionId) => DetectionsCompanion(
      sessionId: drift.Value(sessionId),
      nodeId: const drift.Value('default'),
      macAddress: drift.Value(detection.macAddress),
      deviceName: drift.Value(detection.deviceName),
      engine: drift.Value(detection.engine.name),
      detectionMethod: drift.Value(detection.method),
      rssi: drift.Value(detection.rssi),
      channel: drift.Value(detection.channel),
      deviceTimestampMs: drift.Value(detection.deviceTimestampMs),
      appTimestamp: drift.Value(detection.appTimestamp.millisecondsSinceEpoch),
      latitude: drift.Value(detection.latitude),
      longitude: drift.Value(detection.longitude),
      accuracy: drift.Value(detection.accuracy),
      altitude: drift.Value(detection.altitude),
      speed: drift.Value(detection.speed),
      heading: drift.Value(detection.heading),
      satelliteCount: drift.Value(detection.satelliteCount),
      ssid: drift.Value(detection.ssid),
      authMode: drift.Value(detection.wardrive?.authMode ?? 0),
      uavId: drift.Value(detection.odid?.uavId),
      operatorId: drift.Value(detection.odid?.operatorId),
      droneLat: drift.Value(detection.odid?.droneLat),
      droneLon: drift.Value(detection.odid?.droneLon),
      altitudeMsl: drift.Value(detection.odid?.altitudeMsl),
      heightAgl: drift.Value(detection.odid?.heightAgl),
      droneSpeed: drift.Value(detection.odid?.droneSpeed),
      droneHeading: drift.Value(detection.odid?.droneHeading),
      pilotLat: drift.Value(detection.odid?.pilotLat),
      pilotLon: drift.Value(detection.odid?.pilotLon),
      isRaven: drift.Value(detection.flock?.isRaven),
      ravenFirmware: drift.Value(detection.flock?.ravenFirmware),
      flockSignals: drift.Value(detection.flock?.signals),
      count: drift.Value(detection.count),
      approxGps: drift.Value(detection.approxGps),
      robotType: drift.Value(detection.unipwn?.robotType),
      exploited: drift.Value(detection.unipwn?.exploited),
      robotSerial: drift.Value(detection.unipwn?.serialNumber),
      filterDescription: drift.Value(detection.detector?.filterDescription),
      isFullMac: drift.Value(detection.detector?.isFullMac),
    );

Map<String, Object?> detectionExt(Detection d) {
  final o = d.odid;
  final x = d.detector;
  return {
    if (d.sourceNodeId.isNotEmpty) 'sourceNodeId': d.sourceNodeId,
    if (x != null) 'detectorConfidence': x.confidence,
    if (o != null) ...{
      'odidSelfId': o.selfId,
      'odidAltitudeBaro': o.altitudeBaro,
      'odidVertSpeed': o.vertSpeed,
      'odidOperatorAlt': o.operatorAlt,
      'odidAreaCount': o.areaCount,
      'odidAreaRadius': o.areaRadius,
      'odidAreaCeiling': o.areaCeiling,
      'odidAreaFloor': o.areaFloor,
      'odidLocTimestamp': o.locTimestamp,
      'odidUaType': o.uaType,
      'odidIdType': o.idType,
      'odidOpIdType': o.opIdType,
      'odidOpLocationType': o.opLocationType,
      'odidClassification': o.classification,
      'odidCategoryEu': o.categoryEu,
      'odidClassEu': o.classEu,
      'odidHeightType': o.heightType,
      'odidStatus': o.status,
      'odidHorizAcc': o.horizAcc,
      'odidVertAcc': o.vertAcc,
      'odidBaroAcc': o.baroAcc,
      'odidSpeedAcc': o.speedAcc,
      'odidSelfIdType': o.selfIdType,
    },
  };
}

/// Maps a raw `detections` row map onto the app-side [Detection] model.
Detection detectionFromDbRow(Map<String, dynamic> row) {
  final engineName = row['engine'] as String;
  final engine = Engine.values.firstWhere(
    (e) => e.name == engineName,
    orElse: () => Engine.wardrive,
  );

  final ssid = (row['ssid'] as String?) ?? '';
  final authMode = (row['authMode'] as int?) ?? 0;
  final deviceName = (row['deviceName'] as String?) ?? '';
  final ext = (row['ext'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  final d = Detection(
    id: '${row['id']}',
    sessionId: row['sessionId'] as String,
    nodeId: row['nodeId'] as String,
    macAddress: row['macAddress'] as String,
    deviceName: deviceName,
    engine: engine,
    method: row['detectionMethod'] as String,
    rssi: row['rssi'] as int,
    channel: row['channel'] as int,
    deviceTimestampMs: row['deviceTimestampMs'] as int,
    appTimestamp: DateTime.fromMillisecondsSinceEpoch(row['appTimestamp'] as int),
    ssid: ssid,
    count: (row['count'] as int?) ?? 1,
    sourceNodeId: (ext['sourceNodeId'] as String?) ?? '',
    latitude: row['latitude'] as double?,
    longitude: row['longitude'] as double?,
    altitude: row['altitude'] as double?,
    speed: row['speed'] as double?,
    heading: row['heading'] as double?,
    accuracy: row['accuracy'] as double?,
    satelliteCount: row['satelliteCount'] as int?,
    approxGps: (row['approxGps'] as bool?) ?? false,
    wardrive: engine == Engine.wardrive
        ? WardriveExtension(ssid: ssid, authMode: authMode, deviceName: deviceName)
        : null,
    flock: (engine == Engine.flockBle || engine == Engine.flockWifi)
        ? FlockExtension(
            isRaven: (row['isRaven'] as bool?) ?? false,
            ravenFirmware: row['ravenFirmware'] as String?,
            signals: (row['flockSignals'] as int?) ?? 0,
          )
        : null,
    odid: engine == Engine.skySpy
        ? OdidExtension(
            uavId: row['uavId'] as String?,
            operatorId: row['operatorId'] as String?,
            droneLat: row['droneLat'] as double?,
            droneLon: row['droneLon'] as double?,
            altitudeMsl: row['altitudeMsl'] as int?,
            heightAgl: row['heightAgl'] as int?,
            droneSpeed: row['droneSpeed'] as int?,
            droneHeading: row['droneHeading'] as int?,
            pilotLat: row['pilotLat'] as double?,
            pilotLon: row['pilotLon'] as double?,
            selfId: ext['odidSelfId'] as String?,
            altitudeBaro: ext['odidAltitudeBaro'] as int?,
            vertSpeed: ext['odidVertSpeed'] as int?,
            operatorAlt: ext['odidOperatorAlt'] as int?,
            areaCount: ext['odidAreaCount'] as int?,
            areaRadius: ext['odidAreaRadius'] as int?,
            areaCeiling: ext['odidAreaCeiling'] as int?,
            areaFloor: ext['odidAreaFloor'] as int?,
            locTimestamp: ext['odidLocTimestamp'] as int?,
            uaType: ext['odidUaType'] as int?,
            idType: ext['odidIdType'] as int?,
            opIdType: ext['odidOpIdType'] as int?,
            opLocationType: ext['odidOpLocationType'] as int?,
            classification: ext['odidClassification'] as int?,
            categoryEu: ext['odidCategoryEu'] as int?,
            classEu: ext['odidClassEu'] as int?,
            heightType: ext['odidHeightType'] as int?,
            status: ext['odidStatus'] as int?,
            horizAcc: ext['odidHorizAcc'] as int?,
            vertAcc: ext['odidVertAcc'] as int?,
            baroAcc: ext['odidBaroAcc'] as int?,
            speedAcc: ext['odidSpeedAcc'] as int?,
            selfIdType: ext['odidSelfIdType'] as int?,
          )
        : null,
    unipwn: engine == Engine.uniPwn
        ? UnipwnExtension(
            robotType: (row['robotType'] as String?) ?? '',
            exploited: (row['exploited'] as bool?) ?? false,
            serialNumber: row['robotSerial'] as String?,
          )
        : null,
    detector: engine == Engine.detector
        ? DetectorExtension(
            filterDescription: row['filterDescription'] as String?,
            isFullMac: (row['isFullMac'] as bool?) ?? false,
            confidence: (ext['detectorConfidence'] as int?) ?? 0,
          )
        : null,
  );
  final cls = row['alertClass'];
  if (cls is String && cls.isNotEmpty) detectionAlertClass[d] = cls;
  return d;
}
