import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:oui_spy/core/models/engine.dart';

part 'detection.freezed.dart';
part 'detection.g.dart';

@freezed
class Detection with _$Detection {
  const factory Detection({
    required String id,
    required String sessionId,
    required String nodeId,
    required String macAddress,
    required Engine engine,
    required String method,
    required int rssi,
    required int channel,
    required int deviceTimestampMs,
    required DateTime appTimestamp,
    @Default('') String deviceName,
    @Default('') String ssid,
    @Default(1) int count,
    @Default('') String sourceNodeId,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? heading,
    double? accuracy,
    int? satelliteCount,
    @Default(false) bool approxGps,
    FlockExtension? flock,
    OdidExtension? odid,
    UnipwnExtension? unipwn,
    DetectorExtension? detector,
    WardriveExtension? wardrive,
  }) = _Detection;

  factory Detection.fromJson(Map<String, dynamic> json) =>
      _$DetectionFromJson(json);
}

/// Bitmask of every Flock predicate that matched, mirroring FLOCK_SIG_* in
/// firmware protocol.h. A bare 10-digit name (serial) is not standalone
/// evidence; it only counts when the XUNTONG mfg ID corroborates it.
abstract class FlockSignal {
  static const int oui = 0x01;
  static const int name = 0x02;
  static const int serial = 0x04;
  static const int mfg = 0x08;
  static const int tn = 0x10;
  static const int ravenUuid = 0x20;

  static const int validated = serial | mfg | tn;
}

@freezed
class FlockExtension with _$FlockExtension {
  const factory FlockExtension({
    @Default(false) bool isRaven,
    String? ravenFirmware,
    @Default(0) int signals,
  }) = _FlockExtension;

  factory FlockExtension.fromJson(Map<String, dynamic> json) =>
      _$FlockExtensionFromJson(json);
}

enum FlockConfidence { verified, high, suspected }

extension FlockConfidenceX on FlockConfidence {
  String label(String method) => switch (this) {
    FlockConfidence.verified => 'Verified (XUNTONG Serial)',
    FlockConfidence.high => switch (method) {
      'wildcard_probe' => 'High (Flock Probe Captured)',
      'raven_uuid' => 'High (Raven UUID)',
      'name_match' => 'High (BLE Name)',
      _ => 'High',
    },
    FlockConfidence.suspected => 'Suspected (Known OUI)',
  };
}

extension FlockExtensionSignals on FlockExtension {
  bool hasSignal(int bit) => (signals & bit) != 0;

  /// Bare-serial name + XUNTONG mfg ID + TN serial all present.
  bool get isValidated =>
      (signals & FlockSignal.validated) == FlockSignal.validated;

  FlockConfidence confidence(String method) {
    if (isValidated) return FlockConfidence.verified;
    if (hasSignal(FlockSignal.ravenUuid)) return FlockConfidence.high;
    if (hasSignal(FlockSignal.name)) return FlockConfidence.high;
    if (method == 'wildcard_probe') return FlockConfidence.high;
    return FlockConfidence.suspected;
  }
}

@freezed
class OdidExtension with _$OdidExtension {
  const factory OdidExtension({
    String? uavId,
    String? operatorId,
    double? droneLat,
    double? droneLon,
    int? altitudeMsl,
    int? heightAgl,
    int? droneSpeed,
    int? droneHeading,
    double? pilotLat,
    double? pilotLon,
    String? selfId,
    int? altitudeBaro,
    int? vertSpeed,
    int? operatorAlt,
    int? areaCount,
    int? areaRadius,
    int? areaCeiling,
    int? areaFloor,
    int? locTimestamp,
    int? uaType,
    int? idType,
    int? opIdType,
    int? opLocationType,
    int? classification,
    int? categoryEu,
    int? classEu,
    int? heightType,
    int? status,
    int? horizAcc,
    int? vertAcc,
    int? baroAcc,
    int? speedAcc,
    int? selfIdType,
  }) = _OdidExtension;

  factory OdidExtension.fromJson(Map<String, dynamic> json) =>
      _$OdidExtensionFromJson(json);
}

@freezed
class UnipwnExtension with _$UnipwnExtension {
  const factory UnipwnExtension({
    required String robotType,
    @Default(false) bool exploited,
    String? serialNumber,
  }) = _UnipwnExtension;

  factory UnipwnExtension.fromJson(Map<String, dynamic> json) =>
      _$UnipwnExtensionFromJson(json);
}

@freezed
class WardriveExtension with _$WardriveExtension {
  const factory WardriveExtension({
    @Default('') String ssid,
    @Default(0) int authMode,
    @Default('') String deviceName,
  }) = _WardriveExtension;

  factory WardriveExtension.fromJson(Map<String, dynamic> json) =>
      _$WardriveExtensionFromJson(json);
}

@freezed
class DetectorExtension with _$DetectorExtension {
  const factory DetectorExtension({
    String? filterDescription,
    @Default(false) bool isFullMac,
  }) = _DetectorExtension;

  factory DetectorExtension.fromJson(Map<String, dynamic> json) =>
      _$DetectorExtensionFromJson(json);
}
