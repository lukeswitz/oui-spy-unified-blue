import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

class DroneGroup {
  const DroneGroup({
    required this.uavId,
    required this.representative,
    required this.macs,
    required this.methods,
  });

  final String uavId;
  final Detection representative;
  final List<String> macs;
  final List<String> methods;
}

int odidCompleteness(OdidExtension? o) {
  if (o == null) return -1;
  var s = 0;
  if ((o.uavId ?? '').isNotEmpty) s++;
  if ((o.operatorId ?? '').isNotEmpty) s++;
  if ((o.selfId ?? '').isNotEmpty) s++;
  if (o.uaType != null && o.uaType != 0) s++;
  if (o.idType != null && o.idType != 0) s++;
  if (o.droneLat != null && o.droneLat != 0) s++;
  if (o.pilotLat != null && o.pilotLat != 0) s++;
  if (o.altitudeMsl != null) s++;
  if (o.altitudeBaro != null) s++;
  if (o.heightAgl != null) s++;
  if (o.droneSpeed != null) s++;
  if (o.vertSpeed != null) s++;
  if (o.droneHeading != null) s++;
  if (o.operatorAlt != null) s++;
  if (o.classification != null && o.classification != 0) s++;
  if (o.classEu != null && o.classEu != 0) s++;
  if (o.categoryEu != null && o.categoryEu != 0) s++;
  if (o.status != null && o.status != 0) s++;
  if (o.areaCount != null) s++;
  return s;
}

List<DroneGroup> groupDronesByUavId(List<Detection> detections) {
  final byId = <String, List<Detection>>{};
  for (final d in detections) {
    if (d.engine != Engine.skySpy) continue;
    final id = d.odid?.uavId ?? '';
    if (id.isEmpty) continue;
    byId.putIfAbsent(id, () => []).add(d);
  }

  final groups = <DroneGroup>[];
  byId.forEach((id, list) {
    var rep = list.first;
    var bestScore = odidCompleteness(rep.odid);
    for (final d in list) {
      final sc = odidCompleteness(d.odid);
      if (sc > bestScore ||
          (sc == bestScore && d.appTimestamp.isAfter(rep.appTimestamp))) {
        rep = d;
        bestScore = sc;
      }
    }

    final sorted = [...list]
      ..sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    final macs = <String>[];
    final methods = <String>[];
    final seen = <String>{};
    for (final d in sorted) {
      if (seen.add(d.macAddress)) {
        macs.add(d.macAddress);
        methods.add(d.method);
      }
    }

    groups.add(DroneGroup(
      uavId: id,
      representative: rep,
      macs: macs,
      methods: methods,
    ));
  });

  groups.sort((a, b) =>
      b.representative.appTimestamp.compareTo(a.representative.appTimestamp));
  return groups;
}
