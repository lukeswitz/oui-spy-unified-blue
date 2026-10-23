import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';

enum WifiAdapterState { absent, present, starting, running, error }

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
  int _apCount = 0;
  final Set<String> _seenBssids = {};

  List<WifiAdapterDevice> get devices => _list;
  WifiAdapterState get state => _current;
  String get status => _status;
  int get apCount => _apCount;
  Stream<WifiAdapterState> get stateStream => _state.stream;
  Stream<List<WifiAdapterDevice>> get deviceStream => _devices.stream;

  void init() {
    _attachSub ??= WifiAdapter.attachEvents.listen(_onAttach);
    refresh();
  }

  Future<void> _onAttach(WifiAdapterAttach e) async {
    if (e.attached) {
      await refresh();
    } else {
      await refresh();
      final gone = _list.isEmpty;
      final active = _current == WifiAdapterState.running || _current == WifiAdapterState.starting;
      if (gone && active) await stop();
    }
  }

  Future<List<WifiAdapterDevice>> refresh() async {
    try {
      _list = await WifiAdapter.list();
    } on PlatformException catch (e) {
      DebugLog.log('WIFIADAPTER: list failed ${e.message}');
      _list = const [];
    }
    _devices.add(_list);
    if (_current == WifiAdapterState.absent && _list.isNotEmpty) _set(WifiAdapterState.present);
    if (_current == WifiAdapterState.present && _list.isEmpty) _set(WifiAdapterState.absent);
    return _list;
  }

  Future<bool> start(WifiAdapterDevice device, {int radioMask = 0x01}) async {
    _set(WifiAdapterState.starting);
    _sub?.cancel();
    _sub = WifiAdapter.events.listen(_onEvent, onError: (Object e) {
      _status = e.toString();
      _set(WifiAdapterState.error);
    });
    try {
      final ok = await WifiAdapter.start(device, radioMask: radioMask);
      if (!ok) {
        _set(WifiAdapterState.error);
        await _sub?.cancel();
        _sub = null;
      }
      return ok;
    } on PlatformException catch (e) {
      DebugLog.log('WIFIADAPTER: start failed ${e.message}');
      _status = e.message ?? 'start failed';
      _set(WifiAdapterState.error);
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _apCount = 0;
    await WifiAdapter.stop();
    _set(_list.isEmpty ? WifiAdapterState.absent : WifiAdapterState.present);
  }

  void _onEvent(WifiAdapterEvent e) {
    if (e.status != null) {
      _status = e.status!;
      DebugLog.log('WIFIADAPTER: ${e.status}');
      if (_status.contains('receiver live')) _set(WifiAdapterState.running);
      if (_status.contains('MT7612U:') && !_status.contains('live') && !_status.contains('running')) {
        _set(WifiAdapterState.error);
      }
    }
    final aps = e.aps;
    if (aps != null && aps.isNotEmpty) {
      if (_current != WifiAdapterState.running) _set(WifiAdapterState.running);
      for (final ap in aps) {
        _seenBssids.add(ap.bssid);
      }
      _apCount = _seenBssids.length;
      DebugLog.log('WIFIADAPTER: batch ${aps.length} fresh, ${_seenBssids.length} unique aps');
      for (final ap in aps) {
        _ble.addPhoneWifiDetection(ap.bssid, ap.ssid ?? '', ap.rssi, ap.channel, ap.authMode,
            nodeId: BleManager.usbWifiNodeId, client: ap.client);
      }
    }
    final ble = e.bleReports;
    if (ble != null && ble.isNotEmpty) {
      if (_current != WifiAdapterState.running) _set(WifiAdapterState.running);
      for (final r in ble) {
        _ble.addPhoneDetection(r.mac, r.name, r.rssi, r.adv, nodeId: BleManager.usbBleNodeId);
      }
    }
  }

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

final usbAdapterScanProvider = StateProvider<bool>((ref) => true);
