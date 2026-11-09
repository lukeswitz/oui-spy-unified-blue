import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/theme/app_theme.dart';

String wifiSecurityLabel(int a) => switch (a) {
      0 => 'Open',
      1 => 'WEP',
      2 => 'WPA',
      3 => 'WPA2',
      4 => 'WPA/WPA2',
      5 => 'WPA2-EAP',
      6 => 'WPA3',
      7 => 'WPA2/WPA3',
      8 => 'OWE',
      9 => 'WPA3-EAP',
      _ => 'Unknown',
    };

String durationLabel(Duration d) => d.inHours > 0
    ? '${d.inHours}h ${d.inMinutes % 60}m'
    : d.inMinutes > 0
        ? '${d.inMinutes}m ${d.inSeconds % 60}s'
        : '${d.inSeconds}s';

List<MapEntry<String, int>> _ranked(Map<String, int> m, [int? take]) {
  final out = m.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return take == null ? out : out.take(take).toList();
}

class WardriveReport {
  WardriveReport({
    required this.session,
    required this.networks,
    required this.newNetworks,
    required this.hidden,
    required this.ble,
    required this.ghz24,
    required this.ghz5,
    required this.security,
    required this.makers,
    required this.flock,
    required this.drones,
    required this.watchlist,
    required this.alerts,
    required this.route,
    required this.wigleUploaded,
    required this.wdgwarsUploaded,
  });

  final Session session;
  final int networks;
  final int newNetworks;
  final int hidden;
  final int ble;
  final int ghz24;
  final int ghz5;
  final List<MapEntry<String, int>> security;
  final List<MapEntry<String, int>> makers;
  final int flock;
  final int drones;
  final int watchlist;
  final List<MapEntry<String, int>> alerts;
  final List<(double, double)> route;
  final bool wigleUploaded;
  final bool wdgwarsUploaded;

  int get seenNetworks => networks - newNetworks;
  Duration get duration => Duration(milliseconds: (session.endedAt ?? session.startedAt) - session.startedAt);

  static WardriveReport build({
    required Session session,
    required List<({String mac, String ssid, int auth, int channel, bool seenBefore})> aps,
    required int ble,
    required List<(double, double)> route,
    required Map<String, int> alertCounts,
    required int flock,
    required int drones,
    required int watchlist,
    required String? Function(String mac) vendorOf,
    required bool wigleUploaded,
    required bool wdgwarsUploaded,
  }) {
    final security = <String, int>{};
    final makers = <String, int>{};
    var fresh = 0, hidden = 0, g24 = 0, g5 = 0;
    for (final ap in aps) {
      if (!ap.seenBefore) fresh++;
      if (ap.ssid.isEmpty) hidden++;
      if (ap.channel >= 1 && ap.channel <= 14) g24++;
      if (ap.channel >= 32 && ap.channel <= 177) g5++;
      final sec = wifiSecurityLabel(ap.auth);
      security[sec] = (security[sec] ?? 0) + 1;
      final v = MacUtil.isRandomized(ap.mac) ? null : vendorOf(ap.mac);
      if (v != null && v.isNotEmpty) makers[v] = (makers[v] ?? 0) + 1;
    }
    return WardriveReport(
      session: session,
      networks: aps.length,
      newNetworks: fresh,
      hidden: hidden,
      ble: ble,
      ghz24: g24,
      ghz5: g5,
      security: _ranked(security),
      makers: _ranked(makers, 5),
      flock: flock,
      drones: drones,
      watchlist: watchlist,
      alerts: _ranked({for (final e in alertCounts.entries) alertKindLabel(e.key): e.value}),
      route: route,
      wigleUploaded: wigleUploaded,
      wdgwarsUploaded: wdgwarsUploaded,
    );
  }

  static Future<WardriveReport> load(
    AppDatabase db,
    Session s, {
    required String? Function(String mac) vendorOf,
    required bool wigleUploaded,
    required bool wdgwarsUploaded,
  }) async {
    final id = s.id;
    return build(
      session: s,
      aps: await db.sessionAps(id, s.startedAt),
      ble: (await db.wifiBleUniqueCounts(id)).ble,
      route: await db.sessionRoute(id),
      alertCounts: await db.classAlertCountsBetween(s.startedAt, s.endedAt ?? s.startedAt),
      flock: await db.flockMacCount(id),
      drones: await db.droneMacCount(id),
      watchlist: await db.detectorMacCount(id),
      vendorOf: vendorOf,
      wigleUploaded: wigleUploaded,
      wdgwarsUploaded: wdgwarsUploaded,
    );
  }

  static String _join(List<MapEntry<String, int>> l) => l.map((e) => '${e.key} ${e.value}').join(' · ');

  String shareText(UnitSystem units) => [
        'OUI-APEX wardrive report',
        AppTime.dateTime(DateTime.fromMillisecondsSinceEpoch(session.startedAt)),
        'Duration ${durationLabel(duration)} · Distance ${UnitFormatter.distance(session.distanceKm, units)}',
        'Wi-Fi networks $networks ($newNetworks new, $seenNetworks seen before)',
        'Hidden networks $hidden',
        'Bluetooth devices $ble',
        'Bands: 2.4 GHz $ghz24 · 5 GHz $ghz5',
        if (security.isNotEmpty) 'Security: ${_join(security)}',
        if (makers.isNotEmpty) 'Top makers: ${_join(makers)}',
        'Flock cameras $flock · Drones $drones · Watchlist hits $watchlist',
        if (alerts.isNotEmpty) 'Alerts: ${_join(alerts)}',
        'WiGLE ${wigleUploaded ? 'uploaded' : 'not uploaded'} · WDGWars ${wdgwarsUploaded ? 'uploaded' : 'not uploaded'}',
      ].join('\n');
}
