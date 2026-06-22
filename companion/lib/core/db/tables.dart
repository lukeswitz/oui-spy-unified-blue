import 'package:drift/drift.dart';

class Nodes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get macAddress => text()();
  TextColumn get firmwareVersion => text().nullable()();
  IntColumn get lastSeen => integer().nullable()();
  TextColumn get configJson => text().nullable()();
  TextColumn get configHash => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nodeId => text().references(Nodes, #id)();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get enginesActive => integer().withDefault(const Constant(0))();
  IntColumn get detectionCount => integer().withDefault(const Constant(0))();
  IntColumn get uniqueMacCount => integer().withDefault(const Constant(0))();
  RealColumn get distanceKm =>
      real().withDefault(const Constant(0.0))();
  BoolColumn get exported =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isWardrive =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Detections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get nodeId => text().references(Nodes, #id)();
  TextColumn get macAddress => text()();
  TextColumn get deviceName => text().withDefault(const Constant(''))();
  TextColumn get engine => text()();
  TextColumn get detectionMethod => text()();
  IntColumn get rssi => integer()();
  IntColumn get channel => integer()();
  IntColumn get deviceTimestampMs => integer()();
  IntColumn get appTimestamp => integer()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get altitude => real().nullable()();
  RealColumn get speed => real().nullable()();
  RealColumn get heading => real().nullable()();
  RealColumn get accuracy => real().nullable()();
  IntColumn get satelliteCount => integer().nullable()();
  TextColumn get ssid => text().withDefault(const Constant(''))();
  IntColumn get authMode => integer().withDefault(const Constant(0))();
  IntColumn get count => integer().withDefault(const Constant(1))();
  // Flock extensions
  BoolColumn get isRaven => boolean().nullable()();
  TextColumn get ravenFirmware => text().nullable()();
  // ODID extensions
  TextColumn get uavId => text().nullable()();
  TextColumn get operatorId => text().nullable()();
  RealColumn get droneLat => real().nullable()();
  RealColumn get droneLon => real().nullable()();
  IntColumn get altitudeMsl => integer().nullable()();
  IntColumn get heightAgl => integer().nullable()();
  IntColumn get droneSpeed => integer().nullable()();
  IntColumn get droneHeading => integer().nullable()();
  RealColumn get pilotLat => real().nullable()();
  RealColumn get pilotLon => real().nullable()();
  // UniPwn extensions
  TextColumn get robotType => text().nullable()();
  BoolColumn get exploited => boolean().nullable()();
  TextColumn get robotSerial => text().nullable()();
  // Detector extensions
  TextColumn get filterDescription => text().nullable()();
  BoolColumn get isFullMac => boolean().nullable()();
  // GPS tagged from app's last-known position (captured while phone away)
  BoolColumn get approxGps => boolean().nullable()();
}

class EngineConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nodeId => text().references(Nodes, #id)();
  TextColumn get engine => text()();
  TextColumn get configJson => text()();
  IntColumn get updatedAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {nodeId, engine},
      ];
}

class Baselines extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get locationName => text().nullable()();
  RealColumn get centerLat => real()();
  RealColumn get centerLon => real()();
  RealColumn get radiusM => real()();
  TextColumn get polygonJson => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get detectionCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class BaselineDevices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get baselineId => text().references(Baselines, #id)();
  TextColumn get macAddress => text()();
  TextColumn get deviceName => text().withDefault(const Constant(''))();
  TextColumn get engine => text()();
  IntColumn get rssiAvg => integer().nullable()();
  IntColumn get firstSeen => integer()();
  TextColumn get fingerprintId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {baselineId, macAddress},
      ];
}

class Fingerprints extends Table {
  TextColumn get id => text()();
  TextColumn get primaryMac => text()();
  RealColumn get advIntervalMs => real().nullable()();
  IntColumn get txPower => integer().nullable()();
  TextColumn get serviceUuids => text().nullable()();
  TextColumn get mfgDataStructure => text().nullable()();
  TextColumn get rssiEnvelope => text().nullable()();
  RealColumn get probeIntervalMs => real().nullable()();
  TextColumn get ieOrder => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class FingerprintMacs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fingerprintId => text().references(Fingerprints, #id)();
  TextColumn get macAddress => text()();
  IntColumn get firstSeen => integer()();
  IntColumn get lastSeen => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {fingerprintId, macAddress},
      ];
}

class Geofences extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get zoneType => text()();
  RealColumn get centerLat => real().nullable()();
  RealColumn get centerLon => real().nullable()();
  RealColumn get radiusM => real().nullable()();
  TextColumn get polygonJson => text().nullable()();
  TextColumn get corridorJson => text().nullable()();
  BoolColumn get alertOnFlock =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get alertOnDrone =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get alertOnNew =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get alertOnStalking =>
      boolean().withDefault(const Constant(true))();
  TextColumn get alertMode =>
      text().withDefault(const Constant('push'))();
  BoolColumn get enabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get excludeFromWardrive =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class GeofenceAlerts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get geofenceId => text().references(Geofences, #id)();
  IntColumn get detectionId => integer().nullable()();
  TextColumn get alertType => text()();
  TextColumn get macAddress => text()();
  IntColumn get triggeredAt => integer()();
  BoolColumn get acknowledged =>
      boolean().withDefault(const Constant(false))();
}

class StalkingSuspects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get macAddress => text().unique()();
  IntColumn get sessionsSeen => integer()();
  IntColumn get locationsSeen => integer()();
  RealColumn get stalkingScore => real()();
  IntColumn get firstFlagged => integer()();
  IntColumn get lastSeen => integer()();
  TextColumn get status =>
      text().withDefault(const Constant('active'))();
  BoolColumn get whitelisted =>
      boolean().withDefault(const Constant(false))();
}

class WigleUploads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  IntColumn get uploadedAt => integer()();
  TextColumn get transactionId => text().nullable()();
  IntColumn get networksAccepted => integer().nullable()();
  IntColumn get networksNew => integer().nullable()();
  TextColumn get status => text()();
}
