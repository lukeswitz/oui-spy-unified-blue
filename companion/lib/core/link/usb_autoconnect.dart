import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/link_net.dart';
import 'package:oui_spy/core/link/usb_serial.dart';
import 'package:uuid/uuid.dart';

class UsbAutoConnect {
  UsbAutoConnect(this._ble);

  static const netPollEvery = Duration(seconds: 3);
  static const netRetryAfter = Duration(seconds: 30);

  final BleManager _ble;
  final _devices = StreamController<List<UsbSerialDevice>>.broadcast();
  final _netTargets = StreamController<NetLinkTarget?>.broadcast();
  StreamSubscription<UsbSerialEvent>? _sub;
  Timer? _netTimer;
  List<UsbSerialDevice> _attached = const [];
  NetLinkTarget? _net;
  DateTime? _netFailedAt;
  bool _busy = false;

  List<UsbSerialDevice> get attached => _attached;
  Stream<List<UsbSerialDevice>> get devices => _devices.stream;
  NetLinkTarget? get netTarget => _net;
  Stream<NetLinkTarget?> get netTargets => _netTargets.stream;

  void start() {
    if (UsbSerial.supported) {
      _sub = UsbSerial.events.listen((e) async {
        await refresh();
        if (e.attached) await connect(e.device);
      });
    }
    if (NetLinkTarget.supported) {
      _netTimer = Timer.periodic(netPollEvery, (_) => _pollNet());
    }
  }

  Future<List<UsbSerialDevice>> refresh() async {
    try {
      _attached = await UsbSerial.list();
    } on PlatformException catch (e) {
      DebugLog.log('USB: list failed ${e.message}');
      _attached = const [];
    }
    _devices.add(_attached);
    return _attached;
  }

  Future<bool> connectFirstAttached() async {
    final list = await refresh();
    if (list.isNotEmpty) return connect(list.first);
    final net = await _findNet();
    return net != null && await connectNet(net);
  }

  Future<bool> connect(UsbSerialDevice device, {bool replaceBle = false}) async {
    if (_busy || _ble.isUsbLinked) return false;
    if (_ble.isConnected && !replaceBle) {
      DebugLog.log('USB: ${device.vidPid} attached while BLE is connected — left for the user to pick');
      return false;
    }
    _busy = true;
    try {
      await _ble.connectUsb(device, sessionId: const Uuid().v4());
      return _ble.isUsbLinked;
    } on Exception catch (e) {
      DebugLog.log('USB: connect ${device.vidPid} failed: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<bool> connectNet(NetLinkTarget target, {bool replaceBle = false}) async {
    if (_busy || _ble.isUsbLinked) return false;
    if (_ble.isConnected && !replaceBle) return false;
    _busy = true;
    try {
      await _ble.connectNetLink(target, sessionId: const Uuid().v4());
      _netFailedAt = null;
      return _ble.isUsbLinked;
    } on Exception catch (e) {
      DebugLog.log('USB: net link ${target.label} failed: $e');
      _netFailedAt = DateTime.now();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<NetLinkTarget?> _findNet() async {
    NetLinkTarget? found;
    try {
      found = await NetLinkTarget.find();
    } on SocketException catch (e) {
      DebugLog.log('USB: interface list failed ${e.message}');
    }
    if ((found == null) != (_net == null)) _netTargets.add(found);
    _net = found;
    return found;
  }

  Future<void> _pollNet() async {
    final target = await _findNet();
    if (target == null || _busy || _ble.isConnected || _ble.isUsbLinked) return;
    final failed = _netFailedAt;
    if (failed != null && DateTime.now().difference(failed) < netRetryAfter) return;
    await connectNet(target);
  }

  void dispose() {
    _sub?.cancel();
    _netTimer?.cancel();
    _devices.close();
    _netTargets.close();
  }
}

final usbAutoConnectProvider = Provider<UsbAutoConnect>((ref) {
  final ac = UsbAutoConnect(ref.read(bleManagerProvider));
  ac.start();
  ref.onDispose(ac.dispose);
  return ac;
});
