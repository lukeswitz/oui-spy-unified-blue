import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/features/feed/detection_row.dart' show detectorTitle, methodLabel;

/// Notification channels for Android grouping.
class NotifChannel {
  const NotifChannel._();

  static const flock = 'flock_alerts';
  static const detector = 'detector_alerts';
  static const drone = 'drone_alerts';
  static const foxhunt = 'foxhunt_alerts';
  static const wardrive = 'wardrive_status';
}

class NotificationService extends ChangeNotifier {
  NotificationService() {
    _loadPrefs();
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  // Per-engine notification toggles
  bool flockEnabled = true;
  bool detectorEnabled = true;
  bool droneEnabled = true;
  bool foxhuntEnabled = false; // foxhunt is high-frequency, off by default
  bool wardriveStatusEnabled = true;
  Set<SignatureClass> classAlerts = {...defaultAlertClasses};
  final _classAlerted = <String, DateTime>{};
  final _classPending = <String, ClassifiedDevice>{};
  Timer? _classRetry;

  void _scheduleClassRetry() {
    if (_classRetry != null || _recentNotifications.isEmpty) return;
    final wait = _recentNotifications.first.add(const Duration(minutes: 1)).difference(DateTime.now());
    _classRetry = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 50), () {
      _classRetry = null;
      final pending = _classPending.values.toList();
      _classPending.clear();
      pending.forEach(onClassified);
    });
  }

  // Cooldown per MAC to avoid repeat alerts (seconds)
  int cooldownSeconds = 300; // 5 minutes

  // Throttle: max notifications per minute across all engines
  int maxPerMinute = 10;

  // Sound toggles
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  // Milestone alerts during wardrive
  bool milestoneAlertsEnabled = true;
  int _lastMilestone = 0;

  // Cooldown tracking: mac+engine → last notification time
  final Map<String, DateTime> _cooldownMap = {};
  DateTime? _lastFoxhuntNotif;

  // Rate limiter: timestamps of recent notifications
  final List<DateTime> _recentNotifications = [];

  Future<void> init() async {
    if (!_initialized) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      await _createAndroidChannels();
      _initialized = true;
    }

    await _refreshPermission();
    DebugLog.log('NOTIF: initialized=$_initialized permission=$_permissionGranted');
    notifyListeners();
  }

  Future<void> refreshPermission() async {
    if (!_initialized) return;
    await _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      _permissionGranted = await ios
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } else if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      _permissionGranted = await mac
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } else if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == true) {
        _permissionGranted = true;
      } else {
        _permissionGranted =
            await android?.requestNotificationsPermission() ?? false;
      }
    } else {
      _permissionGranted = true;
    }
  }

  Future<void> _createAndroidChannels() async {
    if (!Platform.isAndroid) return;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const channels = [
      AndroidNotificationChannel(
        NotifChannel.flock,
        'Flock Safety Alerts',
        description: 'Alerts when Flock Safety cameras are detected',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotifChannel.detector,
        'Watchlist Alerts',
        description: 'Alerts when watchlist devices are detected',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotifChannel.drone,
        'Drone Alerts',
        description: 'Alerts when FAA Remote ID drones are detected',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotifChannel.foxhunt,
        'Foxhunt Proximity',
        description: 'Proximity alerts during foxhunt tracking',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        NotifChannel.wardrive,
        'Wardrive Status',
        description: 'Wardrive session milestones and status',
        importance: Importance.low,
      ),
    ];

    for (final channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }

  /// Handle a new detection — decide whether to notify.
  void onDetection(Detection det) {
    if (!_initialized || !_permissionGranted) return;

    final enabled = _isEngineEnabled(det.engine);
    if (!enabled) return;

    if (_isRateLimited()) return;
    if (_isCoolingDown(det.macAddress, det.engine)) return;

    _recordCooldown(det.macAddress, det.engine);
    _recordRateLimit();

    _fireDetectionNotification(det);
  }

  void onClassified(ClassifiedDevice d) {
    if (!_initialized || !_permissionGranted) return;
    final alert = alertClassOf(d, classAlerts);
    if (alert == null) return;
    final key = d.obs.mac.isNotEmpty ? d.obs.mac : d.obs.key;
    final last = _classAlerted[key];
    final now = DateTime.now();
    if (last != null && now.difference(last).inSeconds < cooldownSeconds) return;
    if (_isRateLimited()) {
      _classPending[key] = d;
      _scheduleClassRetry();
      return;
    }
    _classPending.remove(key);
    _classAlerted[key] = now;
    if (_classAlerted.length > 1000) {
      _classAlerted.removeWhere((_, t) => now.difference(t).inSeconds >= cooldownSeconds);
    }
    _recordRateLimit();
    if (d.obs.mac.isNotEmpty) {
      classAlertedMacs.add(d.obs.mac.toUpperCase());
      notifyListeners();
    }
    final (title, subtitle, body) = classNotificationText(d, alert);
    _fireNotification(
      id: _notifId(NotifChannel.detector),
      channel: NotifChannel.detector,
      title: title,
      subtitle: subtitle,
      body: body,
      groupKey: NotifChannel.detector,
      alertKind: alert.name,
      alertMac: key,
    );
  }

  static (String, String, String) classNotificationText(ClassifiedDevice d, SignatureClass alert) {
    final matched = d.signatures.where((s) => s.kind.folded == alert).map((s) => s.name).toSet();
    final what = matched.firstOrNull ??
        d.guess.headline.replaceFirst(RegExp(r'^(Most likely|Probably|Could be) '), '');
    final why = matched.length > 1
        ? 'Matched ${matched.join(', ')}'
        : matched.isNotEmpty
            ? 'Signature match'
            : d.vendor != null
                ? 'Vendor ${d.vendor}'
                : 'Classifier estimate';
    final radio = d.obs.kind == RadioKind.ble ? 'Bluetooth' : 'Wi-Fi';
    final body = [
      'Signal ${d.obs.rssi} dBm over $radio${d.obs.channel > 0 ? ' on channel ${d.obs.channel}' : ''}.',
      if (d.obs.name.isNotEmpty && d.obs.name != what) 'Name ${d.obs.name}.',
      if (d.obs.mac.isNotEmpty) 'MAC ${d.obs.mac.toUpperCase()}.',
    ].join(' ');
    return ('${alert.label}: $what', why, body);
  }

  void Function(String title, String detail, String? kind, String? mac)? onAlert;
  final classAlertedMacs = <String>{};

  void setClassAlert(SignatureClass a, bool on) {
    on ? classAlerts.add(a) : classAlerts.remove(a);
    notifyListeners();
    _savePrefs();
  }

  /// Fire a wardrive milestone notification
  void onWardriveUpdate({required int uniqueCount}) {
    if (!_initialized || !_permissionGranted) return;
    if (!milestoneAlertsEnabled) return;

    final milestone = (uniqueCount ~/ 1000) * 1000;
    if (milestone > 0 && milestone > _lastMilestone) {
      _lastMilestone = milestone;
      _fireMilestoneNotification(milestone);
    }
  }

  /// Reset milestone tracking (call on session start).
  void resetMilestones() {
    _lastMilestone = 0;
  }

  /// Fire a foxhunt proximity alert when signal crosses threshold.
  void onFoxhuntProximity({
    required String mac,
    required int rssi,
    required int previousRssi,
  }) {
    if (!_initialized || !_permissionGranted) return;
    if (!foxhuntEnabled) return;
    final now = DateTime.now();
    if (_lastFoxhuntNotif != null &&
        now.difference(_lastFoxhuntNotif!) < const Duration(seconds: 15)) {
      return;
    }

    // Alert on significant RSSI jumps toward target (getting closer)
    if (rssi > -50 && previousRssi <= -50) {
      _lastFoxhuntNotif = now;
      _fireNotification(
        id: _notifId(NotifChannel.foxhunt),
        channel: NotifChannel.foxhunt,
        title: 'Foxhunt Target Very Close',
        subtitle: 'Signal crossed -50 dBm',
        body: 'Signal is now $rssi dBm, up from $previousRssi dBm. MAC ${mac.toUpperCase()}.',
        groupKey: NotifChannel.foxhunt,
      );
    } else if (rssi > -65 && previousRssi <= -65) {
      _lastFoxhuntNotif = now;
      _fireNotification(
        id: _notifId(NotifChannel.foxhunt),
        channel: NotifChannel.foxhunt,
        title: 'Foxhunt Target Getting Closer',
        subtitle: 'Signal crossed -65 dBm',
        body: 'Signal is now $rssi dBm, up from $previousRssi dBm. MAC ${mac.toUpperCase()}.',
        groupKey: NotifChannel.foxhunt,
      );
    }
  }

  bool _isEngineEnabled(Engine engine) {
    return switch (engine) {
      Engine.flockBle || Engine.flockWifi => flockEnabled,
      Engine.detector => true,
      Engine.skySpy => droneEnabled,
      Engine.foxhunter => foxhuntEnabled,
      Engine.wardrive => false, // wardrive uses milestone alerts instead
      Engine.uniPwn => false,
      Engine.pcap => false,
    };
  }

  bool _isCoolingDown(String mac, Engine engine) {
    final key = '$mac|${engine.name}';
    final last = _cooldownMap[key];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < cooldownSeconds;
  }

  void _recordCooldown(String mac, Engine engine) {
    final key = '$mac|${engine.name}';
    _cooldownMap[key] = DateTime.now();

    // Prune old entries to prevent memory leak
    if (_cooldownMap.length > 1000) {
      final cutoff =
          DateTime.now().subtract(Duration(seconds: cooldownSeconds));
      _cooldownMap.removeWhere((_, v) => v.isBefore(cutoff));
    }
  }

  bool _isRateLimited() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    _recentNotifications.removeWhere((t) => t.isBefore(cutoff));
    return _recentNotifications.length >= maxPerMinute;
  }

  void _recordRateLimit() {
    _recentNotifications.add(DateTime.now());
  }

  void _fireDetectionNotification(Detection det) {
    final text = detectionNotificationText(det);
    if (text == null) return;
    final (title, subtitle, body, channel) = text;
    _fireNotification(
      id: _notifId(channel),
      channel: channel,
      title: title,
      subtitle: subtitle,
      body: body,
      groupKey: channel,
      alertKind: switch (det.engine) {
        Engine.flockBle || Engine.flockWifi => 'flock',
        Engine.skySpy => 'drone',
        Engine.foxhunter => 'foxhunt',
        _ => 'detector',
      },
      alertMac: det.macAddress,
    );
  }

  static (String, String, String, String)? detectionNotificationText(Detection det) {
    final uavId = det.odid?.uavId;
    final (title, channel) = switch (det.engine) {
      Engine.flockBle || Engine.flockWifi => ('Flock camera', NotifChannel.flock),
      Engine.detector => (_detectorHeadline(det), NotifChannel.detector),
      Engine.skySpy => (uavId != null && uavId.isNotEmpty ? 'Drone: $uavId' : 'Drone', NotifChannel.drone),
      Engine.foxhunter => ('Foxhunt target', NotifChannel.foxhunt),
      _ => (null, null),
    };
    if (title == null || channel == null) return null;
    return (title, '${det.engine.label} · ${methodLabel(det.method)}', _detectionBody(det, title), channel);
  }

  static String _detectorHeadline(Detection det) {
    final why = det.detector?.filterDescription?.trim() ?? '';
    if (why.isNotEmpty || det.method == 'probe_ssid') return detectorTitle(det);
    return switch (det.method) {
      'tracker' => 'Find My Tracker',
      'flipper' => 'Flipper Zero',
      'deauth_storm' => 'Deauth Attack',
      'pwnagotchi' => 'Pwnagotchi',
      'glasses' => 'Meta Smart Glasses',
      'axon' => 'Axon Device',
      'ble_watchlist' || 'wifi_watchlist' => 'Watchlist Hit',
      _ => detectorTitle(det),
    };
  }

  static String _detectionBody(Detection det, String title) => [
        'Signal ${det.rssi} dBm${det.channel > 0 ? ' on channel ${det.channel}' : ''}.',
        if (det.deviceName.isNotEmpty && det.deviceName != title) 'Name ${det.deviceName}.',
        if (det.ssid.isNotEmpty) 'Network "${det.ssid}".',
        'MAC ${det.macAddress.toUpperCase()}.',
        if (det.sourceNodeId.isNotEmpty) 'Seen by node ${det.sourceNodeId}.',
      ].join(' ');

  void _fireMilestoneNotification(int count) {
    _fireNotification(
      id: _notifId(NotifChannel.wardrive),
      channel: NotifChannel.wardrive,
      title: 'Wardrive Milestone',
      body: '$count unique networks captured so far.',
      groupKey: NotifChannel.wardrive,
    );
  }

  Future<void> _fireNotification({
    required int id,
    required String channel,
    required String title,
    required String body,
    String? subtitle,
    String? groupKey,
    String? alertKind,
    String? alertMac,
  }) async {
    if (channel != NotifChannel.wardrive) {
      onAlert?.call(title, subtitle == null ? body : '$subtitle · $body', alertKind, alertMac);
    }
    final androidDetails = AndroidNotificationDetails(
      channel,
      channel,
      groupKey: groupKey,
      subText: subtitle,
      styleInformation: BigTextStyleInformation(body),
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      priority: Priority.high,
      importance: Importance.high,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      subtitle: subtitle,
      threadIdentifier: groupKey,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, details);
  }

  @override
  void dispose() {
    _classRetry?.cancel();
    super.dispose();
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
      DebugLog.log('NOTIF: cancelAll');
    } catch (e) {
      DebugLog.log('NOTIF: cancelAll error: $e');
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    DebugLog.log('NOTIF: tapped ${response.id} payload=${response.payload}');
    // Navigation handled by app-level callback if needed
  }

  /// Incrementing notification ID scoped per channel.
  final Map<String, int> _channelIds = {};

  int _notifId(String channel) {
    final base = switch (channel) {
      NotifChannel.flock => 1000,
      NotifChannel.detector => 2000,
      NotifChannel.drone => 3000,
      NotifChannel.foxhunt => 4000,
      NotifChannel.wardrive => 5000,
      _ => 9000,
    };
    final seq = (_channelIds[channel] ?? 0) + 1;
    _channelIds[channel] = seq % 100; // cycle through 100 IDs per channel
    return base + seq;
  }


  // --- Preferences persistence ---

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    flockEnabled = p.getBool('notif_flock') ?? true;
    detectorEnabled = p.getBool('notif_detector') ?? true;
    droneEnabled = p.getBool('notif_drone') ?? true;
    foxhuntEnabled = p.getBool('notif_foxhunt') ?? false;
    wardriveStatusEnabled = p.getBool('notif_wardrive_status') ?? true;
    milestoneAlertsEnabled = p.getBool('notif_milestones') ?? true;
    cooldownSeconds = p.getInt('notif_cooldown') ?? 300;
    maxPerMinute = p.getInt('notif_max_per_min') ?? 10;
    soundEnabled = p.getBool('notif_sound') ?? true;
    vibrationEnabled = p.getBool('notif_vibration') ?? true;
    final ac = p.getStringList('notif_alert_classes');
    final ca = p.getStringList('notif_class_alerts');
    if (ac != null) {
      classAlerts = {for (final n in ac) ...alertableClasses.where((c) => c.name == n)};
    } else if (ca != null) {
      const legacy = {
        'cameras': [SignatureClass.surveillance, SignatureClass.camera],
        'lawEnforcement': [SignatureClass.lawEnforcement],
        'drones': [SignatureClass.drone],
        'glasses': [SignatureClass.glasses],
        'trackers': [SignatureClass.finder],
      };
      classAlerts = {for (final n in ca) ...?legacy[n]};
    }
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    p.setBool('notif_flock', flockEnabled);
    p.setBool('notif_detector', detectorEnabled);
    p.setBool('notif_drone', droneEnabled);
    p.setBool('notif_foxhunt', foxhuntEnabled);
    p.setBool('notif_wardrive_status', wardriveStatusEnabled);
    p.setBool('notif_milestones', milestoneAlertsEnabled);
    p.setInt('notif_cooldown', cooldownSeconds);
    p.setInt('notif_max_per_min', maxPerMinute);
    p.setBool('notif_sound', soundEnabled);
    p.setBool('notif_vibration', vibrationEnabled);
    p.setStringList('notif_alert_classes', [for (final a in classAlerts) a.name]);
  }

  void setFlockEnabled(bool v) {
    flockEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setDetectorEnabled(bool v) {
    detectorEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setDroneEnabled(bool v) {
    droneEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setFoxhuntEnabled(bool v) {
    foxhuntEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setWardriveStatusEnabled(bool v) {
    wardriveStatusEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setMilestoneAlertsEnabled(bool v) {
    milestoneAlertsEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setCooldownSeconds(int v) {
    cooldownSeconds = v.clamp(30, 3600);
    notifyListeners();
    _savePrefs();
  }

  void setMaxPerMinute(int v) {
    maxPerMinute = v.clamp(1, 60);
    notifyListeners();
    _savePrefs();
  }

  void setSoundEnabled(bool v) {
    soundEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setVibrationEnabled(bool v) {
    vibrationEnabled = v;
    notifyListeners();
    _savePrefs();
  }
}

final notificationServiceProvider =
    ChangeNotifierProvider<NotificationService>((ref) {
  final svc = NotificationService();
  final la = ref.read(liveActivityServiceProvider);
  svc.onAlert = la.showAlert;
  return svc;
});
