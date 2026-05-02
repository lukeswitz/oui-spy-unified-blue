import 'package:intl/intl.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

/// Generates Wigle-compatible CSV (format 1.6).
class WigleCsv {
  const WigleCsv._();

  static const _version = '1.0.0';
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String generate(List<Detection> detections) {
    final buffer = StringBuffer();

    // Pre-header (line 1)
    buffer.writeln(
      'WigleWifi-1.6,'
      'appRelease=$_version,'
      'model=oui-spy,'
      'release=$_version,'
      'device=ESP32-S3,'
      'display=companion-app,'
      'board=XIAO,'
      'brand=colonelpanic',
    );

    // Column headers (line 2)
    buffer.writeln(
      'MAC,SSID,AuthMode,FirstSeen,Channel,Frequency,RSSI,'
      'CurrentLatitude,CurrentLongitude,AltitudeMeters,'
      'AccuracyMeters,RCOIs,MfgrId,Type',
    );

    // Data rows
    for (final d in detections) {
      // Skip detections without GPS (Wigle rejects ungeolocated data)
      if (d.latitude == null || d.longitude == null) continue;

      final mac = d.macAddress;
      final ssid = _escapeCsv(d.engine == Engine.skySpy
          ? (d.odid?.uavId ?? d.deviceName)
          : (d.ssid.isNotEmpty ? d.ssid : d.deviceName));
      final authMode = _authMode(d);
      final firstSeen = _dateFormat.format(d.appTimestamp);
      final channel = d.channel;
      final frequency = _frequency(d);
      final rssi = d.rssi;
      final lat = d.latitude!.toStringAsFixed(8);
      final lon = d.longitude!.toStringAsFixed(8);
      final alt = (d.altitude ?? 0).toStringAsFixed(0);
      final acc = (d.accuracy ?? 0).toStringAsFixed(1);
      final rcois = ''; // Not applicable for our use
      final mfgrId = _mfgrId(d);
      final type = d.engine.isWifi ? 'WIFI' : 'BLE';

      buffer.writeln(
        '$mac,$ssid,$authMode,$firstSeen,$channel,$frequency,$rssi,'
        '$lat,$lon,$alt,$acc,$rcois,$mfgrId,$type',
      );
    }

    return buffer.toString();
  }

  static String _authMode(Detection d) {
    final method = d.method;
    if (d.engine.isBle) {
      return '$method [LE]';
    }
    return method;
  }

  static int _frequency(Detection d) {
    if (d.engine.isWifi && d.channel > 0 && d.channel <= 14) {
      // 2.4 GHz channel to frequency
      if (d.channel == 14) return 2484;
      return 2407 + d.channel * 5;
    }
    if (d.engine.isBle) {
      return 7936; // BT device type code for generic BLE
    }
    return 0;
  }

  static String _mfgrId(Detection d) {
    // Flock-BLE detections via manufacturer ID
    if (d.engine == Engine.flockBle && d.method == 'mfg_id') {
      return '2504'; // 0x09C8 in decimal
    }
    return '';
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
