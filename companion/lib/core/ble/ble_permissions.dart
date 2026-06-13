import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:oui_spy/core/debug_log.dart';

enum BlePermResult {
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  locationServicesOff,
}

class BlePermissions {
  static int? _sdkInt;

  static Future<int> androidSdkInt() async {
    if (_sdkInt != null) return _sdkInt!;
    if (!Platform.isAndroid) return _sdkInt = 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return _sdkInt = info.version.sdkInt;
  }

  static Future<BlePermResult> ensureForScan() async {
    if (!Platform.isAndroid) return BlePermResult.ready;

    final sdk = await androidSdkInt();

    if (sdk >= 31) {
      final res = await [
        ph.Permission.bluetoothScan,
        ph.Permission.bluetoothConnect,
      ].request();
      DebugLog.log('BLEPERM: sdk=$sdk scan=${res[ph.Permission.bluetoothScan]} '
          'connect=${res[ph.Permission.bluetoothConnect]}');
      return _collapse(res.values);
    }

    final loc = await ph.Permission.location.request();
    DebugLog.log('BLEPERM: sdk=$sdk location=$loc');
    final permResult = _collapse([loc]);
    if (permResult != BlePermResult.ready) return permResult;

    if (!await Geolocator.isLocationServiceEnabled()) {
      DebugLog.log('BLEPERM: location services off');
      return BlePermResult.locationServicesOff;
    }
    return BlePermResult.ready;
  }

  static BlePermResult _collapse(Iterable<ph.PermissionStatus> statuses) {
    if (statuses.any((s) => s.isPermanentlyDenied)) {
      return BlePermResult.permissionPermanentlyDenied;
    }
    if (statuses.any((s) => !s.isGranted)) {
      return BlePermResult.permissionDenied;
    }
    return BlePermResult.ready;
  }

  static Future<void> openAppSettings() => ph.openAppSettings();

  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();
}
