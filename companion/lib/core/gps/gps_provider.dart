import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_types.dart';

/// Provides continuous phone GPS and pushes to BLE device.
class GpsProvider {
  GpsProvider(this._bleManager);

  final BleManager _bleManager;

  StreamSubscription<Position>? _positionSub;
  Timer? _pushTimer;
  GpsPosition? _lastPosition;
  final _positionController = StreamController<GpsPosition>.broadcast();

  Stream<GpsPosition> get positionStream => _positionController.stream;
  GpsPosition? get lastPosition => _lastPosition;

  /// Start GPS tracking and BLE push.
  Future<bool> start() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      if (result == LocationPermission.denied ||
          result == LocationPermission.deniedForever) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) return false;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(_onPosition);

    // Push GPS to device every 2 seconds
    _pushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pushToDevice();
    });

    return true;
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
      satelliteCount: pos.isMocked ? 0 : -1, // Platform doesn't expose sat count
      timestamp: pos.timestamp,
    );
    _positionController.add(_lastPosition!);
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
