/// Phone GPS position with all relevant fields.
class GpsPosition {
  const GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.satelliteCount,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final double speed; // m/s
  final double heading; // degrees
  final double accuracy; // meters
  final int satelliteCount;
  final DateTime timestamp;

  double get speedKmh => speed * 3.6;
  double get speedMph => speed * 2.237;

  GpsQuality get quality {
    if (accuracy <= 0) return GpsQuality.none;
    if (accuracy <= 10) return GpsQuality.good;
    if (accuracy <= 50) return GpsQuality.fair;
    return GpsQuality.poor;
  }

  /// Linear interpolation between two GPS positions.
  static GpsPosition lerp(GpsPosition a, GpsPosition b, double t) {
    return GpsPosition(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t,
      altitude: a.altitude + (b.altitude - a.altitude) * t,
      speed: a.speed + (b.speed - a.speed) * t,
      heading: a.heading + (b.heading - a.heading) * t,
      accuracy: a.accuracy + (b.accuracy - a.accuracy) * t,
      satelliteCount: t < 0.5 ? a.satelliteCount : b.satelliteCount,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (a.timestamp.millisecondsSinceEpoch +
                (b.timestamp.millisecondsSinceEpoch -
                        a.timestamp.millisecondsSinceEpoch) *
                    t)
            .round(),
      ),
    );
  }
}

enum GpsQuality { good, fair, poor, none }
