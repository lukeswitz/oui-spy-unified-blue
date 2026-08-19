import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/deflock/deflock_api.dart';
import 'package:oui_spy/core/deflock/deflock_provider.dart';
import 'package:oui_spy/core/models/detection.dart';

class _FakeApi extends DeflockApi {
  _FakeApi(this.nodes);
  final List<AlprNode> nodes;
  int calls = 0;

  @override
  Future<List<AlprNode>> fetchBounds(GeoBounds bounds) async {
    calls++;
    return nodes.where((n) => bounds.contains(n.position)).toList();
  }
}

AlprNode _node(int id, double lat, double lon, {String? op}) => AlprNode(
      id: id,
      position: LatLng(lat, lon),
      operator: op,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Overpass query carries the ALPR tag pair and the bbox', () {
    final q = DeflockApi.query(
        const GeoBounds(south: 0.1, west: 0.2, north: 0.3, east: 0.4));
    expect(q, contains('"man_made"="surveillance"'));
    expect(q, contains('"surveillance:type"="ALPR"'));
    expect(q, contains('"surveillance:type"="alpr"'));
    expect(q, isNot(contains('~')));
    expect(q, contains('(0.10000,0.20000,0.30000,0.40000)'));
    expect(q, startsWith('[out:json]'));
  });

  test('element parsing keeps tags and rejects malformed nodes', () {
    final ok = AlprNode.fromElement({
      'id': 42,
      'lat': 0.0,
      'lon': 0.0,
      'tags': {
        'operator': 'Flock Safety',
        'camera:direction': '180',
      },
    });
    expect(ok, isNotNull);
    expect(ok!.isFlock, isTrue);
    expect(ok.direction, '180');
    expect(ok.osmUrl, 'https://www.openstreetmap.org/node/42');

    expect(AlprNode.fromElement({'id': 1, 'lat': 0.0}), isNull);
    expect(AlprNode.fromElement({'lat': 0.0, 'lon': 0.0}), isNull);
  });

  test('no tile loaded for the area reads as unknown, not as a candidate',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final p = DeflockProvider(prefs, api: _FakeApi([]));
    expect(p.match(0.0, 0.0).verdict, AlprMapVerdict.unknown);
  });

  test('a hit on top of a mapped node is ON MAP, one far away is UNMAPPED',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi([_node(1, 0.0, 0.0, op: 'Flock Safety')]);
    final p = DeflockProvider(prefs, api: api);

    await p.ensureBounds(
        const GeoBounds(south: -0.01, west: -0.01, north: 0.01, east: 0.01));
    expect(api.calls, greaterThan(0));
    expect(p.nodeCount, 1);

    final near = p.match(0.00032, 0.0);
    expect(near.verdict, AlprMapVerdict.mapped);
    expect(near.meters, lessThan(75));

    final far = p.match(0.0, 0.0051);
    expect(far.verdict, AlprMapVerdict.candidate);
    expect(far.meters, greaterThan(250));
  });

  test('cached tiles survive a provider restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi([_node(7, 0.0, 0.0)]);
    final first = DeflockProvider(prefs, api: api);
    await first.ensureBounds(
        const GeoBounds(south: -0.01, west: -0.01, north: 0.01, east: 0.01));
    await first.flushPersist();

    final second = DeflockProvider(prefs, api: _FakeApi([]));
    expect(second.nodeCount, 1);
    expect(second.match(0.00032, 0.0).verdict, AlprMapVerdict.mapped);
  });

  test('ensureAround pulls one tile, and only when the layer is on', () async {
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi([_node(3, 0.0, 0.0)]);
    final p = DeflockProvider(prefs, api: api);

    await p.ensureAround(0.0, 0.0);
    expect(api.calls, 0);
    expect(p.match(0.0, 0.0).verdict, AlprMapVerdict.unknown);

    await p.setShowAlpr(true);
    await p.ensureAround(0.0, 0.0);
    expect(api.calls, 1);
    expect(p.match(0.0, 0.0).verdict, AlprMapVerdict.mapped);
  });

  test('a viewport spanning many tiles costs exactly one request', () async {
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi([_node(1, 0.02, 0.02), _node(2, 0.22, 0.22)]);
    final p = DeflockProvider(prefs, api: api);

    await p.ensureBounds(
        const GeoBounds(south: 0.0, west: 0.0, north: 0.25, east: 0.25));
    expect(api.calls, 1);
    expect(p.nodeCount, 2);

    await p.ensureBounds(
        const GeoBounds(south: 0.0, west: 0.0, north: 0.25, east: 0.25));
    expect(api.calls, 1, reason: 'cached tiles must not refetch');

    await p.ensureBounds(
        const GeoBounds(south: 0.05, west: 0.05, north: 0.15, east: 0.15));
    expect(api.calls, 1, reason: 'a pan inside cached tiles must not refetch');
  });

  test('only a validated flock detection may be offered to OSM', () {
    for (final v in AlprMapVerdict.values) {
      expect(osmContributionAllowed(FlockConfidence.suspected, v), isFalse);
      expect(osmContributionAllowed(FlockConfidence.high, v), isFalse);
      expect(osmContributionAllowed(null, v), isFalse);
    }
    expect(
        osmContributionAllowed(
            FlockConfidence.verified, AlprMapVerdict.candidate),
        isTrue);
    expect(
        osmContributionAllowed(FlockConfidence.verified, AlprMapVerdict.mapped),
        isFalse);
    expect(
        osmContributionAllowed(
            FlockConfidence.verified, AlprMapVerdict.unknown),
        isFalse);
  });

  test('OSM note link points at the detection position', () {
    expect(DeflockProvider.osmNoteUrl(0.1, 0.2),
        'https://www.openstreetmap.org/note/new#map=19/0.10000/0.20000');
  });
}
