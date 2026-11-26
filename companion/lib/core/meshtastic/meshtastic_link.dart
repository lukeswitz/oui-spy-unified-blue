// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// A radio found while scanning.
class MtRadioFound {
  const MtRadioFound({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;
}

/// One open connection to a Meshtastic radio: the three characteristics of its Bluetooth service.
abstract class MeshtasticLink {
  /// Fires when the radio has new packets waiting (the `fromNum` characteristic notifies).
  Stream<void> get fromNum;

  /// The next packet for the phone, or empty when the queue is empty (the `fromRadio` characteristic).
  Future<Uint8List> readFromRadio();

  /// Sends one ToRadio message (the `toRadio` characteristic).
  Future<void> writeToRadio(Uint8List bytes);

  /// Completes when the radio goes away.
  Future<void> get closed;

  Future<void> close();
}

abstract class MeshtasticBle {
  Future<List<MtRadioFound>> scan({Duration timeout});

  Future<MeshtasticLink> open(String id);
}

/// The Meshtastic Bluetooth service, from meshtastic.org/docs/development/device/client-api.
class MeshtasticUuids {
  const MeshtasticUuids._();

  static final service = Guid('6ba1b218-15a8-461f-9fa8-5dcae273eafd');
  static final toRadio = Guid('f75c76d2-129e-4dad-a1dd-7866124401e7');
  static final fromRadio = Guid('2c55e69e-4993-11ed-b878-0242ac120002');
  static final fromNum = Guid('ed9da18c-a800-4f66-a670-aa7547e34453');
}

class FbpMeshtasticBle implements MeshtasticBle {
  FbpMeshtasticBle({this.connectWait = const Duration(seconds: 15)});

  final Duration connectWait;

  @override
  Future<List<MtRadioFound>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    final found = <String, MtRadioFound>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (!r.advertisementData.serviceUuids.contains(MeshtasticUuids.service)) continue;
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        found[r.device.remoteId.str] = MtRadioFound(id: r.device.remoteId.str, name: name, rssi: r.rssi);
      }
    });
    try {
      await FlutterBluePlus.startScan(withServices: [MeshtasticUuids.service], timeout: timeout);
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } finally {
      await sub.cancel();
    }
    return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  @override
  Future<MeshtasticLink> open(String id) async {
    final device = BluetoothDevice.fromId(id);
    await device.connect(autoConnect: true, mtu: null);
    try {
      await device.connectionState
          .firstWhere((s) => s == BluetoothConnectionState.connected)
          .timeout(connectWait);
    } on TimeoutException {
      await device.disconnect();
      throw StateError('no answer in ${connectWait.inSeconds} s');
    }
    try {
      if (Platform.isAndroid) await device.createBond(timeout: 120);
      try {
        await device.requestMtu(512);
      } on FlutterBluePlusException {
        // iOS negotiates by itself
      }
      final services = await device.discoverServices();
      final service = services.where((s) => s.uuid == MeshtasticUuids.service).firstOrNull;
      if (service == null) throw StateError('not a Meshtastic radio');
      BluetoothCharacteristic chr(Guid u) =>
          service.characteristics.firstWhere((c) => c.uuid == u, orElse: () => throw StateError('radio lacks $u'));
      final link = _FbpLink(device, chr(MeshtasticUuids.toRadio), chr(MeshtasticUuids.fromRadio),
          chr(MeshtasticUuids.fromNum));
      await link.start();
      return link;
    } catch (_) {
      await device.disconnect();
      rethrow;
    }
  }
}

class _FbpLink implements MeshtasticLink {
  _FbpLink(this._device, this._to, this._from, this._num);

  final BluetoothDevice _device;
  final BluetoothCharacteristic _to, _from, _num;
  final _notify = StreamController<void>.broadcast();
  final _closed = Completer<void>();
  StreamSubscription<List<int>>? _numSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;

  Future<void> start() async {
    _stateSub = _device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_closed.isCompleted) _closed.complete();
    });
    _numSub = _num.onValueReceived.listen((_) => _notify.add(null));
    await _num.setNotifyValue(true, timeout: 120);
  }

  @override
  Stream<void> get fromNum => _notify.stream;

  @override
  Future<Uint8List> readFromRadio() async => Uint8List.fromList(await _from.read());

  @override
  Future<void> writeToRadio(Uint8List bytes) => _to.write(bytes);

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() async {
    await _numSub?.cancel();
    await _stateSub?.cancel();
    await _notify.close();
    await _device.disconnect();
    if (!_closed.isCompleted) _closed.complete();
  }
}
