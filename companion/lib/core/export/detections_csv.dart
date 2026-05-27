import 'package:intl/intl.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/radio_classifier.dart';

class DetectionsCsv {
  const DetectionsCsv._();

  static final _ts = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

  static const _columns = <String>[
    'timestamp_utc',
    'session_id',
    'node_id',
    'source_node_id',
    'engine',
    'method',
    'mac',
    'device_name',
    'ssid',
    'rssi_dbm',
    'channel',
    'count',
    'lat',
    'lon',
    'altitude_m',
    'speed',
    'heading',
    'accuracy_m',
    'satellites',
    'radio',
    'is_raven',
    'raven_fw',
    'odid_uav_id',
    'odid_op_id',
    'odid_drone_lat',
    'odid_drone_lon',
    'odid_alt_msl',
    'odid_height_agl',
    'odid_speed',
    'odid_heading',
    'odid_pilot_lat',
    'odid_pilot_lon',
    'unipwn_robot_type',
    'unipwn_exploited',
    'unipwn_serial',
    'detector_filter',
    'detector_full_mac',
    'wardrive_auth_mode',
  ];

  static String generate(Iterable<Detection> detections) {
    final rows = detections.map(_cells).toList();
    final keep = List<bool>.filled(_columns.length, false);
    for (final r in rows) {
      for (var i = 0; i < r.length; i++) {
        if (!keep[i] && r[i].isNotEmpty) keep[i] = true;
      }
    }
    final header = <String>[];
    for (var i = 0; i < _columns.length; i++) {
      if (keep[i]) header.add(_columns[i]);
    }
    final buf = StringBuffer()..writeln(header.join(','));
    for (final r in rows) {
      final out = <String>[];
      for (var i = 0; i < r.length; i++) {
        if (keep[i]) out.add(_escape(r[i]));
      }
      buf.writeln(out.join(','));
    }
    return buf.toString();
  }

  static List<String> _cells(Detection d) {
    String radio;
    if (d.isBleDetection) {
      radio = 'BLE';
    } else if (d.isWifiDetection) {
      radio = 'WIFI';
    } else {
      radio = '';
    }

    final cells = <String>[
      _ts.format(d.appTimestamp.toUtc()),
      d.sessionId,
      d.nodeId,
      d.sourceNodeId,
      d.engine.name,
      d.method,
      d.macAddress,
      d.deviceName,
      d.ssid,
      d.rssi.toString(),
      d.channel.toString(),
      d.count.toString(),
      _num(d.latitude),
      _num(d.longitude),
      _num(d.altitude),
      _num(d.speed),
      _num(d.heading),
      _num(d.accuracy),
      d.satelliteCount?.toString() ?? '',
      radio,
      d.flock?.isRaven == true ? '1' : (d.flock != null ? '0' : ''),
      d.flock?.ravenFirmware ?? '',
      d.odid?.uavId ?? '',
      d.odid?.operatorId ?? '',
      _num(d.odid?.droneLat),
      _num(d.odid?.droneLon),
      d.odid?.altitudeMsl?.toString() ?? '',
      d.odid?.heightAgl?.toString() ?? '',
      d.odid?.droneSpeed?.toString() ?? '',
      d.odid?.droneHeading?.toString() ?? '',
      _num(d.odid?.pilotLat),
      _num(d.odid?.pilotLon),
      d.unipwn?.robotType ?? '',
      d.unipwn?.exploited == true ? '1' : (d.unipwn != null ? '0' : ''),
      d.unipwn?.serialNumber ?? '',
      d.detector?.filterDescription ?? '',
      d.detector?.isFullMac == true ? '1' : (d.detector != null ? '0' : ''),
      d.wardrive?.authMode.toString() ?? '',
    ];
    return cells;
  }

  static String _num(double? v) => v == null ? '' : v.toString();

  static String _escape(String value) {
    if (value.isEmpty) return '';
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
