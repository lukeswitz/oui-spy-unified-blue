import 'package:intl/intl.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

/// Generate WiGLE-compatible CSV (format 1.6)
/// Spec: https://api.wigle.net/csvFormat.html
class WigleCsv {
  const WigleCsv._();

  static const _version = '1.0.0';
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String generate(List<Detection> detections) {
    final buffer = StringBuffer();

    // Pre-header 
    buffer.writeln(
      'WigleWifi-1.6,'
      'appRelease=$_version,'
      'model=OUI-SPY,'
      'release=$_version,'
      'device=ESP32-S3,'
      'display=companion,'
      'board=XIAO,'
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

      final mac = d.macAddress;
      final ssid = _escapeCsv(d.engine == Engine.skySpy
          ? (d.odid?.uavId ?? d.deviceName)
          : (d.ssid.isNotEmpty ? d.ssid : d.deviceName));
      final authMode = _capabilities(d);
      final firstSeen = _dateFormat.format(d.appTimestamp.toUtc());
      final channel = d.channel;
      final frequency = _frequency(d);
      final rssi = d.rssi;
      final lat = d.latitude!;
      final lon = d.longitude!;
      final alt = d.altitude ?? 0.0;
      final acc = d.accuracy ?? 0.0;
      final type = _type(d);

      buffer.writeln(
        '$mac,$ssid,$authMode,$firstSeen,$channel,'
        '$frequency,$rssi,$lat,$lon,$alt,$acc,,,${type}',
      );
    }

    return buffer.toString();
  }

  /// WiGLE capabilities from firmware auth_mode byte.
  /// Firmware values: 0=OPEN, 1=WEP, 2=WPA, 3=WPA2, 4=WPA_WPA2, 5=WPA2_ENT, 6=WPA3
  static String _capabilities(Detection d) {
    if (d.engine.isBle) return '[LE]';
    final auth = d.wardrive?.authMode ?? 3;
    return switch (auth) {
      0 => '[OPEN]',
      1 => '[WEP]',
      2 => '[WPA_PSK]',
      3 => '[WPA2_PSK]',
      4 => '[WPA_WPA2_PSK]',
      5 => '[WPA2_EAP]',
      6 => '[WPA3_SAE]',
      _ => '[WPA2_PSK]',
    };
  }

  /// Channel to center frequency in MHz. BLE = 0 (matches Biscuit format).
  static String _frequency(Detection d) {
    if (d.engine.isBle) return '0';
    if (d.channel >= 1 && d.channel <= 13) return '${2407 + d.channel * 5}';
    if (d.channel == 14) return '2484';
    if (d.channel >= 36 && d.channel <= 177) {
      return '${5000 + d.channel * 5}';
    }
    return '0';
  }

  /// WiGLE type field.
  static String _type(Detection d) {
    if (d.engine.isBle) return 'BLE';
    return 'WIFI';
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
