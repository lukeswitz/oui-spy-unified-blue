import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/feed/detection_row.dart' show detectionHeadline;

/// One Cursor-on-Target event, as ATAK reads it over UDP.
class CotEvent {
  const CotEvent({
    required this.uid,
    required this.type,
    required this.lat,
    required this.lon,
    required this.callsign,
    required this.time,
    this.how = 'm-g',
    this.hae,
    this.ce = 9999999,
    this.remarks = '',
    this.staleSeconds = 300,
    this.linkUid,
  });

  final String uid;
  final String type;
  final double lat;
  final double lon;
  final double? hae;
  final double ce;
  final String how;
  final String callsign;
  final String remarks;
  final DateTime time;
  final int staleSeconds;
  final String? linkUid;

  static String _iso(DateTime t) => t.toUtc().toIso8601String();

  static String esc(String s) => s
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String toXml() {
    final now = _iso(time);
    final stale = _iso(time.add(Duration(seconds: staleSeconds)));
    final link = linkUid == null ? '' : '<link uid="${esc(linkUid!)}" relation="p-p" type="a-u-A-M-H-Q"/>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<event version="2.0" uid="${esc(uid)}" type="${esc(type)}" how="${esc(how)}" '
        'time="$now" start="$now" stale="$stale">'
        '<point lat="${lat.toStringAsFixed(7)}" lon="${lon.toStringAsFixed(7)}" '
        'hae="${(hae ?? 9999999).toStringAsFixed(1)}" ce="${ce.toStringAsFixed(1)}" le="9999999.0"/>'
        '<detail><contact callsign="${esc(callsign)}"/>$link<remarks>${esc(remarks)}</remarks></detail>'
        '</event>';
  }
}

String _macKey(String mac) => mac.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();

/// Engines whose catches go to ATAK. Wardrive and capture rows are every radio in range, not catches.
bool cotSends(Detection d) => switch (d.engine) {
      Engine.wardrive || Engine.pcap || Engine.sdr || Engine.foxhunter => false,
      _ => true,
    };

/// The events one detection puts on ATAK's map: a drone and its pilot from Remote ID, or a catch
/// placed where this phone was when it heard it.
List<CotEvent> cotEventsFor(Detection d, {DateTime? now}) {
  if (!cotSends(d)) return const [];
  final t = now ?? d.appTimestamp;
  final key = _macKey(d.macAddress);
  final odid = d.odid;
  final dLat = odid?.droneLat, dLon = odid?.droneLon;
  if (odid != null && dLat != null && dLon != null && (dLat != 0 || dLon != 0)) {
    final id = odid.uavId?.trim().isNotEmpty == true ? odid.uavId!.trim() : key;
    final droneUid = 'ouispy-drone-$key';
    final events = [
      CotEvent(
        uid: droneUid,
        type: 'a-u-A-M-H-Q',
        lat: dLat,
        lon: dLon,
        callsign: 'UAS $id',
        remarks: 'Remote ID drone, ${d.rssi} dBm${d.sourceNodeId.isNotEmpty ? ', via ${d.sourceNodeId}' : ''}',
        time: t,
        staleSeconds: 60,
      ),
    ];
    final pLat = odid.pilotLat, pLon = odid.pilotLon;
    if (pLat != null && pLon != null && (pLat != 0 || pLon != 0)) {
      events.add(CotEvent(
        uid: 'ouispy-pilot-$key',
        type: 'a-u-G',
        lat: pLat,
        lon: pLon,
        callsign: 'PILOT $id',
        remarks: 'Operator of UAS $id',
        time: t,
        staleSeconds: 60,
        linkUid: droneUid,
      ));
    }
    return events;
  }
  final lat = d.latitude, lon = d.longitude;
  if (lat == null || lon == null || (lat == 0 && lon == 0)) return const [];
  final title = detectionHeadline(d);
  return [
    CotEvent(
      uid: 'ouispy-catch-$key',
      type: 'a-u-G',
      how: 'h-e',
      lat: lat,
      lon: lon,
      ce: d.accuracy ?? 50,
      callsign: title,
      remarks: '$title, ${d.macAddress.toUpperCase()}, ${d.rssi} dBm, heard near here'
          '${d.sourceNodeId.isNotEmpty ? ' by ${d.sourceNodeId}' : ''}',
      time: t,
    ),
  ];
}
