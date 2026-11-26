// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/core/classify/device_explain.dart' show Confidence;
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/notifications/alert_gate.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/features/feed/detection_row.dart' show detectorTitle, methodLabel;

/// Notification channels for Android grouping.
class NotifChannel {
  const NotifChannel._();

  static const flock = 'flock_alerts';
  static const detector = 'detector_alerts';
  static const detectorQuiet = 'detector_suspected';
  static const drone = 'drone_alerts';
  static const foxhunt = 'foxhunt_alerts';
  static const wardrive = 'wardrive_status';
  static const liveStatus = 'live_status';
  static const nodes = 'node_alerts';
  static const quiet = 'alerts_quiet';
}

/// An alert that reached the notification path and was not silenced. [channel] is the [NotifChannel] the alert
/// belongs to, before the sound-off fallback to [NotifChannel.quiet].
class AlertEvent {
  const AlertEvent({required this.title, required this.detail, required this.channel, this.kind, this.mac});

  final String title;
  final String detail;
  final String channel;
  final String? kind;
  final String? mac;
}

class NotificationService extends ChangeNotifier {
  NotificationService() {
    _loadPrefs();
  }

  static const _detectionCategory = 'detection';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  // Per-engine notification toggles
  bool flockEnabled = true;
  bool flockOuiOnly = false;
  bool detectorEnabled = true;
  bool droneEnabled = true;
  bool foxhuntEnabled = false; // foxhunt is high-frequency, off by default
  bool wardriveStatusEnabled = true;
  int minDetectorConfidence = 0;
  Set<SignatureClass> classAlerts = {...defaultAlertClasses};
  Set<String> mutedAlerts = {};
  static const noisyThreshold = 10;
  final _sent = <(DateTime, String)>[];
  DateTime? _noisyAskedAt;
  ({String key, int count, int total})? noisyPrompt;
  final gate = AlertGate();
  String? Function(String mac)? watchLabelOf;
  final Map<AlertSfx, bool> _sfxOn = {for (final s in AlertSfx.values) s: true};
  final _classPending = <String, ClassifiedDevice>{};
  Timer? _classRetry;

  void _scheduleClassRetry() {
    if (_classRetry != null || _recentNotifications.isEmpty) return;
    final wait = _recentNotifications.first.add(const Duration(minutes: 1)).difference(DateTime.now());
    _classRetry = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 50), () {
      _classRetry = null;
      final pending = _classPending.values.toList();
      _classPending.clear();
      for (final d in pending) {
        final alert = classAlertOf(d, classAlerts, flock: flockEnabled);
        if (alert != null) _notifyClassified(d, alert, _classKey(d));
      }
    });
  }

  int get cooldownSeconds => gate.gap.inSeconds;
  set cooldownSeconds(int v) => gate.gap = Duration(seconds: v);

  bool get silenced => gate.silenced;

  void setSilenced(bool v) {
    gate.silenced = v;
    notifyListeners();
  }

  bool sfxOn(AlertSfx s) => _sfxOn[s] ?? true;

  void setSfxOn(AlertSfx s, bool on) {
    _sfxOn[s] = on;
    notifyListeners();
    _savePrefs();
  }

  bool isDeviceMuted(String mac) => gate.isDeviceMuted(mac);

  void setDeviceMuted(String mac, bool muted) {
    final key = AlertGate.keyOf(mac);
    if (key.isEmpty) return;
    muted ? gate.mutedDevices.add(key) : gate.mutedDevices.remove(key);
    notifyListeners();
    _savePrefs();
  }

  static String _classKey(ClassifiedDevice d) => d.obs.mac.isNotEmpty ? AlertGate.keyOf(d.obs.mac) : d.obs.key;

  // Throttle: max notifications per minute across all engines
  int maxPerMinute = 10;

  // Sound toggles
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  // Milestone alerts during wardrive
  bool milestoneAlertsEnabled = true;
  int _lastMilestone = 0;

  DateTime? _lastFoxhuntNotif;

  // Rate limiter: timestamps of recent notifications
  final List<DateTime> _recentNotifications = [];

  @visibleForTesting
  void debugReady() {
    _initialized = true;
    _permissionGranted = true;
  }

  Future<void> init({bool ask = true}) async {
    if (!_initialized) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _detectionCategory,
            options: {
              DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
            },
          ),
        ],
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
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final launchKind = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && launchKind != null && launchKind.isNotEmpty) {
        final cb = onTap;
        if (cb == null) {
          _launchKind = launchKind;
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) => cb(launchKind));
        }
      }

      await _createAndroidChannels();
      _initialized = true;
    }

    await _refreshPermission(ask: ask);
    DebugLog.log('NOTIF: initialized=$_initialized permission=$_permissionGranted');
    notifyListeners();
  }

  Future<void> refreshPermission() async {
    if (!_initialized) return;
    await _refreshPermission(ask: false);
  }

  Future<void> _refreshPermission({required bool ask}) async {
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      _permissionGranted = ask
          ? await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false
          : (await ios?.checkPermissions())?.isEnabled ?? false;
    } else if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      _permissionGranted = ask
          ? await mac?.requestPermissions(alert: true, badge: true, sound: true) ?? false
          : (await mac?.checkPermissions())?.isEnabled ?? false;
    } else if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == true) {
        _permissionGranted = true;
      } else if (ask) {
        _permissionGranted =
            await android?.requestNotificationsPermission() ?? false;
      } else {
        _permissionGranted = false;
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
        NotifChannel.detectorQuiet,
        'Suspected Detections',
        description: 'Weak-evidence detector hits (one vendor OUI or a brief tracker sighting), delivered silently',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
      AndroidNotificationChannel(
        NotifChannel.drone,
        'Drone Alerts',
        description: 'Alerts when FAA Remote ID drones are detected',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotifChannel.nodes,
        'Mesh Node Alerts',
        description: 'A mesh node dropped off or came back',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        NotifChannel.quiet,
        'Alerts without sound',
        description: 'Alerts while their sound is off',
        importance: Importance.defaultImportance,
        playSound: false,
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
      AndroidNotificationChannel(
        NotifChannel.liveStatus,
        'Live Scan Status',
        description: 'Ongoing counts and the latest alert while a scan runs',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
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
    if (det.engine == Engine.detector && detectorMethodClass.containsKey(det.method)) return;
    if (det.engine == Engine.detector && belowConfidence(det.detector?.confidence ?? 0)) return;
    final key = AlertGate.keyOf(det.macAddress);
    if (key.isEmpty) return;
    final label = watchLabelOf?.call(det.macAddress);
    final verdict = gate.check(key, DateTime.now().millisecondsSinceEpoch,
        watchLabel: label, kindMuted: mutedAlerts.contains(muteKeyOf(det)));
    if (verdict != AlertVerdict.fire) return;
    if (_isRateLimited()) return;
    _recordRateLimit();

    _fireDetectionNotification(det, watchLabel: label);
  }

  /// True when this sighting is the first of the device or follows a gap of more than the re-arm time.
  bool onClassified(ClassifiedDevice d, {int? prevSeenMs}) {
    final alert = classAlertOf(d, classAlerts, flock: flockEnabled);
    if (alert == null) return false;
    final key = _classKey(d);
    if (!gate.due(key, d.obs.lastSeenMs > 0 ? d.obs.lastSeenMs : DateTime.now().millisecondsSinceEpoch,
        lastSeenMs: prevSeenMs)) {
      return false;
    }
    _notifyClassified(d, alert, key);
    return true;
  }

  void _notifyClassified(ClassifiedDevice d, ClassAlert alert, String key) {
    if (!_initialized || !_permissionGranted) return;
    final label = d.obs.mac.isEmpty ? null : watchLabelOf?.call(d.obs.mac);
    final kindMuted = mutedAlerts.contains(alert.kind) ||
        (d.obs.detectorMethod != null && mutedAlerts.contains('det:${d.obs.detectorMethod}'));
    if (gate.block(key, watchLabel: label, kindMuted: kindMuted) != AlertVerdict.fire) return;
    if (d.obs.detectorMethod != null && belowConfidence(d.obs.detectorConfidence)) return;
    if (_isRateLimited()) {
      _classPending[key] = d;
      _scheduleClassRetry();
      return;
    }
    _classPending.remove(key);
    _recordRateLimit();
    if (d.obs.mac.isNotEmpty) {
      classAlertedMacs.add(d.obs.mac.toUpperCase());
      classAlertKinds[d.obs.mac.toUpperCase()] = alert.kind;
      notifyListeners();
    }
    final (title, why, body) = classNotificationText(d, alert);
    final channel = alert == ClassAlert.flock
        ? NotifChannel.flock
        : d.obs.detectorMethod != null && d.obs.detectorConfidence == confSuspected
            ? NotifChannel.detectorQuiet
            : NotifChannel.detector;
    _fireNotification(
      id: _notifId(channel),
      channel: channel,
      title: label ?? title,
      subtitle: label != null ? AlertSfx.watch.label : why,
      body: body,
      groupKey: channel,
      alertKind: alert.kind,
      alertMac: d.obs.mac.isNotEmpty ? d.obs.mac : d.obs.key,
      muteKey: alert.kind,
      sfx: alertSfxFor(
        watchLabel: label,
        drone: alert.kind == SignatureClass.drone.name,
        tracker: alert.kind == SignatureClass.finder.name || d.obs.detectorMethod == 'tracker',
      ),
    );
  }

  void onNodeDown(String label) => _nodeAlert(AlertSfx.nodeDown, '$label dropped off the mesh', 'Node down: $label');

  void onNodeUp(String label) => _nodeAlert(AlertSfx.nodeUp, '$label is back on the mesh', 'Node back: $label');

  void _nodeAlert(AlertSfx sfx, String body, String title) {
    if (!_initialized || !_permissionGranted || gate.silenced) return;
    _fireNotification(
      id: _notifId(NotifChannel.nodes),
      channel: NotifChannel.nodes,
      title: title,
      body: body,
      groupKey: NotifChannel.nodes,
      sfx: sfx,
    );
  }

  static const confSuspected = 1;
  static const confHigh = 2;
  static const confVerified = 3;

  static String? confidenceLabel(int c) => switch (c) {
        confSuspected => 'Suspected',
        confHigh => 'High',
        confVerified => 'Verified',
        _ => null,
      };

  bool belowConfidence(int c) => c > 0 && c < minDetectorConfidence;

  void setMinDetectorConfidence(int v) {
    minDetectorConfidence = v.clamp(0, confVerified);
    notifyListeners();
    _savePrefs();
  }

  static String muteKeyOf(Detection det) => switch (det.engine) {
        Engine.flockBle || Engine.flockWifi => 'flock',
        Engine.skySpy => 'drone',
        Engine.foxhunter => 'foxhunt',
        _ => det.method.endsWith('watchlist') ? 'det:watchlist' : 'det:${det.method}',
      };

  static String muteLabel(String k) {
    if (k.startsWith('det:')) {
      final m = k.substring(4);
      if (m == 'watchlist') return 'Watchlist hits';
      for (final e in detectorMethodsByBit.entries) {
        if (e.value.contains(m)) return detectorSignatures.firstWhere((s) => s.bit == e.key).label;
      }
      return methodLabel(m);
    }
    return switch (k) {
      'flock' => 'Flock',
      'drone' => 'Drones',
      'foxhunt' => 'Foxhunt',
      _ => SignatureClass.values.where((c) => c.name == k).firstOrNull?.label ?? k,
    };
  }

  bool isMuted(Iterable<String> keys) => keys.any(mutedAlerts.contains);

  void setMuted(Iterable<String> keys, bool muted) {
    for (final k in keys) {
      if (k == 'foxhunt') {
        foxhuntEnabled = !muted;
      } else {
        muted ? mutedAlerts.add(k) : mutedAlerts.remove(k);
      }
    }
    notifyListeners();
    _savePrefs();
  }

  void _noteSent(String key) {
    final now = DateTime.now();
    _sent
      ..add((now, key))
      ..removeWhere((e) => now.difference(e.$1).inSeconds >= 60);
    if (_sent.length < noisyThreshold || noisyPrompt != null) return;
    if (_noisyAskedAt != null && now.difference(_noisyAskedAt!).inMinutes < 10) return;
    final counts = <String, int>{};
    for (final e in _sent) {
      counts[e.$2] = (counts[e.$2] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    _noisyAskedAt = now;
    noisyPrompt = (key: top.key, count: top.value, total: _sent.length);
    notifyListeners();
  }

  void resolveNoisy(bool mute) {
    final p = noisyPrompt;
    noisyPrompt = null;
    if (mute && p != null) {
      setMuted([p.key], true);
    } else {
      notifyListeners();
    }
  }

  static (String, String, String) classNotificationText(ClassifiedDevice d, ClassAlert alert) {
    final matched = d.signatures.where(alert.matches).map((s) => s.name).toSet();
    final method = d.obs.detectorMethod;
    final desc = d.obs.detectorDesc?.trim() ?? '';
    final board = method == null
        ? null
        : desc.isNotEmpty
            ? desc
            : detectorMethodName(method) ?? methodLabel(method);
    final what = matched.firstOrNull ??
        (board != null && d.guess.confidence == Confidence.low
            ? board
            : d.guess.headline.replaceFirst(RegExp(r'^(Most likely|Probably|Could be) '), ''));
    final why = matched.length > 1
        ? 'Matched ${matched.join(', ')}'
        : matched.isNotEmpty
            ? 'Signature match'
            : board != null
                ? 'Board detector: $board'
                : d.vendor != null
                    ? 'Vendor ${d.vendor}'
                    : 'Classifier estimate';
    final radio = d.obs.kind == RadioKind.ble ? 'Bluetooth' : 'Wi-Fi';
    final body = [
      '${d.obs.rssi} dBm · $radio${d.obs.channel > 0 ? ' · ch ${d.obs.channel}' : ''}',
      if (d.obs.name.isNotEmpty && d.obs.name != what) d.obs.name,
      if ((matched.isNotEmpty || board != null) && d.vendor != null && d.vendor != what) d.vendor!,
      if (d.obs.mac.isNotEmpty) d.obs.mac.toUpperCase(),
      if (d.obs.detectorNode != null) 'via node ${d.obs.detectorNode}',
    ].join('\n');
    return ('${alert.label}: $what', why, body);
  }

  void Function(String title, String detail, String? kind, String? mac, bool alert)? onAlert;
  final _alertListeners = <void Function(AlertEvent)>[];

  void addAlertListener(void Function(AlertEvent) listener) => _alertListeners.add(listener);

  void removeAlertListener(void Function(AlertEvent) listener) => _alertListeners.remove(listener);

  bool Function()? activityCanAlert;
  final classAlertedMacs = <String>{};
  final classAlertKinds = <String, String>{};

  void setClassAlert(SignatureClass a, bool on) {
    on ? classAlerts.add(a) : classAlerts.remove(a);
    notifyListeners();
    _savePrefs();
  }

  static int milestoneFor(int count) {
    const steps = [1000, 5000, 10000, 25000, 50000];
    if (count >= 100000) return (count ~/ 100000) * 100000;
    var m = 0;
    for (final s in steps) {
      if (count >= s) m = s;
    }
    return m;
  }

  void onWatchAlert({required String kind, required String title, required String body, String? subtitle, String? mac}) {
    if (!_initialized || !_permissionGranted || gate.silenced || mutedAlerts.contains(kind) || _isRateLimited()) return;
    _recordRateLimit();
    _fireNotification(
      id: _notifId(NotifChannel.detector),
      channel: NotifChannel.detector,
      title: title,
      subtitle: subtitle,
      body: body,
      groupKey: NotifChannel.detector,
      alertKind: kind,
      alertMac: mac,
      muteKey: kind,
    );
  }

  void onWardriveEndedBoardLost({required int minutes, required int detections}) {
    if (!_initialized || !_permissionGranted || !wardriveStatusEnabled) return;
    _fireNotification(
      id: _notifId(NotifChannel.wardrive),
      channel: NotifChannel.wardrive,
      title: 'Wardrive ended',
      body: 'The board did not reconnect within $minutes minutes. Session saved with $detections detections.',
    );
  }

  /// Fire a wardrive milestone notification
  void onWardriveUpdate({required int uniqueCount}) {
    if (!_initialized || !_permissionGranted) return;
    if (!milestoneAlertsEnabled) return;

    final milestone = milestoneFor(uniqueCount);
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
        muteKey: 'foxhunt',
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
        muteKey: 'foxhunt',
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
      Engine.axeoff => false,
      Engine.bleSniff => false,
      Engine.sdr => false,
    };
  }

  bool _isRateLimited() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    _recentNotifications.removeWhere((t) => t.isBefore(cutoff));
    return _recentNotifications.length >= maxPerMinute;
  }

  void _recordRateLimit() {
    _recentNotifications.add(DateTime.now());
  }

  void _fireDetectionNotification(Detection det, {String? watchLabel}) {
    final text = detectionNotificationText(det);
    if (text == null) return;
    final (title, subtitle, body, channel) = text;
    _fireNotification(
      id: _notifId(channel),
      channel: channel,
      title: watchLabel ?? title,
      subtitle: watchLabel != null ? AlertSfx.watch.label : subtitle,
      body: body,
      sfx: alertSfxFor(
        watchLabel: watchLabel,
        drone: det.engine == Engine.skySpy,
        tracker: det.method == 'tracker',
      ),
      groupKey: channel,
      alertKind: switch (det.engine) {
        Engine.flockBle || Engine.flockWifi => 'flock',
        Engine.skySpy => 'drone',
        Engine.foxhunter => 'foxhunt',
        _ => 'detector',
      },
      alertMac: det.macAddress,
      muteKey: muteKeyOf(det),
    );
  }

  static (String, String, String, String)? detectionNotificationText(Detection det) {
    final uavId = det.odid?.uavId;
    final conf = det.detector?.confidence ?? 0;
    final (title, channel) = switch (det.engine) {
      Engine.flockBle || Engine.flockWifi => ('Flock camera', NotifChannel.flock),
      Engine.detector => (_detectorHeadline(det),
          conf == confSuspected ? NotifChannel.detectorQuiet : NotifChannel.detector),
      Engine.skySpy => (uavId != null && uavId.isNotEmpty ? 'Drone: $uavId' : 'Drone', NotifChannel.drone),
      Engine.foxhunter => ('Foxhunt target', NotifChannel.foxhunt),
      _ => (null, null),
    };
    if (title == null || channel == null) return null;
    final tier = det.engine == Engine.detector ? confidenceLabel(conf) : null;
    return (
      title,
      '${det.engine.label} · ${methodLabel(det.method)}${tier != null ? ' · $tier' : ''}',
      _detectionBody(det, title),
      channel,
    );
  }

  static String _detectorHeadline(Detection det) {
    final why = det.detector?.filterDescription?.trim() ?? '';
    if (why.isNotEmpty && det.method.endsWith('watchlist')) return 'Watchlist: $why';
    if (why.isNotEmpty || det.method == 'probe_ssid') return detectorTitle(det);
    return detectorMethodName(det.method) ?? detectorTitle(det);
  }

  static String? detectorMethodName(String method) => switch (method) {
        'tracker' => 'Tracker',
        'flipper' => 'Flipper Zero',
        'deauth_storm' => 'Deauth Attack',
        'join_flood' => 'Wi-Fi Join Flood',
        'tag_flood' => 'Tracker Tag Flood',
        'beacon_flood' => 'Wi-Fi Beacon Flood',
        'pwnagotchi' => 'Pwnagotchi',
        'glasses' => 'Meta Smart Glasses',
        'axon' => 'Axon Device',
        'evil_twin' => 'Evil Twin AP',
        'karma' => 'KARMA AP',
        'mesh' => 'Mesh Radio',
        'wearable_cam' => 'Wearable Camera',
        'vehicle' => 'Vehicle',
        'drone_ble' => 'Drone',
        'ble_watchlist' || 'wifi_watchlist' => 'Watchlist Hit',
        _ => null,
      };

  static String _detectionBody(Detection det, String title) => [
        '${det.rssi} dBm${det.channel > 0 ? ' · ch ${det.channel}' : ''}',
        if (det.deviceName.isNotEmpty && det.deviceName != title) det.deviceName,
        if (det.ssid.isNotEmpty) '"${det.ssid}"',
        ?_droneLine(det.odid),
        det.macAddress.toUpperCase(),
        if (det.sourceNodeId.isNotEmpty) 'via node ${det.sourceNodeId}',
      ].join('\n');

  static String? _droneLine(OdidExtension? o) {
    if (o == null) return null;
    final parts = [
      if (o.heightAgl != null) '${o.heightAgl} m AGL' else if (o.altitudeMsl != null) '${o.altitudeMsl} m MSL',
      if (o.droneSpeed != null) '${o.droneSpeed} m/s',
      if (o.operatorId != null && o.operatorId!.isNotEmpty) 'Operator ${o.operatorId}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

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
    String? muteKey,
    AlertSfx? sfx,
  }) async {
    if (gate.silenced) return;
    if (muteKey != null) _noteSent(muteKey);
    final alertChannel = channel;
    final soundOn = soundEnabled && (sfx == null || sfxOn(sfx));
    if (!soundOn && channel != NotifChannel.wardrive && channel != NotifChannel.detectorQuiet) {
      channel = NotifChannel.quiet;
    }
    final viaActivity = channel != NotifChannel.wardrive &&
        soundOn &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
        (activityCanAlert?.call() ?? false);
    if (channel != NotifChannel.wardrive) {
      final detail = subtitle == null ? body : '$subtitle · $body';
      onAlert?.call(title, detail, alertKind, alertMac, viaActivity);
      if (_alertListeners.isNotEmpty) {
        final event = AlertEvent(title: title, detail: detail, channel: alertChannel, kind: alertKind, mac: alertMac);
        for (final l in List.of(_alertListeners)) {
          l(event);
        }
      }
    }
    final androidDetails = AndroidNotificationDetails(
      channel,
      channel,
      groupKey: groupKey,
      subText: subtitle,
      styleInformation: BigTextStyleInformation(body),
      playSound: soundOn && channel != NotifChannel.detectorQuiet,
      enableVibration: vibrationEnabled && channel != NotifChannel.detectorQuiet,
      priority: channel == NotifChannel.detectorQuiet ? Priority.low : Priority.high,
      importance: channel == NotifChannel.detectorQuiet ? Importance.low : Importance.high,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundOn && !viaActivity && channel != NotifChannel.detectorQuiet,
      subtitle: subtitle,
      threadIdentifier: groupKey,
      categoryIdentifier: channel == NotifChannel.wardrive ? null : _detectionCategory,
      interruptionLevel: channel == NotifChannel.wardrive
          ? null
          : viaActivity || channel == NotifChannel.detectorQuiet
              ? InterruptionLevel.passive
              : InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, details, payload: alertKind);
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

  void Function(String kind)? onTap;
  String? _launchKind;

  String? takeLaunchKind() {
    final k = _launchKind;
    _launchKind = null;
    return k;
  }

  void _onNotificationTap(NotificationResponse response) {
    DebugLog.log('NOTIF: tapped ${response.id} payload=${response.payload}');
    final kind = response.payload;
    if (kind == null || kind.isEmpty) return;
    final cb = onTap;
    if (cb == null) {
      _launchKind = kind;
      return;
    }
    cb(kind);
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
      NotifChannel.nodes => 6000,
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
    flockOuiOnly = p.getBool('notif_flock_oui_only') ?? false;
    detectorEnabled = p.getBool('notif_detector') ?? true;
    droneEnabled = p.getBool('notif_drone') ?? true;
    foxhuntEnabled = p.getBool('notif_foxhunt') ?? false;
    wardriveStatusEnabled = p.getBool('notif_wardrive_status') ?? true;
    milestoneAlertsEnabled = p.getBool('notif_milestones') ?? true;
    minDetectorConfidence = p.getInt('notif_min_confidence') ?? 0;
    final legacyCooldown = p.getInt('notif_cooldown');
    cooldownSeconds =
        p.getInt('notif_rearm') ?? (legacyCooldown != null && legacyCooldown != 300 ? legacyCooldown : alertRearmSeconds);
    for (final s in AlertSfx.values) {
      _sfxOn[s] = p.getBool(s.prefKey) ?? true;
    }
    gate.mutedDevices
      ..clear()
      ..addAll(p.getStringList('notif_muted_devices') ?? const []);
    maxPerMinute = p.getInt('notif_max_per_min') ?? 10;
    soundEnabled = p.getBool('notif_sound') ?? true;
    vibrationEnabled = p.getBool('notif_vibration') ?? true;
    mutedAlerts = {...?p.getStringList('notif_muted')};
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
    p.setBool('notif_flock_oui_only', flockOuiOnly);
    p.setBool('notif_detector', detectorEnabled);
    p.setBool('notif_drone', droneEnabled);
    p.setBool('notif_foxhunt', foxhuntEnabled);
    p.setBool('notif_wardrive_status', wardriveStatusEnabled);
    p.setBool('notif_milestones', milestoneAlertsEnabled);
    p.setInt('notif_min_confidence', minDetectorConfidence);
    p.setInt('notif_rearm', cooldownSeconds);
    for (final s in AlertSfx.values) {
      p.setBool(s.prefKey, sfxOn(s));
    }
    p.setStringList('notif_muted_devices', [...gate.mutedDevices]);
    p.setInt('notif_max_per_min', maxPerMinute);
    p.setBool('notif_sound', soundEnabled);
    p.setBool('notif_vibration', vibrationEnabled);
    p.setStringList('notif_alert_classes', [for (final a in classAlerts) a.name]);
    p.setStringList('notif_muted', [...mutedAlerts]);
  }

  void setFlockEnabled(bool v) {
    flockEnabled = v;
    notifyListeners();
    _savePrefs();
  }

  void setFlockOuiOnly(bool v) {
    flockOuiOnly = v;
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
  svc.activityCanAlert = () => la.canAlert;
  final watch = ref.read(watchlistProvider);
  svc.watchLabelOf = watch.labelForMac;
  return svc;
});
