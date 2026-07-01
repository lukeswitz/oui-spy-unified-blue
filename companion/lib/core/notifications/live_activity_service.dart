import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';

class LiveActivityService {
  LiveActivityService();

  static const _channel = MethodChannel('tech.colonelpanic.ouispy/live_activity');

  bool _supported = false;
  bool get supported => _supported;

  String? _activityId;
  Future<String?>? _startInFlight;
  bool get isActive => _activityId != null;

  /// Check if Live Activities are supported on this device.
  Future<void> init() async {
    if (!Platform.isIOS) {
      _supported = false;
      return;
    }

    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      DebugLog.log('LIVE_ACTIVITY: supported=$_supported');
    } on MissingPluginException {
      _supported = false;
      DebugLog.log('LIVE_ACTIVITY: plugin not available (Widget Extension not configured)');
    } catch (e) {
      _supported = false;
      DebugLog.log('LIVE_ACTIVITY: init error: $e');
    }
  }

  Future<void> update({
    required String primaryMode,
    String activeLabel = '',
    required int uniqueCount,
    int flockCount = 0,
    int droneCount = 0,
    int detectorHits = 0,
    double distanceKm = 0,
    double speedKmh = 0,
    String targetMac = '',
    int rssi = -100,
    int intervalMs = 0,
    String robotType = '',
    String exploitStatus = '',
    bool isImperial = false,
  }) async {
    if (!_supported) return;

    final payload = <String, Object?>{
      'mode': primaryMode,
      'activeLabel': activeLabel,
      'uniqueCount': uniqueCount,
      'flockCount': flockCount,
      'droneCount': droneCount,
      'detectorHits': detectorHits,
      'distanceKm': distanceKm,
      'speedKmh': speedKmh,
      'targetMac': targetMac,
      'rssi': rssi,
      'intervalMs': intervalMs,
      'robotType': robotType,
      'exploitStatus': exploitStatus,
      'isImperial': isImperial,
    };

    try {
      if (_activityId != null) {
        payload['activityId'] = _activityId;
        await _channel.invokeMethod('updateActivity', payload);
        return;
      }
      if (_startInFlight != null) {
        final id = await _startInFlight!;
        if (id != null) {
          final upd = Map<String, Object?>.from(payload);
          upd['activityId'] = id;
          await _channel.invokeMethod('updateActivity', upd);
        }
        return;
      }
      _startInFlight = _channel.invokeMethod<String>('startActivity', payload);
      try {
        _activityId = await _startInFlight!;
        DebugLog.log('LIVE_ACTIVITY: started activity=$_activityId mode=$primaryMode');
      } finally {
        _startInFlight = null;
      }
    } catch (e) {
      _startInFlight = null;
      DebugLog.log('LIVE_ACTIVITY: update error: $e');
    }
  }

  /// End the current Live Activity.
  Future<void> end() async {
    if (!_supported || _activityId == null) return;

    try {
      await _channel.invokeMethod('endActivity', {
        'activityId': _activityId,
      });
      DebugLog.log('LIVE_ACTIVITY: ended activity=$_activityId');
      _activityId = null;
    } catch (e) {
      DebugLog.log('LIVE_ACTIVITY: end error: $e');
    }
  }

  Future<void> endAll() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('endAllActivities');
      DebugLog.log('LIVE_ACTIVITY: endAll');
      _activityId = null;
    } on MissingPluginException {
      // legacy handler / unsupported iOS — fall back to single-end
      await end();
    } catch (e) {
      DebugLog.log('LIVE_ACTIVITY: endAll error: $e');
    }
  }

  static String resolvePrimaryMode(Set<String> activeEngines, {String? foxhuntTarget}) {
    final hasWardrive = activeEngines.contains('wardrive');
    final hasFlockBle = activeEngines.contains('flockBle');
    final hasFlockWifi = activeEngines.contains('flockWifi');
    final hasFlock = hasFlockBle || hasFlockWifi;

    if (foxhuntTarget != null && activeEngines.contains('foxhunter')) return 'foxhunter';
    if (hasWardrive && hasFlock) return 'wardriveFlock';
    if (hasWardrive) return 'wardrive';
    if (hasFlockBle && hasFlockWifi) return 'flockDual';
    if (hasFlockBle) return 'flockBle';
    if (hasFlockWifi) return 'flockWifi';
    if (activeEngines.contains('skySpy')) return 'skySpy';
    if (activeEngines.contains('detector')) return 'detector';
    if (activeEngines.contains('uniPwn')) return 'uniPwn';
    return 'wardrive';
  }
}

final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  return LiveActivityService();
});
