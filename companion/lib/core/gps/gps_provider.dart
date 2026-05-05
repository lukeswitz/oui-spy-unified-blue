import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GpsProvider {
  GpsProvider(this._bleManager) {
    _restoreLastPosition();
  }

  final BleManager _bleManager;

  StreamSubscription<Position>? _positionSub;
  Timer? _pushTimer;
  GpsPosition? _lastPosition;
  final _positionController = StreamController<GpsPosition>.broadcast();

  Stream<GpsPosition> get positionStream => _positionController.stream;
  GpsPosition? get lastPosition => _lastPosition;

  Future<void> _restoreLastPosition() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('gps_last_lat');
    final lon = p.getDouble('gps_last_lon');
    if (lat != null && lon != null && _lastPosition == null) {
      _lastPosition = GpsPosition(
        latitude: lat,
        longitude: lon,
        altitude: p.getDouble('gps_last_alt') ?? 0,
        speed: 0,
        heading: 0,
        accuracy: p.getDouble('gps_last_acc') ?? 50,
        satelliteCount: 0,
        timestamp: DateTime.now(),
      );
      DebugLog.log('GPS: restored last position $lat, $lon');
    }
  }

  Future<void> _persistPosition(double lat, double lon, double alt, double acc) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('gps_last_lat', lat);
    await p.setDouble('gps_last_lon', lon);
    await p.setDouble('gps_last_alt', alt);
    await p.setDouble('gps_last_acc', acc);
  }

  bool _hasAlwaysPermission = false;
  bool get hasAlwaysPermission => _hasAlwaysPermission;

  Future<bool> start() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        DebugLog.log('GPS: permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      DebugLog.log('GPS: permission denied forever');
      return false;
    }

    _hasAlwaysPermission = permission == LocationPermission.always;

    if (permission == LocationPermission.whileInUse) {
      DebugLog.log('GPS: have whenInUse, requesting always');
      if (Platform.isAndroid) {
        await Geolocator.openAppSettings();
      } else {
        final upgraded = await Geolocator.requestPermission();
        _hasAlwaysPermission = upgraded == LocationPermission.always;
      }
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _platformSettings(),
    ).listen(_onPosition);

    _pushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pushToDevice();
    });

    DebugLog.log('GPS: started (always=$_hasAlwaysPermission)');
    return true;
  }

  LocationSettings _platformSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'OUI-SPY Active',
          notificationText: 'GPS tracking for wardrive session',
          enableWakeLock: true,
        ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _pushTimer?.cancel();
    _pushTimer = null;
  }

  void dispose() {
    stop();
    _positionController.close();
  }

  void _onPosition(Position pos) {
    _lastPosition = GpsPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
      accuracy: pos.accuracy,
      satelliteCount: pos.isMocked ? 0 : -1,
      timestamp: pos.timestamp,
    );
    _positionController.add(_lastPosition!);
    _persistPosition(pos.latitude, pos.longitude, pos.altitude, pos.accuracy);
    _bleManager.updateGps(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
    );
  }

  Future<void> _pushToDevice() async {
    final pos = _lastPosition;
    if (pos == null || !_bleManager.isConnected) return;

    await _bleManager.pushGps(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
      accuracy: pos.accuracy,
      satelliteCount: pos.satelliteCount > 0 ? pos.satelliteCount : 0,
    );
  }
}

final gpsProvider = Provider<GpsProvider>((ref) {
  final ble = ref.watch(bleManagerProvider);
  final gps = GpsProvider(ble);
  ref.onDispose(gps.dispose);
  return gps;
});
