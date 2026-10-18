import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

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
          )
        : null,
  );
  final cls = row['alertClass'];
  if (cls is String && cls.isNotEmpty) detectionAlertClass[d] = cls;
  return d;
}
