import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';

/// Flock-BLE notification wire layout (firmware ble_gatt.cpp packDetection):
///   [0]      engine_id
///   [1..6]   mac
///   [7]      rssi        [8]  channel
///   [9..12]  timestamp   [13] method
///   [14..18] source_node_id
///   ext base = 19:
///     +0      is_raven
///     +1..16  raven_fw
///     +17     auth_mode
///     +18..49 name
///     +50     sig_mask
List<int> _flockPacket({
  required String name,
  int sigMask = 0,
  bool includeSigMask = true,
  int method = 1,
  bool isRaven = false,
  String ravenFw = '',
}) {
  final buf = List<int>.filled(includeSigMask ? 70 : 69, 0);
  buf[0] = 1; // ENGINE_FLOCK_BLE
  for (int i = 0; i < 6; i++) {
    buf[1 + i] = 0x10 + i;
  }
  buf[7] = 0xA6; // -90
  buf[8] = 0;
  buf[13] = method;
  buf[19] = isRaven ? 1 : 0;
  for (int i = 0; i < ravenFw.length && i < 15; i++) {
    buf[20 + i] = ravenFw.codeUnitAt(i);
  }
  buf[36] = 0;
  for (int i = 0; i < name.length && i < 31; i++) {
    buf[37 + i] = name.codeUnitAt(i);
  }
  if (includeSigMask) buf[69] = sigMask;
  return buf;
}

Detection _decode(List<int> data) => BleProtocol.decodeDetection(
      data,
      sessionId: 's',
      nodeId: 'n',
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  test('bare serial name survives the wire verbatim', () {
    final d = _decode(_flockPacket(name: '0102000000'));
    expect(d.engine, Engine.flockBle);
    expect(d.deviceName, '0102000000');
    expect(d.method, 'name_match');
  });

  test('validated requires serial + XUNTONG mfg + TN together', () {
    const mask =
        FlockSignal.serial | FlockSignal.mfg | FlockSignal.tn;
    final d = _decode(_flockPacket(name: '7202302200', sigMask: mask));
    expect(d.flock!.signals, mask);
    expect(d.flock!.isValidated, true);
    expect(d.flock!.hasSignal(FlockSignal.mfg), true);
  });

  test('serial name without corroboration is not validated', () {
    final d = _decode(
        _flockPacket(name: '0102000000', sigMask: FlockSignal.serial));
    expect(d.flock!.isValidated, false);
    expect(d.deviceName, '0102000000');
  });

  test('mfg without TN serial is not validated', () {
    final d = _decode(_flockPacket(
        name: '0102000000',
        sigMask: FlockSignal.serial | FlockSignal.mfg));
    expect(d.flock!.isValidated, false);
  });

  test('named-pattern hits stay standalone and unvalidated', () {
    final d = _decode(
        _flockPacket(name: 'Penguin-1234567890', sigMask: FlockSignal.name));
    expect(d.deviceName, 'Penguin-1234567890');
    expect(d.flock!.hasSignal(FlockSignal.name), true);
    expect(d.flock!.isValidated, false);
  });

  test('pre-sig-mask firmware (69B) still decodes, signals default 0', () {
    final d = _decode(
        _flockPacket(name: 'FS Ext Battery', includeSigMask: false));
    expect(d.deviceName, 'FS Ext Battery');
    expect(d.flock!.signals, 0);
    expect(d.flock!.isValidated, false);
  });

  test('raven fields are unaffected by the appended byte', () {
    final d = _decode(_flockPacket(
      name: 'Raven',
      isRaven: true,
      ravenFw: '1.2+',
      method: 3,
      sigMask: FlockSignal.ravenUuid,
    ));
    expect(d.flock!.isRaven, true);
    expect(d.flock!.ravenFirmware, '1.2+');
    expect(d.method, 'raven_uuid');
    expect(d.flock!.hasSignal(FlockSignal.ravenUuid), true);
  });

  test('flock GATT uuid decodes as BLE, high confidence', () {
    final d = _decode(
        _flockPacket(name: '', method: 4, sigMask: FlockSignal.gatt));
    expect(d.method, 'gatt_uuid');
    expect(isBleMethod(d.method), true);
    expect(isWifiMethod(d.method), false);
    expect(d.flock!.isRaven, false);
    expect(d.flock!.confidence(d.method), FlockConfidence.high);
    expect(d.flock!.confidence(d.method).label(d.method),
        'High (Flock GATT UUID)');
  });

  test('nordic DFU decodes as BLE, suspected confidence', () {
    final d = _decode(
        _flockPacket(name: 'DfuTarg', method: 5, sigMask: FlockSignal.dfu));
    expect(d.method, 'nordic_dfu');
    expect(isBleMethod(d.method), true);
    expect(isWifiMethod(d.method), false);
    expect(d.flock!.confidence(d.method), FlockConfidence.suspected);
    expect(d.flock!.isValidated, false);
  });

  test('new bits do not collide with validated set', () {
    expect(FlockSignal.validated & (FlockSignal.gatt | FlockSignal.dfu), 0);
    final d = _decode(_flockPacket(
        name: '',
        sigMask: FlockSignal.gatt | FlockSignal.dfu | FlockSignal.ravenUuid));
    expect(d.flock!.signals, 0xE0);
  });
}
