import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';

/// iOS Live Activity / Dynamic Island integration.
///
/// Shows a compact live indicator in the Dynamic Island (iPhone 14 Pro+)
/// or Lock Screen Live Activity on older devices.
///
/// Engine priority for primary icon (highest wins):
///   wardrive > foxhunter > flockBle/flockWifi > skySpy > detector > uniPwn
///
/// Combined counts from ALL active engines shown in expanded view regardless
/// of which engine is primary for the icon.
///
/// Requires iOS 16.1+ Widget Extension target (OuiSpyLiveActivity).
/// Falls back gracefully to no-op on unsupported platforms.
class LiveActivityService {
  LiveActivityService();

  static const _channel = MethodChannel('tech.colonelpanic.ouispy/live_activity');

  bool _supported = false;
  bool get supported => _supported;

  String? _activityId;
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

  /// Start or update the Live Activity with combined engine state.
  ///
  /// [primaryMode] is the engine that gets the icon/label (determined by
  /// priority: wardrive > foxhunter > flock > skySpy > detector > uniPwn).
  ///
  /// All count fields represent the combined totals across ALL active engines.
  Future<void> update({
    required String primaryMode,
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
      if (_activityId == null) {
        _activityId = await _channel.invokeMethod<String>('startActivity', payload);
        DebugLog.log('LIVE_ACTIVITY: started activity=$_activityId mode=$primaryMode');
      } else {
        payload['activityId'] = _activityId;
        await _channel.invokeMethod('updateActivity', payload);
      }
    } catch (e) {
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

  /// Determine primary display mode from set of active engines.
  ///
  /// Combinations collapse to dedicated modes so the title reflects every
  /// active radio path:
  ///   wardrive + flock*       → wardriveFlock (WIGLE+FLOCK)
  ///   flockBle + flockWifi    → flockDual     (FLOCK WiFi+BLE)
  ///
  /// Priority for singletons:
  ///   foxhunter(with target) > wardriveFlock > wardrive > flockDual >
  ///   flockBle > flockWifi > skySpy > detector > uniPwn
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
