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
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Load OUI vendor database (async, non-blocking)
  container.read(ouiLookupProvider).init();

  // Initialize notification service (async, non-blocking)
  container.read(notificationServiceProvider).init();

  // Initialize Live Activity service (iOS Dynamic Island, non-blocking)
  container.read(liveActivityServiceProvider).init();

  container.read(appStateProvider);

  _forceCleanBleState();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const OuiSpyApp(),
  ));
}

Future<void> _forceCleanBleState() async {
  try {
    await Future.delayed(const Duration(milliseconds: 500));
    final connected = FlutterBluePlus.connectedDevices;
    for (final d in connected) {
      try {
        await d.disconnect(queue: false);
        DebugLog.log('BLE: force-disconnect on launch ${d.platformName}');
      } on Exception catch (e) {
        DebugLog.log('BLE: force-disconnect error $e');
      }
    }
  } on Exception catch (e) {
    DebugLog.log('BLE: force-clean failed $e');
  }
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

    final prefs = await SharedPreferences.getInstance();
    final lastPrimaryId = prefs.getString('lastPrimaryDeviceId');

    final connected = FlutterBluePlus.connectedDevices;
    for (final device in connected) {
      if (device.platformName.contains('OUI-SPY')) {
        DebugLog.log('AUTO: reconnecting to system-remembered ${device.platformName}');
        final ble = container.read(bleManagerProvider);
        await ble.connect(device, sessionId: const Uuid().v4());
        ble.markAsPrimary();
        await _onConnected(container, device.remoteId.toString());
        return;
      }
    }

    DebugLog.log('AUTO: scanning (no filter, 8s)...');

    final completer = Completer<BluetoothDevice?>();
    BluetoothDevice? preferredDevice;

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final advName = r.advertisementData.advName;
        final id = r.device.remoteId.toString();
        final serviceUuids = r.advertisementData.serviceUuids;

        // Match by name or by service UUID
        final nameMatch = name.contains('OUI-SPY') ||
            name.contains('OUI') ||
            advName.contains('OUI-SPY') ||
            advName.contains('OUI');
        final uuidMatch = serviceUuids.any(
            (u) => u.toString().endsWith('0a15-4b70-ba00-c010ae1ba01c'));
        final isOuiSpy = nameMatch || uuidMatch;

        if (name.isNotEmpty || advName.isNotEmpty || uuidMatch) {
          DebugLog.log('AUTO: saw "$name"/"$advName" $id uuids=$serviceUuids');
        }

        if (isOuiSpy) {
          if (lastPrimaryId != null && id == lastPrimaryId) {
            DebugLog.log('AUTO: PREFERRED MATCH: $name/$advName');
            FlutterBluePlus.stopScan();
            if (!completer.isCompleted) completer.complete(r.device);
            return;
          }
          preferredDevice ??= r.device;
          DebugLog.log('AUTO: MATCH: $name/$advName (fallback)');
        }
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    final found = await completer.future
        .timeout(const Duration(seconds: 10), onTimeout: () => preferredDevice);

    await sub.cancel();
    await FlutterBluePlus.stopScan();

    if (found != null) {
      DebugLog.log('AUTO: connecting to ${found.platformName}...');
      final ble = container.read(bleManagerProvider);
      await ble.connect(found, sessionId: const Uuid().v4());
      ble.markAsPrimary();
      await _onConnected(container, found.remoteId.toString());
      DebugLog.log('AUTO: connected');
    } else {
      DebugLog.log('AUTO: no OUI-SPY found after scan');
    }
  } catch (e) {
    DebugLog.log('AUTO: failed: $e');
  }
}

Future<void> _onConnected(ProviderContainer container, String deviceId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lastPrimaryDeviceId', deviceId);
}

