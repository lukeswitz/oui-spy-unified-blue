import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';

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
  List<WifiAdapterDevice> _list = const [];
  WifiAdapterState _current = WifiAdapterState.absent;
  String _status = '';
  final Map<String, WifiAdapterState> _deviceState = {};
  final Map<String, Set<String>> _deviceBssids = {};
  final Set<String> _seenBssids = {};

  List<WifiAdapterDevice> get devices => _list;
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
    refresh().then((list) {
      if (list.isNotEmpty) WifiAdapter.requestPermission();
    });
  }

  Future<void> _onAttach(WifiAdapterAttach e) async {
    await refresh();
    if (!e.attached && isActive(e.device.id)) await stop(id: e.device.id);
  }

  Future<List<WifiAdapterDevice>> refresh() async {
    try {
      _list = await WifiAdapter.list();
    } on PlatformException catch (e) {
      DebugLog.log('WIFIADAPTER: list failed ${e.message}');
      _list = const [];
    }
    _devices.add(_list);
    _update();
    return _list;
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
    final aps = e.aps;
    if (aps != null && aps.isNotEmpty) {
      if (id != null) _markRunning(id);
      final mine = id == null ? null : _deviceBssids.putIfAbsent(id, () => <String>{});
      for (final ap in aps) {
        _seenBssids.add(ap.bssid);
        mine?.add(ap.bssid);
      }
      DebugLog.log('WIFIADAPTER: batch ${aps.length} fresh, ${mine?.length ?? 0} unique aps on $id, '
          '${_seenBssids.length} total');
      for (final ap in aps) {
        _ble.addPhoneWifiDetection(ap.bssid, ap.ssid ?? '', ap.rssi, ap.channel, ap.authMode,
            nodeId: BleManager.usbWifiNodeId, client: ap.client);
      }
    }
    final ble = e.bleReports;
    if (ble != null && ble.isNotEmpty) {
      if (id != null) _markRunning(id);
      for (final r in ble) {
        _ble.addPhoneDetection(r.mac, r.name, r.rssi, r.adv, nodeId: BleManager.usbBleNodeId);
      }
    }
  }

  void _markRunning(String id) {
    if (_deviceState[id] == WifiAdapterState.running) return;
    _deviceState[id] = WifiAdapterState.running;
    _update();
  }

  void _update() => _set(aggregateAdapterState(_deviceState.values, attached: _list.isNotEmpty));

  void _set(WifiAdapterState s) {
    _current = s;
    _state.add(s);
  }

  void dispose() {
    _sub?.cancel();
    _attachSub?.cancel();
    _state.close();
    _devices.close();
  }
}

final wifiAdapterControllerProvider = Provider<WifiAdapterController>((ref) {
  final c = WifiAdapterController(ref.read(bleManagerProvider));
  c.init();
  ref.onDispose(c.dispose);
  return c;
});

final wifiAdapterStateProvider = StreamProvider<WifiAdapterState>((ref) {
  return ref.watch(wifiAdapterControllerProvider).stateStream;
});

final usbAdapterOffProvider = StateProvider<Set<String>>((ref) => const {});
