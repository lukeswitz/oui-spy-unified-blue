import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/feed/feed_stats_header.dart';

Detection _d(String mac, int secondsAgo) => Detection(
      id: mac,
      sessionId: 's',
      nodeId: 'n',
      macAddress: mac,
      engine: Engine.wardrive,
      method: 'x',
      rssi: -60,
      channel: 1,
      deviceTimestampMs: 0,
      appTimestamp: DateTime(2026).subtract(Duration(seconds: secondsAgo)),
    );

void main() {
  const vendors = {
    '02:00:00:00:00:01': 'Apple',
    '02:00:00:00:00:02': 'Netgear',
    '02:00:00:00:00:03': 'Espressif',
    '02:00:00:00:00:04': 'Netgear',
  };
  String? key(Detection d) => vendors[d.macAddress];

  List<String> macs(List<Detection> l) => [for (final d in l) d.macAddress.substring(15)];

  test('selected vendor first, rest A to Z, unknown last, newest first within vendor', () {
    final l = [
      _d('02:00:00:00:00:05', 0),
      _d('02:00:00:00:00:01', 5),
      _d('02:00:00:00:00:02', 9),
      _d('02:00:00:00:00:03', 1),
      _d('02:00:00:00:00:04', 2),
    ];
    sortByVendor(l, key, first: 'Netgear');
    expect(macs(l), ['04', '02', '01', '03', '05']);
  });

  test('descending reverses vendor order but keeps the selected vendor first', () {
    final l = [
      _d('02:00:00:00:00:01', 0),
      _d('02:00:00:00:00:03', 0),
      _d('02:00:00:00:00:02', 0),
      _d('02:00:00:00:00:05', 0),
    ];
    sortByVendor(l, key, first: 'Apple', ascending: false);
    expect(macs(l), ['01', '02', '03', '05']);
  });
}
