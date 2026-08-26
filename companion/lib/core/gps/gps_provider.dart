import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GpsProvider {
  GpsProvider(this._bleManager, this._geofenceFilter) {
    _restoreLastPosition();
    _restoreSource();
  }

  final BleManager _bleManager;
  final GeofenceFilter _geofenceFilter;

  /// UI callback to show a message (toast/snackbar). Set by screen layer.
  void Function(String message)? onMessage;

  StreamSubscription<Position>? _positionSub;
  Timer? _pushTimer;
  Timer? _hwPollTimer;
  GpsPosition? _lastPosition;
  GpsPosition? _phonePosition;
  final _positionController = StreamController<GpsPosition>.broadcast();

  Stream<GpsPosition> get positionStream => _positionController.stream;
  GpsPosition? get lastPosition => _lastPosition;

  final _hwGpsController = StreamController<HwGpsState>.broadcast();
  GpsSource _source = GpsSource.phone;
  HwGpsState _hwGps = const HwGpsState(
      active: false, satellites: 0, source: GpsSource.phone, inUse: false);

  /// On-board GPS module state and which source the app is actually recording.
  Stream<HwGpsState> get hwGpsStream => _hwGpsController.stream;
  HwGpsState get hwGps => _hwGps;
  GpsSource get source => _source;

  /// True when the app is stamping detections with the device's own GPS fix.
  bool get usingHardware => _source == GpsSource.hardware && _hwActive;

  /// Hardware is selected but has no fix, so the phone is standing in.
  bool get isFallingBack => _source == GpsSource.hardware && !_hwActive;

  Future<void> _restoreSource() async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString('gps_source');
    for (final s in GpsSource.values) {
      if (s.name == name) _source = s;
    }
    if (_running && _source == GpsSource.hardware) _startHwPoll();
    _publishHwState();
  }

  Future<void> setSource(GpsSource s) async {
    if (s == _source) return;
    _source = s;
    final p = await SharedPreferences.getInstance();
    await p.setString('gps_source', s.name);
    DebugLog.log('GPS: source=${s.name}');

    if (s == GpsSource.hardware) {
      if (_running) _startHwPoll();
      await _readHwGps();
      return;
    }

    _stopHwPoll();
    _hwActive = false;
    _publishHwState();
    if (_phonePosition != null) _publish(_phonePosition!);
  }

  /// One-shot read so a screen can show the module's state without polling.
  Future<void> refreshHwGps() => _readHwGps();

  Future<void> _restoreLastPosition() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('gps_last_lat');
    final lon = p.getDouble('gps_last_lon');
    
    if (lat != null && lon != null && 
        lat.isFinite && lon.isFinite && 
        _lastPosition == null) {
      final alt = p.getDouble('gps_last_alt') ?? 0;
      final acc = p.getDouble('gps_last_acc') ?? 50;
      
      if (alt.isFinite && acc.isFinite && acc > 0 && acc < 10000) {
        _lastPosition = GpsPosition(
          latitude: lat,
          longitude: lon,
          altitude: alt,
          speed: 0,
          heading: 0,
          accuracy: acc,
          satelliteCount: 0,
          timestamp: DateTime.now(),
        );
        DebugLog.log('GPS: restored last position');
      }
    }
  }

  Future<void> _persistPosition(double lat, double lon, double alt, double acc) async {
    if (!lat.isFinite || !lon.isFinite || !alt.isFinite || !acc.isFinite) {
      DebugLog.log('GPS: rejecting invalid position for persistence');
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setDouble('gps_last_lat', lat);
    await p.setDouble('gps_last_lon', lon);
    await p.setDouble('gps_last_alt', alt);
    await p.setDouble('gps_last_acc', acc);
  }

  bool _hasAlwaysPermission = false;
  bool _running = false;
  bool get hasAlwaysPermission => _hasAlwaysPermission;

  Future<bool> start() async {
    _running = true;
    if (_source == GpsSource.hardware) _startHwPoll();
    if (!await Geolocator.isLocationServiceEnabled()) {
      DebugLog.log('GPS: location services disabled');
      return false;
    }

    // Foreground permission via Geolocator (non-blocking native dialog on both platforms).
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
    DebugLog.log('GPS: foreground permission=$permission');

    // Start stream — whileInUse is enough for foreground GPS
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _platformSettings(),
    ).listen(_onPosition, onError: (e) {
      DebugLog.log('GPS: stream error $e');
    });

    _pushTimer?.cancel();
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
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'OUI-SPY Wardriving',
          notificationText: 'Tracking location for detections',
          notificationChannelName: 'Wardrive Location',
          enableWakeLock: true,
          setOngoing: true,
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
    _running = false;
    _positionSub?.cancel();
    _positionSub = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    _stopHwPoll();
  }

  void dispose() {
    stop();
    _positionController.close();
    _hwGpsController.close();
  }

  void _onPosition(Position pos) {
    _phonePosition = GpsPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
      accuracy: pos.accuracy,
      satelliteCount: pos.isMocked ? 0 : -1,
      timestamp: pos.timestamp,
    );
    if (!usingHardware) _publish(_phonePosition!);
  }

  void _publish(GpsPosition p) {
    _lastPosition = p;
    _positionController.add(p);
    _persistPosition(p.latitude, p.longitude, p.altitude, p.accuracy);
    _bleManager.updateGps(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      satelliteCount: p.satelliteCount > 0 ? p.satelliteCount : null,
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
      suppressAlerts: _geofenceFilter.isExcluded(pos.latitude, pos.longitude),
    );
  }

  void _startHwPoll() {
    if (_hwPollTimer != null) return;
    _hwPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _readHwGps();
    });
  }

  void _stopHwPoll() {
    _hwPollTimer?.cancel();
    _hwPollTimer = null;
  }

  Future<void> _readHwGps() async {
    final s = _bleManager.isConnected ? await _bleManager.readGpsStatus() : null;
    final wasUsingHardware = usingHardware;
    _hwActive = s?.hwActive ?? false;
    _hwSatellites = s?.satellites ?? 0;
    _publishHwState();

    if (usingHardware) {
      if (!wasUsingHardware) {
        DebugLog.log('GPS: on-board module has a fix — recording from hardware');
        onMessage?.call('On-board GPS has a fix — recording from the module');
      }
      _publish(GpsPosition(
        latitude: s!.latitude,
        longitude: s.longitude,
        altitude: s.altitude,
        speed: s.speed,
        heading: s.heading,
        accuracy: s.accuracy,
        satelliteCount: s.satellites,
        timestamp: DateTime.now(),
      ));
      return;
    }

    if (wasUsingHardware) {
      DebugLog.log('GPS: on-board module lost its fix — falling back to phone');
      onMessage?.call('On-board GPS lost its fix — using phone location');
      if (_phonePosition != null) _publish(_phonePosition!);
    }
  }

  bool _hwActive = false;
  int _hwSatellites = 0;

  void _publishHwState() {
    final s = HwGpsState(
      active: _hwActive,
      satellites: _hwSatellites,
      source: _source,
      inUse: usingHardware,
      fallback: isFallingBack,
    );
    if (s == _hwGps) return;
    _hwGps = s;
    if (!_hwGpsController.isClosed) _hwGpsController.add(s);
  }
}


class HwGpsState {
  const HwGpsState({
    required this.active,
    required this.satellites,
    required this.source,
    required this.inUse,
    this.fallback = false,
  });

  /// The device's on-board GPS module has a fix.
  final bool active;
  final int satellites;

  /// Source the user selected.
  final GpsSource source;

  /// The app is recording positions from the module, not the phone.
  final bool inUse;

  /// Hardware is selected but has no fix, so the phone is standing in.
  final bool fallback;

  @override
  bool operator ==(Object other) =>
      other is HwGpsState &&
      other.active == active &&
      other.satellites == satellites &&
      other.source == source &&
      other.inUse == inUse &&
      other.fallback == fallback;

  @override
  int get hashCode =>
      Object.hash(active, satellites, source, inUse, fallback);
}

enum GpsSource { phone, hardware }

final gpsProvider = Provider<GpsProvider>((ref) {
  final ble = ref.watch(bleManagerProvider);
  final geofence = ref.read(geofenceFilterProvider);
  final gps = GpsProvider(ble, geofence);
  ref.onDispose(gps.dispose);
  return gps;
});
