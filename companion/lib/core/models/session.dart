import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
class Session with _$Session {
  const factory Session({
    required String id,
    required String name,
    required String nodeId,
    required int startedAt,
    int? endedAt,
    @Default(0) int enginesActive,
    @Default(0) int detectionCount,
    @Default(0) int uniqueMacCount,
    @Default(0.0) double distanceKm,
    @Default(false) bool exported,
    @Default(false) bool isWardrive,
  }) = _Session;

  factory Session.fromJson(Map<String, dynamic> json) =>
      _$SessionFromJson(json);
}

/// Live session statistics displayed during wardrive.
class SessionStats {
  const SessionStats({
    required this.duration,
    required this.distanceKm,
    required this.speedKmh,
    required this.totalDetections,
    required this.uniqueMacs,
    required this.newMacs,
    required this.wifiDetections,
    required this.bleDetections,
    required this.flockCount,
    required this.droneCount,
    required this.detectionsPerKm,
    required this.gpsAccuracy,
    required this.satelliteCount,
  });

  final Duration duration;
  final double distanceKm;
  final double speedKmh;
  final int totalDetections;
  final int uniqueMacs;
  final int newMacs;
  final int wifiDetections;
  final int bleDetections;
  final int flockCount;
  final int droneCount;
  final double detectionsPerKm;
  final double gpsAccuracy;
  final int satelliteCount;
}
