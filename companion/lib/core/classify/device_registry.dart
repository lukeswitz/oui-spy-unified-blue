import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/classify/bt_sig_registry.dart';
import 'package:oui_spy/core/classify/vendor_class.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'co_travel.dart';
import 'device_explain.dart';
import 'flood.dart';
import 'kin_index.dart';
import 'observation.dart';
import 'signature_engine.dart';

abstract class ObservationSource {
  String get name;
  Stream<Observation> get observations;
  void dispose() {}
}

String _hexBytes(Iterable<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String _uuidLe(List<int> b) {
  final h = _hexBytes(b.reversed);
  if (h.length != 32) return h;
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class AdvParts {
  final String name;
  final List<String> serviceUuids;
  final List<MfgRecord> mfg;
  final List<ServiceDataRecord> serviceData;
  final int? appearance;
  const AdvParts(this.name, this.serviceUuids, this.mfg, this.serviceData, this.appearance);
}

AdvParts parseAdvStructures(List<int> raw) {
  var name = '';
  final uuids = <String>[];
  final mfg = <MfgRecord>[];
  final sd = <ServiceDataRecord>[];
  int? appearance;
  var i = 0;
  while (i < raw.length) {
    final len = raw[i];
    if (len == 0 || i + 1 + len > raw.length) break;
    final type = raw[i + 1];
    final d = raw.sublist(i + 2, i + 1 + len);
    switch (type) {
      case 0x02 || 0x03:
        for (var j = 0; j + 2 <= d.length; j += 2) {
          uuids.add(_uuidLe(d.sublist(j, j + 2)));
        }
      case 0x04 || 0x05:
        for (var j = 0; j + 4 <= d.length; j += 4) {
          uuids.add(_uuidLe(d.sublist(j, j + 4)));
        }
      case 0x06 || 0x07:
        for (var j = 0; j + 16 <= d.length; j += 16) {
          uuids.add(_uuidLe(d.sublist(j, j + 16)));
        }
      case 0x08 || 0x09:
        if (type == 0x09 || name.isEmpty) name = String.fromCharCodes(d.where((c) => c >= 0x20 && c < 0x7F));
      case 0x16:
        if (d.length >= 2) sd.add(ServiceDataRecord(_uuidLe(d.sublist(0, 2)), _hexBytes(d.sublist(2))));
      case 0x20:
        if (d.length >= 4) sd.add(ServiceDataRecord(_uuidLe(d.sublist(0, 4)), _hexBytes(d.sublist(4))));
      case 0x21:
        if (d.length >= 16) sd.add(ServiceDataRecord(_uuidLe(d.sublist(0, 16)), _hexBytes(d.sublist(16))));
      case 0x19:
        if (d.length >= 2) appearance = d[0] | (d[1] << 8);
      case 0xFF:
        if (d.length >= 2) mfg.add(MfgRecord(d[0] | (d[1] << 8), _hexBytes(d.sublist(2))));
    }
    i += 1 + len;
  }
  return AdvParts(name, uuids, mfg, sd, appearance);
}

Observation observationFromDetection(Detection d) {
  final ble = d.isBleDetection;
  final mac = MacUtil.normalize(d.macAddress);
  final at = d.appTimestamp.millisecondsSinceEpoch;
  final raw = (d.wardrive == null ? null : wardriveAdvRaw[d.wardrive!]) ?? const <int>[];
  final adv = parseAdvStructures(ble ? raw : const []);
  final ieOuis = ble ? const <String>[] : [for (var i = 0; i + 3 <= raw.length; i += 3) _hexBytes(raw.sublist(i, i + 3))];
  final name = d.ssid.isNotEmpty ? d.ssid : (d.deviceName.isNotEmpty ? d.deviceName : adv.name);
  return Observation(
    serviceUuids: adv.serviceUuids,
    mfgRecords: adv.mfg,
    serviceData: adv.serviceData,
    appearance: adv.appearance,
    key: '${ble ? 'BLE' : 'WIFI'}:$mac',
    kind: ble ? RadioKind.ble : RadioKind.wifi,
    mac: mac,
    name: name,
    rssi: d.rssi,
    firstSeenMs: at,
    lastSeenMs: at,
    channel: ble ? 0 : d.channel,
    authMode: ble || d.method != 'wifi_ap' ? null : d.wardrive?.authMode,
    hiddenSsid: !ble && d.method == 'wifi_ap' && d.ssid.trim().isEmpty,
    isAp: !ble && d.method == 'wifi_ap',
    vendorIeOuis: ieOuis,
    detectorMethod: d.engine == Engine.detector ? d.method : null,
    detectorDesc: d.engine == Engine.detector ? d.detector?.filterDescription : null,
    detectorNode: d.engine == Engine.detector && d.sourceNodeId.isNotEmpty ? d.sourceNodeId : null,
    gpsTrail: d.latitude != null && d.longitude != null && !d.approxGps
        ? [GpsSample(at, d.latitude!, d.longitude!, d.rssi)]
        : const [],
  );
}

class EspDetectionSource extends ObservationSource {
  EspDetectionSource(Stream<Detection> detections)
      : observations = detections
            .where((d) => d.nodeId != BleManager.phoneNodeId)
            .map(observationFromDetection);

  @override
  String get name => 'esp32';

  @override
  final Stream<Observation> observations;
}

class PhoneBleSource extends ObservationSource with ChangeNotifier {
  static const scanEvery = Duration(seconds: 20);

  final _out = StreamController<Observation>.broadcast();
  StreamSubscription<List<ScanResult>>? _sub;
  Timer? _timer;
  bool _active = false;
  GpsSample? Function()? here;

  PhoneBleSource({this.here}) {
    _sub = FlutterBluePlus.onScanResults.listen(_onResults);
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.on) {
        if (_foxTarget != null) {
          _foxScan();
        } else {
          _kick();
        }
      }
      notifyListeners();
    });
    _busySub = FlutterBluePlus.isScanning.listen((busy) {
      if (busy) return;
      if (_foxTarget != null) {
        _foxScan();
        return;
      }
      if (_ownScan) {
        _ownScan = false;
        notifyListeners();
      }
      if (scanning && _duty == null) {
        Future<void>.delayed(const Duration(milliseconds: 1500), _kick);
      }
    });
  }

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _busySub;
  DateTime _lastKick = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ownScan = false;

  bool get bluetoothOn => FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
  bool get radioListening => _ownScan;

  @override
  String get name => 'phone';

  @override
  Stream<Observation> get observations => _out.stream;

  bool get active => _active;

  bool _boardAllows = true;
  bool get scanning => _active && _boardAllows;

  void setActive(bool on) {
    if (on == _active) return;
    _active = on;
    _apply();
  }

  void setBoardAllows(bool allow) {
    if (allow == _boardAllows) return;
    _boardAllows = allow;
    _apply();
  }

  void _apply() {
    _timer?.cancel();
    _timer = null;
    _wifiTimer?.cancel();
    _wifiTimer = null;
    if (!scanning) {
      _lastFed.clear();
      if (_ownScan && _foxTarget == null) FlutterBluePlus.stopScan();
    }
    if (scanning) {
      _kick();
      final duty = _duty;
      _timer = duty == null
          ? Timer.periodic(scanEvery, (_) => _refreshScan())
          : Timer.periodic(Duration(milliseconds: duty.every), (_) => _kick());
      if (canScanWifi && radioMask & 0x01 != 0) {
        _wifiKick();
        _wifiTimer = Timer.periodic(wifiEvery, (_) => _wifiKick());
      }
    }
    if (_foxTarget != null && canScanWifi && _wifiTimer == null) {
      _wifiTimer = Timer.periodic(wifiEvery, (_) => _wifiKick());
    }
    notifyListeners();
  }

  int radioMask = 0x03;

  ({int on, int every})? _duty;

  void setDuty(({int on, int every})? duty) {
    if (duty == _duty) return;
    _duty = duty;
    if (scanning) _apply();
  }

  void setRadioMask(int mask) {
    if (mask == radioMask) return;
    radioMask = mask;
    if (mask & 0x02 == 0 && _ownScan && _foxTarget == null) FlutterBluePlus.stopScan();
    _apply();
  }

  static const wifiEvery = Duration(seconds: 30);
  static bool get canScanWifi => Platform.isAndroid;
  Timer? _wifiTimer;
  void Function(String bssid, String ssid, int rssi, int channel, int authMode)? onWifi;

  static int wifiChannel(int mhz) {
    if (mhz == 2484) return 14;
    if (mhz >= 2412 && mhz < 2484) return (mhz - 2407) ~/ 5;
    if (mhz >= 5955 && mhz <= 7115) return (mhz - 5950) ~/ 5;
    if (mhz >= 5000 && mhz < 5955) return (mhz - 5000) ~/ 5;
    return 0;
  }

  static int wifiAuthMode(String caps) {
    final c = caps.toUpperCase();
    if (c.contains('SAE')) return 6;
    if (c.contains('EAP')) return 5;
    if (c.contains('WPA2') && c.contains('WPA-')) return 4;
    if (c.contains('WPA2') || c.contains('RSN')) return 3;
    if (c.contains('WPA')) return 2;
    if (c.contains('WEP')) return 1;
    return 0;
  }

  Future<void> _wifiKick() async {
    if ((!scanning && _foxTarget == null) || !canScanWifi) return;
    try {
      if (await WiFiScan.instance.canStartScan() == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      if (!scanning) return;
      if (await WiFiScan.instance.canGetScannedResults() != CanGetScannedResults.yes) return;
      final aps = await WiFiScan.instance.getScannedResults();
      final now = DateTime.now().millisecondsSinceEpoch;
      final fix = here?.call();
      for (final ap in aps) {
        final mac = MacUtil.normalize(ap.bssid);
        if (mac.isEmpty) continue;
        if (_isFoxTarget(mac)) _foxHit(ap.level, DateTime.now());
        if (!scanning || radioMask & 0x01 == 0) continue;
        final ch = wifiChannel(ap.frequency);
        final auth = wifiAuthMode(ap.capabilities);
        onWifi?.call(mac, ap.ssid, ap.level, ch, auth);
        _out.add(Observation(
          key: 'WIFI:$mac',
          kind: RadioKind.wifi,
          mac: mac,
          name: ap.ssid,
          rssi: ap.level,
          firstSeenMs: now,
          lastSeenMs: now,
          channel: ch,
          authMode: auth,
          hiddenSsid: ap.ssid.trim().isEmpty,
          isAp: true,
          gpsTrail: fix == null ? const [] : [GpsSample(now, fix.lat, fix.lon, ap.level)],
        ));
      }
    } on Exception catch (e) {
      DebugLog.log('CLASSIFY: phone wifi scan failed: $e');
    }
  }

  Future<void> _kick() async {
    if (!scanning || radioMask & 0x02 == 0 || FlutterBluePlus.isScanningNow) return;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    _lastKick = DateTime.now();
    _ownScan = true;
    notifyListeners();
    try {
      final duty = _duty;
      await FlutterBluePlus.startScan(
        timeout: duty == null ? null : Duration(milliseconds: duty.on),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } on Exception catch (e) {
      _ownScan = false;
      notifyListeners();
      DebugLog.log('CLASSIFY: phone scan failed: $e');
    }
  }

  static const scanRestartAfter = Duration(minutes: 25);

  void _refreshScan() {
    if (!scanning || _foxTarget != null) return;
    if (!FlutterBluePlus.isScanningNow) {
      _kick();
    } else if (_ownScan && DateTime.now().difference(_lastKick) >= scanRestartAfter) {
      FlutterBluePlus.stopScan();
    }
  }

  void Function(String mac, String name, int rssi, List<int> adv)? onDetection;
  final Map<String, int> _lastFed = {};

  static List<int> advBytes(AdvertisementData a) {
    final out = <int>[];
    void ad(int type, List<int> payload) {
      if (payload.length > 253) return;
      out..add(payload.length + 1)..add(type)..addAll(payload);
    }
    List<int> le(Guid g) {
      final s = g.str.replaceAll('-', '');
      return [for (var i = s.length - 2; i >= 0; i -= 2) int.parse(s.substring(i, i + 2), radix: 16)];
    }
    int uuidType(List<int> b, int t16, int t32, int t128) =>
        b.length == 2 ? t16 : (b.length == 4 ? t32 : t128);
    if (a.advName.isNotEmpty) ad(0x09, utf8.encode(a.advName));
    for (final u in a.serviceUuids) {
      final b = le(u);
      ad(uuidType(b, 0x03, 0x05, 0x07), b);
    }
    a.manufacturerData.forEach((id, data) => ad(0xFF, [id & 0xFF, (id >> 8) & 0xFF, ...data]));
    a.serviceData.forEach((u, data) {
      final b = le(u);
      ad(uuidType(b, 0x16, 0x20, 0x21), [...b, ...data]);
    });
    final ap = a.appearance;
    if (ap != null) ad(0x19, [ap & 0xFF, (ap >> 8) & 0xFF]);
    return out;
  }

  String? _foxTarget;
  DateTime? _foxSeen;
  Timer? _foxLostTimer;
  void Function(int rssi, int intervalMs)? onFoxRssi;

  bool _isFoxTarget(String id) {
    final fox = _foxTarget;
    if (fox == null) return false;
    if (id.toUpperCase() == fox.toUpperCase()) return true;
    final mac = MacUtil.normalize(id);
    return mac.isNotEmpty && mac == MacUtil.normalize(fox);
  }

  void _foxHit(int rssi, DateTime at) {
    final prev = _foxSeen;
    if (prev != null && !at.isAfter(prev)) return;
    _foxSeen = at;
    onFoxRssi?.call(rssi, prev == null ? 1 : at.difference(prev).inMilliseconds.clamp(1, 60000));
  }

  void setFoxTarget(String? id) {
    if (id == _foxTarget) return;
    _foxTarget = id;
    _foxSeen = null;
    _foxLostTimer?.cancel();
    _foxLostTimer = null;
    if (id == null) {
      if (FlutterBluePlus.isScanningNow) FlutterBluePlus.stopScan();
      _apply();
      return;
    }
    _timer?.cancel();
    _timer = null;
    _foxLostTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final seen = _foxSeen;
      if (seen != null && DateTime.now().difference(seen) > const Duration(seconds: 10)) {
        onFoxRssi?.call(-100, 0);
      }
    });
    if (canScanWifi && _wifiTimer == null) {
      _wifiKick();
      _wifiTimer = Timer.periodic(wifiEvery, (_) => _wifiKick());
    }
    _foxScan();
  }

  bool _foxStarting = false;

  Future<void> _foxScan() async {
    if (_foxTarget == null || _foxStarting) return;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    _foxStarting = true;
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      if (_foxTarget == null) return;
      _ownScan = true;
      notifyListeners();
      await FlutterBluePlus.startScan(continuousUpdates: true);
    } on Exception catch (e) {
      _ownScan = false;
      notifyListeners();
      DebugLog.log('CLASSIFY: phone foxhunt scan failed: $e');
    } finally {
      _foxStarting = false;
    }
  }

  void _onResults(List<ScanResult> results) {
    if (_foxTarget != null) {
      for (final r in results) {
        if (_isFoxTarget(r.device.remoteId.toString())) _foxHit(r.rssi, r.timeStamp);
      }
    }
    if (!scanning || radioMask & 0x02 == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final fix = here?.call();
    for (final r in results) {
      final id = r.device.remoteId.toString();
      final isMac = !Platform.isIOS && !Platform.isMacOS;
      final mac = isMac ? MacUtil.normalize(id) : '';
      final adv = r.advertisementData;
      final feed = onDetection;
      if (feed != null) {
        final last = _lastFed[id];
        if (last == null || now - last >= scanEvery.inMilliseconds) {
          _lastFed[id] = now;
          feed(isMac ? mac : id,
              adv.advName.isNotEmpty ? adv.advName : r.device.platformName,
              r.rssi, advBytes(adv));
        }
      }
      _out.add(Observation(
        key: 'BLE:${isMac ? mac : id}',
        kind: RadioKind.ble,
        mac: mac,
        name: adv.advName.isNotEmpty ? adv.advName : r.device.platformName,
        rssi: r.rssi,
        firstSeenMs: now,
        lastSeenMs: now,
        serviceUuids: [for (final u in adv.serviceUuids) u.str128.toUpperCase()],
        mfgRecords: [
          for (final e in adv.manufacturerData.entries) MfgRecord(e.key, _hex(e.value)),
        ],
        serviceData: [
          for (final e in adv.serviceData.entries) ServiceDataRecord(e.key.str128.toUpperCase(), _hex(e.value)),
        ],
        appearance: adv.appearance,
        gpsTrail: fix == null ? const [] : [GpsSample(now, fix.lat, fix.lon, r.rssi)],
      ));
    }
  }

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  @override
  void dispose() {
    _timer?.cancel();
    _wifiTimer?.cancel();
    _foxLostTimer?.cancel();
    _sub?.cancel();
    _adapterSub?.cancel();
    _busySub?.cancel();
    _out.close();
    super.dispose();
  }
}

class ClassifiedDevice {
  final Observation obs;
  final List<Signature> signatures;
  final Set<String> sources;
  final String? vendor;
  final String? baseVendor;
  final Guess? kin;
  const ClassifiedDevice(this.obs, this.signatures, this.sources, {this.vendor, this.baseVendor, this.kin});

  List<String> get signatureNames => [for (final s in signatures) s.name];
  Guess get ownGuess => DeviceExplain.guess(obs, signatureNames, vendor: vendor, baseVendor: baseVendor);
  Guess get guess {
    final own = ownGuess;
    final k = kin;
    return k != null && (own.confidence == Confidence.low || DeviceExplain.isGeneric(own)) ? k : own;
  }
  SignatureClass? get primaryClass => signatures.isEmpty ? null : signatures.first.kind;
}

class DeviceRegistry extends ChangeNotifier {
  static const catalogAsset = 'assets/fieldwatch-signatures-v2.json';
  static const maxDevices = 2000;
  static const _trailCap = 48;

  DeviceRegistry({SignatureEngine? engine, this.vendorOf}) : _engine = engine;

  final String? Function(String mac)? vendorOf;
  void Function(ClassifiedDevice)? onClassified;

  SignatureEngine? _engine;
  final _devices = <String, ClassifiedDevice>{};
  final _subs = <StreamSubscription<Observation>>[];
  final _sources = <ObservationSource>[];
  final pairingFlood = PairingFlood();
  final kinIndex = KinIndex();
  final _path = <GpsSample>[];
  Timer? _tick;
  bool _dirty = false;

  Iterable<ClassifiedDevice> get devices => _devices.values;
  int get count => _devices.length;
  bool get ready => _engine != null;
  List<GpsSample> get path => List.unmodifiable(_path);

  Future<void> loadCatalog() async {
    if (_engine != null) return;
    try {
      _engine = SignatureEngine(Signature.parseCatalog(await rootBundle.loadString(catalogAsset)));
      BtSigRegistry.load(
        await rootBundle.loadString(BtSigRegistry.companyAsset),
        await rootBundle.loadString(BtSigRegistry.memberAsset),
      );
      VendorClass.loadTable([for (final a in VendorClass.tableAssets) await rootBundle.loadString(a)]);
      DebugLog.log('CLASSIFY: catalog ${_engine!.signatures.length} signatures, '
          'SIG ${BtSigRegistry.companies.length} companies / ${BtSigRegistry.memberUuids.length} member UUIDs');
      notifyListeners();
    } on Exception catch (e) {
      DebugLog.log('CLASSIFY: catalog load failed: $e');
    }
  }

  void attach(ObservationSource source) {
    _sources.add(source);
    _subs.add(source.observations.listen((o) => ingest(o, source: source.name)));
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void recordPhoneFix(double lat, double lon, int atMs) {
    if (_path.isNotEmpty) {
      final last = _path.last;
      if (geoMeters(last.lat, last.lon, lat, lon) < 8) return;
    }
    _path.add(GpsSample(atMs, lat, lon));
    if (_path.length > 500) _path.removeRange(0, _path.length - 500);
  }

  void ingest(Observation o, {String source = ''}) {
    final now = o.lastSeenMs;
    final prev = _devices[o.key];
    if (prev == null && o.kind == RadioKind.ble) pairingFlood.consider(o, now);
    var trail = prev?.obs.gpsTrail ?? const <GpsSample>[];
    for (final s in o.gpsTrail) {
      trail = appendTrail(trail, s, _trailCap);
    }
    final merged = (prev == null ? o : prev.obs.merge(o)).withTrail(trail);
    final engine = _engine;
    final sigs = [
      ...?engine?.match(merged),
      if (engine != null && engine.hasClusters)
        ...engine.clusterMatch(merged, [for (final d in _devices.values) d.obs], now),
    ];
    final dev = _withKin(ClassifiedDevice(
      merged,
      sigs,
      {...?prev?.sources, if (source.isNotEmpty) source},
      vendor: prev?.vendor ?? (merged.mac.isEmpty ? null : vendorOf?.call(merged.mac)),
      baseVendor: prev?.baseVendor ?? _baseVendor(merged),
    ));
    _devices[o.key] = dev;
    if (prev == null ||
        prev.signatures.length != sigs.length ||
        prev.obs.mfgRecords.length != merged.mfgRecords.length ||
        prev.obs.serviceUuids.length != merged.serviceUuids.length ||
        prev.obs.detectorMethod != merged.detectorMethod) {
      onClassified?.call(dev);
    }
    if (_devices.length > maxDevices) _evictOldest();
    _dirty = true;
  }

  ClassifiedDevice _withKin(ClassifiedDevice base) {
    final o = base.obs;
    if (o.kind != RadioKind.ble) return base;
    kinIndex.learn(o, base.ownGuess);
    final kin = kinIndex.lookup(o);
    return kin == null
        ? base
        : ClassifiedDevice(o, base.signatures, base.sources,
            vendor: base.vendor, baseVendor: base.baseVendor, kin: kin);
  }

  String? _baseVendor(Observation o) {
    if (!o.isAp || !o.randomized) return null;
    final u = MacUtil.wifiOui24Universal(o.mac);
    return u == null ? null : vendorOf?.call(u + hexOnly(o.mac).substring(6));
  }

  static List<GpsSample> appendTrail(List<GpsSample> trail, GpsSample s, int cap) {
    if (trail.isNotEmpty) {
      final last = trail.last;
      final d = geoMeters(last.lat, last.lon, s.lat, s.lon);
      if (d < 8.0) return trail;
      if (d < 18.0 && s.atMs - last.atMs < 30000) return trail;
    }
    final next = [...trail, s];
    if (next.length <= cap) return next;
    final lastIdx = next.length - 1;
    final out = <GpsSample>[];
    for (var i = 0; i < cap; i++) {
      final p = next[(i * lastIdx) ~/ (cap - 1)];
      if (out.isEmpty || out.last.atMs != p.atMs) out.add(p);
    }
    if (out.last.atMs != next.last.atMs) out.add(next.last);
    return out;
  }

  void _evictOldest() {
    String? oldest;
    var at = 1 << 62;
    _devices.forEach((k, v) {
      if (v.obs.lastSeenMs < at) {
        at = v.obs.lastSeenMs;
        oldest = k;
      }
    });
    if (oldest != null) _devices.remove(oldest);
  }

  void _onTick() {
    final had = pairingFlood.notice;
    pairingFlood.tick(DateTime.now().millisecondsSinceEpoch);
    if (_dirty || !identical(had, pairingFlood.notice)) {
      _dirty = false;
      notifyListeners();
    }
  }

  bool withYou(ClassifiedDevice d) =>
      CoTravel.withYou(d.obs, CoTravelCtx.of(_path), DateTime.now().millisecondsSinceEpoch);

  TrackerKind? trackerKind(ClassifiedDevice d) => TrackerMatch.kind(d.obs, d.signatureNames);

  void clear() {
    _devices.clear();
    kinIndex.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final s in _sources) {
      s.dispose();
    }
    super.dispose();
  }
}

final phoneBleSourceProvider = ChangeNotifierProvider<PhoneBleSource>((ref) {
  final gps = ref.read(gpsProvider);
  final src = PhoneBleSource(here: () {
    final p = gps.lastPosition;
    return p == null ? null : GpsSample(0, p.latitude, p.longitude);
  });
  src.onDetection = ref.read(bleManagerProvider).addPhoneDetection;
  src.onWifi = ref.read(bleManagerProvider).addPhoneWifiDetection;
  src.onFoxRssi = ref.read(bleManagerProvider).addPhoneFoxRssi;
  bool sessionRunning() => ref.read(wardriveProvider).state == WardriveState.running;
  bool boardAllows(AppState s) => sessionRunning() || (s.isConnected && s.activeEngines != 0);
  void sync(AppState s) {
    final wd = ref.read(wardriveProvider);
    src.setDuty(s.isConnected ? (on: wd.bleScanDuration, every: wd.bleScanInterval) : null);
    src.setBoardAllows(boardAllows(s));
    src.setFoxTarget(s.foxhuntViaPhone ? s.foxhunterTarget : null);
  }
  sync(ref.read(appStateProvider));
  ref.listen<AppState>(appStateProvider, (_, s) => sync(s));
  ref.listen<WardriveController>(wardriveProvider, (_, _) => sync(ref.read(appStateProvider)));
  var wasScanning = false;
  src.addListener(() {
    if (src.scanning && !wasScanning) {
      gps.start().catchError((Object e) {
        DebugLog.log('GPS: start failed from phone scan: $e');
        return false;
      });
    }
    wasScanning = src.scanning;
  });
  return src;
});

final deviceRegistryProvider = ChangeNotifierProvider<DeviceRegistry>((ref) {
  final oui = ref.read(ouiLookupProvider);
  final notif = ref.read(notificationServiceProvider);
  final db = ref.read(databaseProvider);
  final gpsFix = ref.read(gpsProvider);
  final ignore = ref.read(ignoreListProvider);
  final geofence = ref.read(geofenceFilterProvider);
  final lastLogged = <String, int>{};
  final reg = DeviceRegistry(vendorOf: oui.lookup)
    ..onClassified = (d) {
      final trail = d.obs.gpsTrail;
      final pos = gpsFix.lastPosition;
      if (ignore.shouldSuppress(mac: d.obs.mac, ssid: d.obs.name, isBle: d.obs.kind == RadioKind.ble) ||
          geofence.isExcludedNullable(
            trail.isNotEmpty ? trail.last.lat : pos?.latitude,
            trail.isNotEmpty ? trail.last.lon : pos?.longitude,
          )) {
        return;
      }
      notif.onClassified(d);
      final alert = classAlertOf(d, notif.classAlerts, flock: notif.flockEnabled);
      if (alert == null) return;
      final mac = d.obs.mac.isNotEmpty ? d.obs.mac.toUpperCase() : d.obs.key;
      final key = '$mac|${alert.kind}';
      final now = DateTime.now().millisecondsSinceEpoch;
      final prev = lastLogged[key];
      if (prev != null && now - prev < notif.cooldownSeconds * 1000) return;
      lastLogged[key] = now;
      final (title, reason, _) = NotificationService.classNotificationText(d, alert);
      db.insertClassAlert(
        macAddress: mac,
        deviceName: d.obs.name,
        alertClass: alert.kind,
        title: title,
        reason: reason,
        isBle: d.obs.kind == RadioKind.ble,
        rssi: d.obs.rssi,
        channel: d.obs.channel,
        alertedAt: now,
        latitude: trail.isNotEmpty ? trail.last.lat : pos?.latitude,
        longitude: trail.isNotEmpty ? trail.last.lon : pos?.longitude,
      ).catchError((Object e) => DebugLog.log('CLASSIFY: alert log failed: $e'));
    };
  reg.loadCatalog();
  reg.attach(EspDetectionSource(ref.read(bleManagerProvider).detections));
  reg.attach(ref.read(phoneBleSourceProvider));
  final gps = ref.read(gpsProvider);
  final sub = gps.positionStream.listen(
    (p) => reg.recordPhoneFix(p.latitude, p.longitude, DateTime.now().millisecondsSinceEpoch),
  );
  ref.onDispose(sub.cancel);
  return reg;
});
