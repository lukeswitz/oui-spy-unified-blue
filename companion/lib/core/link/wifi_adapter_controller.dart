import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';
import 'package:oui_spy/core/wardrive_state.dart';

enum WifiAdapterState { absent, present, starting, running, error }

WifiAdapterState aggregateAdapterState(Iterable<WifiAdapterState> perDevice, {required bool attached}) {
  final s = perDevice.toSet();
  if (s.contains(WifiAdapterState.running)) return WifiAdapterState.running;
  if (s.contains(WifiAdapterState.starting)) return WifiAdapterState.starting;
  if (s.contains(WifiAdapterState.error)) return WifiAdapterState.error;
  return attached ? WifiAdapterState.present : WifiAdapterState.absent;
}

class WifiAdapterController {
  WifiAdapterController(this._ble);

  final BleManager _ble;
  final _state = StreamController<WifiAdapterState>.broadcast();
  final _devices = StreamController<List<WifiAdapterDevice>>.broadcast();
  StreamSubscription<WifiAdapterEvent>? _sub;
  StreamSubscription<WifiAdapterAttach>? _attachSub;
  StreamSubscription<NodeConnectionState>? _linkSub;
  List<WifiAdapterDevice> _list = const [];
  WifiAdapterState _current = WifiAdapterState.absent;
  String _status = '';
  final Map<String, WifiAdapterState> _deviceState = {};
  final Map<String, Set<String>> _deviceBssids = {};
  final Set<String> _seenBssids = {};

  List<WifiAdapterDevice> get devices {
    final boards = {_ble.usbDevice?.id, _ble.lastUsbDevice?.id};
    return [for (final d in _list) if (!boards.contains(d.id)) d];
  }
  WifiAdapterState get state => _current;
  String get status => _status;
  int get apCount => _seenBssids.length;
  WifiAdapterState stateOf(String id) =>
      _deviceState[id] ?? (_list.any((d) => d.id == id) ? WifiAdapterState.present : WifiAdapterState.absent);
  bool isActive(String id) {
    final s = stateOf(id);
    return s == WifiAdapterState.running || s == WifiAdapterState.starting;
  }

  int apCountOf(String id) => _deviceBssids[id]?.length ?? 0;
  Stream<WifiAdapterState> get stateStream => _state.stream;
  Stream<List<WifiAdapterDevice>> get deviceStream => _devices.stream;

  void init() {
    _attachSub ??= WifiAdapter.attachEvents.listen(_onAttach);
    _linkSub ??= _ble.connectionState.listen((_) {
      _devices.add(devices);
      _update();
    });
    refresh().then((list) {
      if (list.isNotEmpty) WifiAdapter.requestPermission();
    });
  }

  Future<void> _onAttach(WifiAdapterAttach e) async {
    await refresh();
    if (!e.attached && _deviceState.containsKey(e.device.id)) await stop(id: e.device.id);
  }

  Future<List<WifiAdapterDevice>> refresh() async {
    try {
      _list = await WifiAdapter.list();
    } on PlatformException catch (e) {
      DebugLog.log('WIFIADAPTER: list failed ${e.message}');
      _list = const [];
    }
    _devices.add(devices);
    _update();
    return devices;
  }

  Future<bool> start(WifiAdapterDevice device, {int radioMask = 0x01}) async {
    _sub ??= WifiAdapter.events.listen(_onEvent, onError: (Object e) {
      _status = e.toString();
      for (final id in _deviceState.keys.toList()) {
        if (isActive(id)) _deviceState[id] = WifiAdapterState.error;
      }
      _update();
    });
    if (isActive(device.id)) return true;
    _deviceState[device.id] = WifiAdapterState.starting;
    _update();
    try {
      final ok = await WifiAdapter.start(device, radioMask: radioMask);
      if (!ok) {
        _deviceState[device.id] = WifiAdapterState.error;
        _update();
      }
      return ok;
    } on PlatformException catch (e) {
      DebugLog.log('WIFIADAPTER: start failed ${e.message}');
      _status = e.message ?? 'start failed';
      _deviceState[device.id] = WifiAdapterState.error;
      _update();
      return false;
    }
  }

  Future<void> stop({String? id}) async {
    await WifiAdapter.stop(id: id);
    if (id == null) {
      _deviceState.clear();
      _deviceBssids.clear();
      _seenBssids.clear();
    } else {
      _deviceState.remove(id);
      _deviceBssids.remove(id);
      _seenBssids
        ..clear()
        ..addAll(_deviceBssids.values.expand((s) => s));
    }
    _update();
  }

  void _onEvent(WifiAdapterEvent e) {
    final id = e.id;
    if (e.stopped && id != null) {
      if (isActive(id)) _deviceState[id] = WifiAdapterState.error;
      DebugLog.log('WIFIADAPTER: $id stopped');
      _update();
      return;
    }
    if (id != null && !_deviceState.containsKey(id)) return;
    if (e.status != null) {
      _status = e.status!;
      DebugLog.log('WIFIADAPTER: ${e.status}');
      if (id != null && _status.contains('receiver live')) _markRunning(id);
    }
    final aps = e.aps?.where((ap) => !(ap.client && isRandomizedMac(ap.bssid))).toList();
    if (aps != null && aps.isNotEmpty) {
      if (id != null) _markRunning(id);
      final mine = id == null ? null : _deviceBssids.putIfAbsent(id, () => <String>{});
      for (final ap in aps) {
        if (ap.client) continue;
        _seenBssids.add(ap.bssid);
        mine?.add(ap.bssid);
      }
      DebugLog.log('WIFIADAPTER: batch ${aps.length} fresh, ${mine?.length ?? 0} unique aps on $id, '
          '${_seenBssids.length} total, ${aps.where((a) => a.client).length} clients, ${aps.where((a) => a.ap != null).length} linked');
      final node = _nodeId(BleManager.usbWifiNodeId, id);
      for (final ap in aps) {
        _ble.addPhoneWifiDetection(ap.bssid, ap.ssid ?? '', ap.rssi, ap.channel, ap.authMode,
            nodeId: node, client: ap.client, ap: ap.ap);
      }
    }
    final ble = e.bleReports;
    if (ble != null && ble.isNotEmpty) {
      if (id != null) _markRunning(id);
      final node = _nodeId(BleManager.usbBleNodeId, id);
      for (final r in ble) {
        _ble.addPhoneDetection(r.mac, r.name, r.rssi, r.adv, nodeId: node);
      }
    }
  }

  String _nodeId(String prefix, String? id) {
    if (id == null) return prefix;
    final d = _list.where((x) => x.id == id).firstOrNull;
    final bus = id.split('/').last;
    if (d == null) return '$prefix:$bus';
    final dup = _list.where((x) => x.title == d.title).length > 1;
    return '$prefix:${dup ? '${d.title} $bus' : d.title}';
  }

  Future<void> startSelected({required Set<String> off, required Map<String, int> picked, required int mask, String? only}) async {
    for (final d in devices) {
      if (only != null && d.id != only) continue;
      if (off.contains(d.id) || isActive(d.id)) continue;
      await start(d, radioMask: picked[d.id] ?? mask);
    }
  }

  void _markRunning(String id) {
    if (_deviceState[id] == WifiAdapterState.running) return;
    _deviceState[id] = WifiAdapterState.running;
    _update();
  }

  void _update() => _set(aggregateAdapterState(_deviceState.values, attached: devices.isNotEmpty));

  void _set(WifiAdapterState s) {
    _current = s;
    _state.add(s);
  }

  void dispose() {
    _sub?.cancel();
    _attachSub?.cancel();
    _linkSub?.cancel();
    _state.close();
    _devices.close();
  }
}

final wifiAdapterControllerProvider = Provider<WifiAdapterController>((ref) {
  final c = WifiAdapterController(ref.read(bleManagerProvider));
  c.init();
  Future<void> startForSession() => c.startSelected(
        off: ref.read(usbAdapterOffProvider),
        picked: ref.read(usbAdapterRadioProvider),
        mask: ref.read(wardriveProvider).radioBitmask,
      );
  var running = ref.read(wardriveProvider).isRunning;
  if (running) startForSession();
  ref.listen<WardriveController>(wardriveProvider, (_, wd) {
    if (wd.isRunning == running) return;
    running = wd.isRunning;
    running ? startForSession() : c.stop();
  });
  final devSub = c.deviceStream.listen((_) {
    if (running) startForSession();
  });
  ref.onDispose(() {
    devSub.cancel();
    c.dispose();
  });
  return c;
});

final wifiAdapterStateProvider = StreamProvider<WifiAdapterState>((ref) {
  return ref.watch(wifiAdapterControllerProvider).stateStream;
});

final wifiAdapterDevicesProvider = StreamProvider<List<WifiAdapterDevice>>((ref) {
  return ref.watch(wifiAdapterControllerProvider).deviceStream;
});

final usbAdapterOffProvider = StateProvider<Set<String>>((ref) => const {});

final usbAdapterRadioProvider = StateProvider<Map<String, int>>((ref) => const {});

bool isRandomizedMac(String mac) {
  final b = mac.length >= 2 ? int.tryParse(mac.substring(0, 2), radix: 16) : null;
  return b != null && b & 0x02 != 0;
}

bool usbAdapterHasBle(WifiAdapterDevice d) => d.vendorId == 0x0e8d && d.productId == 0x7961;
