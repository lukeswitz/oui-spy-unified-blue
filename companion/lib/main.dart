import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/app.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugLog.init();

  // System UI overlay adapts per-theme in MaterialApp; set transparent here.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  final container = ProviderContainer();

  // Force AppState to initialize before auto-connect so it catches
  // the connection state stream events (prevents race condition where
  // auto-connect completes before AppState subscribes).
  container.read(appStateProvider);

  _autoConnect(container);

  runApp(UncontrolledProviderScope(
    container: container,
    child: const OuiSpyApp(),
  ));
}

Future<void> _autoConnect(ProviderContainer container) async {
  try {
    await Future.delayed(const Duration(seconds: 2));
    final adapterState = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);

    if (adapterState != BluetoothAdapterState.on) {
      DebugLog.log('AUTO: BLE not on ($adapterState)');
      return;
    }

    final connected = FlutterBluePlus.connectedDevices;
    for (final device in connected) {
      if (device.platformName.contains('OUI-SPY')) {
        DebugLog.log('AUTO: reconnecting to system-remembered ${device.platformName}');
        final ble = container.read(bleManagerProvider);
        await ble.connect(device, sessionId: const Uuid().v4());
        ble.markAsPrimary();
        _cleanupPrimaryNode(container, device.remoteId.toString());
        return;
      }
    }

    DebugLog.log('AUTO: scanning (no filter, 8s)...');

    final completer = Completer<BluetoothDevice?>();

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        DebugLog.log('AUTO: saw device: "$name" ${r.device.remoteId}');
        if (name.contains('OUI-SPY') || name.contains('OUI')) {
          if (!completer.isCompleted) {
            DebugLog.log('AUTO: MATCH: $name');
            FlutterBluePlus.stopScan();
            completer.complete(r.device);
          }
        }
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    final found = await completer.future
        .timeout(const Duration(seconds: 10), onTimeout: () => null);

    await sub.cancel();
    await FlutterBluePlus.stopScan();

    if (found != null) {
      DebugLog.log('AUTO: connecting to ${found.platformName}...');
      final ble = container.read(bleManagerProvider);
      await ble.connect(found, sessionId: const Uuid().v4());
      ble.markAsPrimary();
      _cleanupPrimaryNode(container, found.remoteId.toString());
      DebugLog.log('AUTO: connected');
    } else {
      DebugLog.log('AUTO: no OUI-SPY found after scan');
    }
  } catch (e) {
    DebugLog.log('AUTO: failed: $e');
  }
}

void _cleanupPrimaryNode(ProviderContainer container, String deviceId) {
  final db = container.read(databaseProvider);
  db.deleteNode(deviceId);
  DebugLog.log('AUTO: cleaned up primary device from nodes table');
}

