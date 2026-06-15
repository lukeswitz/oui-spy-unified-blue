import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

Detection _det({
  required String mac,
  required String method,
  required Engine engine,
  OdidExtension? odid,
  int secondsAgo = 0,
}) {
  return Detection(
    id: '$mac-$method',
    sessionId: 's',
    nodeId: 'n',
    macAddress: mac,
    engine: engine,
    method: method,
    rssi: -50,
    channel: 0,
    deviceTimestampMs: 0,
    appTimestamp: DateTime(2026, 6, 15, 12, 0, 0).subtract(Duration(seconds: secondsAgo)),
    odid: odid,
  );
}

void main() {
  group('groupDronesByUavId', () {
    const serialA = '1787F04BM24010011094';
    const serialB = 'AAAA1111BBBB2222CCCC';

    test('collapses 3 transports of one drone into a single merged group', () {
      final dets = [
        // BLE: partial — identity only, no operator/self-id (BLE sends one msg/advert)
        _det(
          mac: 'DC:39:9C:9C:39:DC',
          method: 'odid_ble',
          engine: Engine.skySpy,
          secondsAgo: 1,
          odid: const OdidExtension(uavId: serialA, uaType: 2, idType: 1),
        ),
        // WiFi NAN: full pack — operator + self-id + telemetry
        _det(
          mac: 'FA:85:AE:71:A9:E5',
          method: 'odid_nan',
          engine: Engine.skySpy,
          secondsAgo: 3,
          odid: const OdidExtension(
            uavId: serialA,
            uaType: 2,
            idType: 1,
            operatorId: 'OpID4Real',
            selfId: 'Test Flight',
            altitudeMsl: -1000,
            droneSpeed: 255,
            droneHeading: 361,
            classification: 1,
            classEu: 2,
          ),
        ),
        // WiFi Beacon: full pack
        _det(
          mac: 'FE:85:AE:71:A9:E5',
          method: 'odid_beacon',
          engine: Engine.skySpy,
          secondsAgo: 4,
          odid: const OdidExtension(
            uavId: serialA,
            uaType: 2,
            idType: 1,
            operatorId: 'OpID4Real',
            selfId: 'Test Flight',
          ),
        ),
        // second physical drone
        _det(
          mac: 'AA:BB:CC:DD:EE:FF',
          method: 'odid_ble',
          engine: Engine.skySpy,
          secondsAgo: 2,
          odid: const OdidExtension(uavId: serialB, uaType: 1, idType: 1),
        ),
        // noise: skyspy but no uavId -> excluded
        _det(mac: '60:60:1F:11:9D:B0', method: 'odid_ble', engine: Engine.skySpy),
        // non-drone -> excluded
        _det(mac: '11:22:33:44:55:66', method: 'wifi_ap', engine: Engine.flockWifi),
      ];

      final groups = groupDronesByUavId(dets);

      expect(groups.length, 2, reason: 'two distinct UAS-IDs');

      final a = groups.firstWhere((g) => g.uavId == serialA);
      expect(a.macs.length, 3, reason: 'BLE + NAN + Beacon MACs collapsed under one ID');
      expect(a.macs, containsAll(<String>[
        'DC:39:9C:9C:39:DC',
        'FA:85:AE:71:A9:E5',
        'FE:85:AE:71:A9:E5',
      ]));
      expect(a.methods, containsAll(<String>['odid_ble', 'odid_nan', 'odid_beacon']));

      // representative must be the MOST COMPLETE member (a WiFi pack), so the
      // grouped entity shows operator + description even though the BLE advert
      // (the "first" one) lacked them.
      expect(a.representative.odid?.operatorId, 'OpID4Real');
      expect(a.representative.odid?.selfId, 'Test Flight');
      expect(a.representative.odid?.uaType, 2);

      final b = groups.firstWhere((g) => g.uavId == serialB);
      expect(b.macs.length, 1);
      expect(b.representative.odid?.uavId, serialB);
    });

    test('empty input -> no groups', () {
      expect(groupDronesByUavId(const []), isEmpty);
    });
  });
}
