import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/notifications/notification_service.dart' show NotifChannel;

class LiveActivityService {
  LiveActivityService();

  static const _channel = MethodChannel('tech.colonelpanic.ouispy/live_activity');

  bool _supported = false;
  bool get supported => _supported;

  String? _activityId;
  String? _mode;
  Future<String?>? _startInFlight;
  bool _android = false;
  bool _androidShown = false;
  Timer? _androidPostTimer;
  DateTime _androidLastPost = DateTime.fromMillisecondsSinceEpoch(0);
  static const _androidStatusId = 0x0A11;
  bool get isActive => _activityId != null || _startInFlight != null || _androidShown;

  /// Mode the visible activity was started with — identifies its owner.
  String? get activeMode => _mode;

  /// Check if Live Activities are supported on this device.
  Future<void> init() async {
    if (Platform.isAndroid) {
      _android = true;
      return;
    }
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

  String _lastAlert = '';
  String _lastAlertDetail = '';
  double _lastAlertAt = 0;
  Map<String, Object?>? _lastPayload;
  final Map<String, Set<String>> _alertMacs = {};

  Map<String, int> get alertKinds =>
      {for (final e in _alertMacs.entries) e.key: e.value.length};

  String _lastAlertKind = '';

  bool get canAlert => _supported && _activityId != null && _lastPayload != null;

  Future<void> showAlert(String title, String detail, [String? kind, String? mac, bool alert = false]) async {
    _lastAlert = title;
    _lastAlertDetail = detail;
    _lastAlertKind = kind ?? '';
    _lastAlertAt = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (kind != null && mac != null && mac.isNotEmpty) {
      final m = mac.toUpperCase();
      if (!_alertMacs.values.any((s) => s.contains(m))) (_alertMacs[kind] ??= {}).add(m);
    }
    if (_android) {
      final last = _lastPayload;
      if (!_androidShown || last == null) return;
      _lastPayload = {
        ...last,
        'lastAlert': _lastAlert,
        'lastAlertDetail': _lastAlertDetail,
        'lastAlertAt': _lastAlertAt,
        'alertKinds': alertKinds,
        'lastAlertKind': _lastAlertKind,
      };
      await _postAndroid();
      return;
    }
    final id = _activityId;
    final last = _lastPayload;
    if (!_supported || id == null || last == null) return;
    final upd = Map<String, Object?>.from(last)
      ..['lastAlert'] = _lastAlert
      ..['lastAlertDetail'] = _lastAlertDetail
      ..['lastAlertAt'] = _lastAlertAt
      ..['alertKinds'] = alertKinds
      ..['lastAlertKind'] = _lastAlertKind
      ..['activityId'] = id;
    _lastPayload = upd;
    try {
      await _channel.invokeMethod('updateActivity', {...upd, 'alert': alert});
    } catch (e) {
      DebugLog.log('LIVE_ACTIVITY: alert update error: $e');
    }
  }

  Future<void> update({
    required String primaryMode,
    required int uniqueCount,
    int wifiCount = 0,
    int bleCount = 0,
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
    bool allowStart = false,
  }) async {
    if (!_supported && !_android) return;

    final payload = <String, Object?>{
      'lastAlert': _lastAlert,
      'lastAlertDetail': _lastAlertDetail,
      'lastAlertAt': _lastAlertAt,
      'alertKinds': alertKinds,
      'lastAlertKind': _lastAlertKind,
      'mode': primaryMode,
      'uniqueCount': uniqueCount,
      'wifiCount': wifiCount,
      'bleCount': bleCount,
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

    _lastPayload = payload;
    if (_android) {
      if (!_androidShown && !allowStart) return;
      if (!_androidShown) _mode = primaryMode;
      _androidShown = true;
      await _postAndroid();
      return;
    }
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
      if (!allowStart) return;
      _startInFlight = _channel.invokeMethod<String>('startActivity', payload);
      try {
        _activityId = await _startInFlight!;
        _mode = primaryMode;
        DebugLog.log('LIVE_ACTIVITY: started activity=$_activityId mode=$primaryMode');
      } finally {
        _startInFlight = null;
      }
    } catch (e) {
      _startInFlight = null;
      _activityId = null;
      _mode = null;
      DebugLog.log('LIVE_ACTIVITY: update error: $e');
    }
  }

  /// End every Live Activity of our type and forget the local handle.
  Future<void> end() async {
    if (_android) {
      _androidPostTimer?.cancel();
      _androidPostTimer = null;
      if (_androidShown) {
        try {
          await FlutterLocalNotificationsPlugin().cancel(_androidStatusId);
        } catch (e) {
          DebugLog.log('LIVE_STATUS: cancel error: $e');
        }
      }
      _androidShown = false;
      _resetState();
      return;
    }
    if (!Platform.isIOS) return;
    if (_activityId == null && _startInFlight != null) {
      _activityId = await _startInFlight;
    }
    final id = _activityId;
    try {
      await _channel.invokeMethod('endAllActivities');
      DebugLog.log('LIVE_ACTIVITY: ended activity=$id mode=$_mode');
    } on MissingPluginException {
      if (id != null) {
        try {
          await _channel.invokeMethod('endActivity', {'activityId': id});
          DebugLog.log('LIVE_ACTIVITY: ended activity=$id (legacy handler)');
        } catch (e) {
          DebugLog.log('LIVE_ACTIVITY: end fallback error: $e');
        }
      }
    } catch (e) {
      DebugLog.log('LIVE_ACTIVITY: end error: $e');
    } finally {
      _resetState();
    }
  }

  void _resetState() {
    _activityId = null;
    _mode = null;
    _lastPayload = null;
    _lastAlert = '';
    _lastAlertDetail = '';
    _lastAlertKind = '';
    _lastAlertAt = 0;
    _alertMacs.clear();
  }

  Future<void> _postAndroid() async {
    final p = _lastPayload;
    if (p == null || !_androidShown) return;
    final wait = 1000 - DateTime.now().difference(_androidLastPost).inMilliseconds;
    if (wait > 0) {
      _androidPostTimer ??= Timer(Duration(milliseconds: wait), () {
        _androidPostTimer = null;
        _postAndroid();
      });
      return;
    }
    _androidLastPost = DateTime.now();
    final (title, text, big) = androidStatusText(p);
    final at = _lastAlertAt;
    try {
      await FlutterLocalNotificationsPlugin().show(
        _androidStatusId,
        title,
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            NotifChannel.liveStatus,
            'Live Scan Status',
            channelDescription: 'Ongoing counts and the latest alert while a scan runs',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            showWhen: at > 0,
            when: at > 0 ? (at * 1000).round() : null,
            category: AndroidNotificationCategory.status,
            styleInformation: BigTextStyleInformation(big, contentTitle: title),
          ),
        ),
      );
    } catch (e) {
      DebugLog.log('LIVE_STATUS: post error: $e');
    }
  }

  static const _modeLabels = {
    'detector': 'DETECTOR',
    'flockBle': 'FLOCK BLE',
    'flockWifi': 'FLOCK WiFi',
    'flockDual': 'FLOCK WiFi+BLE',
    'foxhunter': 'FOXHUNT',
    'skySpy': 'SKY SPY',
    'uniPwn': 'UNIPWN',
    'wardrive': 'WARDRIVE',
    'wardriveFlock': 'WIGLE+FLOCK',
  };

  static String _kindLabel(String k) => switch (k) {
        'flock' => 'Flock',
        'drone' => 'Drones',
        'foxhunt' => 'Foxhunt',
        'detector' => 'Detector',
        _ => SignatureClass.values.where((c) => c.name == k).firstOrNull?.label ?? k,
      };

  static (String, String, String) androidStatusText(Map<String, Object?> p) {
    int n(String k) => (p[k] as num?)?.toInt() ?? 0;
    final mode = p['mode'] as String? ?? 'wardrive';
    final label = _modeLabels[mode] ?? mode.toUpperCase();
    final imperial = p['isImperial'] == true;
    final title = switch (mode) {
      'foxhunter' => '$label · ${n('rssi')} dBm',
      'uniPwn' => '$label · ${p['exploitStatus'] ?? ''}',
      'wardrive' || 'wardriveFlock' => '$label · WiFi ${n('wifiCount')} · BLE ${n('bleCount')}',
      _ => '$label · ${n('uniqueCount')} unique',
    };
    final km = (p['distanceKm'] as num?)?.toDouble() ?? 0;
    final kmh = (p['speedKmh'] as num?)?.toDouble() ?? 0;
    final stats = [
      if (mode == 'foxhunter') (p['targetMac'] as String? ?? '').toUpperCase(),
      if (n('flockCount') > 0) '${n('flockCount')} cameras',
      if (n('droneCount') > 0) '${n('droneCount')} drones',
      if (n('detectorHits') > 0) '${n('detectorHits')} hits',
      if (km > 0) imperial ? '${(km * 0.621371).toStringAsFixed(1)} mi' : '${km.toStringAsFixed(1)} km',
      if (kmh > 0) imperial ? '${(kmh * 0.621371).round()} mph' : '${kmh.round()} km/h',
    ].where((s) => s.isNotEmpty).join(' · ');
    final kinds = [...?(p['alertKinds'] as Map?)?.cast<String, int>().entries]
      ..sort((a, b) => b.value.compareTo(a.value));
    final kindLine = [for (final k in kinds) '${_kindLabel(k.key)} ${k.value}'].join(' · ');
    final alert = p['lastAlert'] as String? ?? '';
    final detail = (p['lastAlertDetail'] as String? ?? '').split('\n').where((l) => l.isNotEmpty);
    final big = [stats, kindLine, alert, ...detail].where((l) => l.isNotEmpty).join('\n');
    return (
      title,
      alert.isNotEmpty ? alert : (stats.isNotEmpty ? stats : 'Scanning'),
      big.isNotEmpty ? big : 'Scanning',
    );
  }

  Future<void> endAll() => end();

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
