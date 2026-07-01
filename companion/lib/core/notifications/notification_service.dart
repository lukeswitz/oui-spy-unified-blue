import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

/// Notification channels for Android grouping.
class NotifChannel {
  const NotifChannel._();

  static const flock = 'flock_alerts';
  static const detector = 'detector_alerts';
  static const drone = 'drone_alerts';
  static const foxhunt = 'foxhunt_alerts';
  static const wardrive = 'wardrive_status';
}

/// Manages local notifications for detection events.
///
/// Intelligent alerting:
/// - Per-engine enable/disable
/// - Per-MAC cooldown to avoid spam (configurable)
/// - Grouped notifications per engine type
/// - Sound/vibration preferences
/// - Automatic throttling under high detection rates
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

  // Rate limiter: timestamps of recent notifications
  final List<DateTime> _recentNotifications = [];

  /// Initialize the notification plugin and request permissions.
  /// Safe to call multiple times — re-checks permission every call.
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

  /// Re-query OS for current permission state. Called by RETRY button after
  /// user toggles permission in system settings. iOS/macOS: calling
  /// requestPermissions after the first prompt returns the current grant state
  /// without re-prompting. Android 13+: checkPermission if available, fall
  /// back to request.
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

    // Alert on significant RSSI jumps toward target (getting closer)
    if (rssi > -50 && previousRssi <= -50) {
      _fireNotification(
        id: _notifId(NotifChannel.foxhunt),
        channel: NotifChannel.foxhunt,
        title: 'Foxhunt: CLOSE',
        body: 'Target ${_formatMac(mac)} signal ${rssi}dBm — very close!',
        groupKey: NotifChannel.foxhunt,
      );
    } else if (rssi > -65 && previousRssi <= -65) {
      _fireNotification(
        id: _notifId(NotifChannel.foxhunt),
        channel: NotifChannel.foxhunt,
        title: 'Foxhunt: Getting warm',
        body: 'Target ${_formatMac(mac)} signal ${rssi}dBm',
        groupKey: NotifChannel.foxhunt,
      );
    }
  }

  bool _isEngineEnabled(Engine engine) {
    return switch (engine) {
      Engine.flockBle || Engine.flockWifi => flockEnabled,
      Engine.detector => detectorEnabled,
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
    final (title, body, channel) = switch (det.engine) {
      Engine.flockBle || Engine.flockWifi => (
          'Flock Camera Detected',
          det.engine == Engine.flockBle
              ? '${_formatMac(det.macAddress)} BLE ${det.rssi}dBm'
              : '${_formatMac(det.macAddress)} WiFi ch${det.channel} ${det.rssi}dBm',
          NotifChannel.flock,
        ),
      Engine.detector => (
          'Watchlist Hit',
          '${det.deviceName.isNotEmpty ? det.deviceName : _formatMac(det.macAddress)} ${det.rssi}dBm',
          NotifChannel.detector,
        ),
      Engine.skySpy => (
          'Drone Detected',
          '${det.odid?.uavId ?? _formatMac(det.macAddress)} ${det.rssi}dBm',
          NotifChannel.drone,
        ),
      Engine.foxhunter => (
          'Foxhunt Signal',
          '${_formatMac(det.macAddress)} ${det.rssi}dBm',
          NotifChannel.foxhunt,
        ),
      _ => (null, null, null),
    };

    if (title == null || body == null || channel == null) return;

    _fireNotification(
      id: _notifId(channel),
      channel: channel,
      title: title,
      body: body,
      groupKey: channel,
    );
  }

  void _fireMilestoneNotification(int count) {
    _fireNotification(
      id: _notifId(NotifChannel.wardrive),
      channel: NotifChannel.wardrive,
      title: 'Wardrive Milestone',
      body: '$count unique networks captured!',
      groupKey: NotifChannel.wardrive,
    );
  }

  Future<void> _fireNotification({
    required int id,
    required String channel,
    required String title,
    required String body,
    String? groupKey,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channel,
      channel,
      groupKey: groupKey,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      priority: Priority.high,
      importance: Importance.high,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      threadIdentifier: groupKey,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, details);
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

  static String _formatMac(String mac) =>
      mac.length >= 8 ? mac.substring(0, 8).toUpperCase() : mac.toUpperCase();

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
  return NotificationService();
});
