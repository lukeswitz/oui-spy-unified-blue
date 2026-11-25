// Copyright (c) 2026 Luke Switzer
import 'package:intl/intl.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';

class WigleCsv {
  const WigleCsv._();

  static const _version = '1.0.0';
  static final _macPattern = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String generate(List<Detection> detections, {GeofenceFilter? geofenceFilter, String board = ''}) {
    final buffer = StringBuffer();

    final b = board.toLowerCase();
    final device = b.contains('c5') ? 'ESP32-C5'
                 : b.contains('c3') ? 'ESP32-C3'
                 : 'ESP32-S3';
    final boardName = b.contains('devkit') ? 'DevKitC' : 'XIAO';

    // Pre-header
    buffer.writeln(
      'WigleWifi-1.6,'
      'appRelease=$_version,'
      'model=OUI-SPY,'
      'release=$_version,'
      'device=$device,'
      'display=companion,'
      'board=$boardName,'
      'brand=colonelpanic,'
      'star=Sol,'
      'body=3,'
      'subBody=0',
    );

    // Column headers (line 2)
    buffer.writeln(
      'MAC,SSID,AuthMode,FirstSeen,Channel,Frequency,RSSI,'
      'CurrentLatitude,CurrentLongitude,AltitudeMeters,'
      'AccuracyMeters,RCOIs,MfgrId,Type',
    );

    // Data rows
    for (final d in detections) {
      if (d.latitude == null || d.longitude == null) continue;
      if (geofenceFilter != null &&
          geofenceFilter.isExcludedNullable(d.latitude, d.longitude)) {
        continue;
      }

      if (d.isZigbeeDetection) continue;
      final mac = d.macAddress;
      final isBleDevice = d.isBleDetection;
      if (!_macPattern.hasMatch(mac)) continue;
      final String rawSsid;
      if (d.engine == Engine.skySpy) {
        rawSsid = d.odid?.uavId ?? d.deviceName;
      } else if (isBleDevice) {
        rawSsid = d.deviceName;
      } else {
        rawSsid = d.ssid;
      }
      final ssid = _escapeCsv(rawSsid);
      final authMode = _capabilities(d);
      final firstSeen = _dateFormat.format(d.appTimestamp.toUtc());
      final channel = isBleDevice ? '0' : (d.channel <= 0 ? '' : '${d.channel}');
      final frequency = _frequency(d);
      final rssi = d.rssi;
      final lat = d.latitude!;
      final lon = d.longitude!;
      final alt = (d.altitude ?? 0.0).round();
      final acc = d.accuracy ?? 0.0;
      final mfgr = isBleDevice ? _mfgrId(d) : '';
      final type = _type(d);

      buffer.writeln(
        '$mac,$ssid,$authMode,$firstSeen,$channel,'
        '$frequency,$rssi,$lat,$lon,$alt,$acc,,$mfgr,$type',
      );
    }

    return buffer.toString();
  }

  static String _capabilities(Detection d) {
    final isBle = d.isBleDetection;
    if (isBle) return '[BLE]';
    return switch (d.wardrive?.authMode) {
      0 => '[OPEN]',
      1 => '[WEP]',
      2 => '[WPA_PSK]',
      3 => '[WPA2_PSK]',
      4 => '[WPA_WPA2_PSK]',
      5 => '[WPA2_EAP]',
      6 => '[WPA3_PSK]',
      7 => '[WPA2_WPA3_PSK]',
      8 => '[OWE]',
      9 => '[WPA3_EAP]',
      _ => '[UNDEFINED]',
    };
  }

  static String _mfgrId(Detection d) {
    final adv = d.wardrive == null ? null : wardriveAdvRaw[d.wardrive!];
    if (adv == null) return '';
    var i = 0;
    while (i + 1 < adv.length) {
      final len = adv[i];
      if (len == 0 || i + 1 + len > adv.length) break;
      if (adv[i + 1] == 0xFF && len >= 3) return '${adv[i + 2] | (adv[i + 3] << 8)}';
      i += 1 + len;
    }
    return '';
  }


  static String _frequency(Detection d) {
    final isBle = d.isBleDetection;
    if (isBle) return '';
    if (d.channel >= 1 && d.channel <= 13) return '${2407 + d.channel * 5}';
    if (d.channel == 14) return '2484';
    if (d.channel >= 36 && d.channel <= 177) {
      return '${5000 + d.channel * 5}';
    }
    return '';
  }

  /// WiGLE type field.
  static String _type(Detection d) {
    final isBle = d.isBleDetection;
    if (isBle) return 'BLE';
    return 'WIFI';
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
