import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/deflock/deflock_api.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/prefs.dart';

enum AlprMapVerdict { mapped, candidate, unknown }

class AlprMatch {
  const AlprMatch(this.verdict, this.node, this.meters);
  final AlprMapVerdict verdict;
  final AlprNode? node;
  final double? meters;

  static const unknown = AlprMatch(AlprMapVerdict.unknown, null, null);

  String get label => switch (verdict) {
        AlprMapVerdict.mapped => 'ON MAP',
        AlprMapVerdict.candidate => 'UNMAPPED',
        AlprMapVerdict.unknown => 'NO MAP DATA',
      };

  String get detail => switch (verdict) {
        AlprMapVerdict.mapped =>
          '${node?.label ?? 'ALPR'} mapped ${meters!.round()} m away',
        AlprMapVerdict.candidate => meters == null
            ? 'No mapped ALPR in this area'
            : 'Nearest mapped ALPR ${meters!.round()} m away',
        AlprMapVerdict.unknown =>
          'Not fetched yet — turn on MAPPED ALPRs in the map layers menu',
      };
}

/// Public map edit: only a fully validated flock detection qualifies.
bool osmContributionAllowed(
        FlockConfidence? confidence, AlprMapVerdict verdict) =>
    confidence == FlockConfidence.verified &&
    verdict == AlprMapVerdict.candidate;

class _Tile {
  _Tile(this.nodes, this.fetchedAt);
  final List<AlprNode> nodes;
  final DateTime fetchedAt;
}

/// Crowd-sourced ALPR positions from OpenStreetMap (the DeFlock dataset),
/// cached per tile so a driven area keeps working offline.
class DeflockProvider extends ChangeNotifier {
  DeflockProvider(this._prefs, {DeflockApi? api})
      : _api = api ?? DeflockApi() {
    _showAlpr = _prefs.getBool(_keyShow) ?? false;
    _restore();
  }

  final SharedPreferences _prefs;
  final DeflockApi _api;

  static const _keyShow = 'deflock_show_alpr';
  static const _keyCache = 'deflock_tile_cache_v1';

  /// ~5.5 km cells: small enough for one Overpass call, big enough that a
  /// drive does not thrash the API.
  static const double _tileDeg = 0.05;
  static const Duration _tileTtl = Duration(days: 7);
  static const int _maxTiles = 2000;
  static const int _maxTilesPerFetch = 400;
  static const Duration _persistDebounce = Duration(seconds: 3);

  /// Within this radius an RF hit and a mapped node are the same camera.
  static const double _mappedMeters = 75;

  /// Beyond this, with tile coverage loaded, the hit is an unmapped candidate.
  static const double _candidateMeters = 250;

  static const _distance = Distance();

  final Map<String, _Tile> _tiles = {};

  /// Tile bboxes are inclusive on every edge, so a node sitting on a boundary
  /// comes back in each neighbouring tile — index by OSM id to keep it once.
  final Map<int, AlprNode> _byId = {};
  bool _showAlpr = false;
  bool _loading = false;
  Timer? _persistTimer;
  String? _error;

  bool get showAlpr => _showAlpr;
  bool get loading => _loading;
  String? get error => _error;
  int get nodeCount => _byId.length;
  int get tileCount => _tiles.length;

  Iterable<AlprNode> get nodes => _byId.values;

  void _reindex() {
    _byId.clear();
    for (final t in _tiles.values) {
      for (final n in t.nodes) {
        _byId[n.id] = n;
      }
    }
  }

  Future<void> setShowAlpr(bool on) async {
    _showAlpr = on;
    await _prefs.setBool(_keyShow, on);
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Nodes inside [bounds], for the map layer. Read-only: never fetches.
  List<AlprNode> nodesIn(GeoBounds bounds) => nodes
      .where((n) =>
          n.position.latitude >= bounds.south &&
          n.position.latitude <= bounds.north &&
          n.position.longitude >= bounds.west &&
          n.position.longitude <= bounds.east)
      .toList();

  /// Fetch whatever of [bounds] is not already cached, in ONE Overpass call.
  Future<void> ensureBounds(GeoBounds bounds, {bool force = false}) async {
    if (_loading) return;
    _error = null;
    final wanted = _tileKeysFor(bounds);
    final now = DateTime.now();
    final missing = wanted.where((k) {
      final t = _tiles[k];
      return force || t == null || now.difference(t.fetchedAt) > _tileTtl;
    }).toList();
    if (missing.isEmpty) return;

    if (missing.length > _maxTilesPerFetch) {
      _error = 'Zoom in to load mapped ALPRs';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final union = _unionOf(missing);
      final fetched = await _api.fetchBounds(union);
      final stamp = DateTime.now();
      final buckets = {for (final k in missing) k: <AlprNode>[]};
      for (final n in fetched) {
        buckets[_keyFor(n.position.latitude, n.position.longitude)]?.add(n);
      }
      buckets.forEach((k, v) => _tiles[k] = _Tile(v, stamp));
      DebugLog.log(
          'DEFLOCK: ${missing.length} tiles → ${fetched.length} ALPR nodes');
      _evict();
      _reindex();
    } on DeflockApiException catch (e) {
      _error = e.message;
      DebugLog.log('DEFLOCK: fetch failed: ${e.message}');
    } finally {
      _loading = false;
      notifyListeners();
    }
    _schedulePersist();
  }

  GeoBounds _unionOf(List<String> keys) {
    var south = double.infinity, west = double.infinity;
    var north = -double.infinity, east = -double.infinity;
    for (final k in keys) {
      final b = _boundsForKey(k);
      if (b.south < south) south = b.south;
      if (b.west < west) west = b.west;
      if (b.north > north) north = b.north;
      if (b.east > east) east = b.east;
    }
    return GeoBounds(south: south, west: west, north: north, east: east);
  }

  /// Pull the tile a single detection sits in, so a hit outside the area you
  /// panned over still resolves. No-op unless the layer is on.
  Future<void> ensureAround(double lat, double lon) {
    if (!_showAlpr) return Future<void>.value();
    return ensureBounds(_boundsForKey(_keyFor(lat, lon)));
  }

  /// Cross-reference one detection position against the mapped ALPRs.
  AlprMatch match(double lat, double lon) {
    final here = LatLng(lat, lon);
    if (_tiles[_keyFor(lat, lon)] == null) return AlprMatch.unknown;

    AlprNode? best;
    double bestM = double.infinity;
    for (final n in nodes) {
      final m = _distance.as(LengthUnit.Meter, here, n.position);
      if (m < bestM) {
        bestM = m;
        best = n;
      }
    }
    if (best == null || bestM > _candidateMeters) {
      return AlprMatch(AlprMapVerdict.candidate, best,
          best == null ? null : bestM);
    }
    if (bestM <= _mappedMeters) {
      return AlprMatch(AlprMapVerdict.mapped, best, bestM);
    }
    return AlprMatch(AlprMapVerdict.candidate, best, bestM);
  }

  /// Prefilled OSM note URL so an unmapped find can be contributed by hand.
  static String osmNoteUrl(double lat, double lon) =>
      'https://www.openstreetmap.org/note/new'
      '#map=19/${lat.toStringAsFixed(5)}/${lon.toStringAsFixed(5)}';

  List<String> _tileKeysFor(GeoBounds b) {
    final keys = <String>[];
    final latStart = (b.south / _tileDeg).floor();
    final lonStart = (b.west / _tileDeg).floor();
    final latEnd = _endIndex(b.north, latStart);
    final lonEnd = _endIndex(b.east, lonStart);
    for (var y = latStart; y <= latEnd; y++) {
      for (var x = lonStart; x <= lonEnd; x++) {
        keys.add('${y}_$x');
      }
    }
    return keys;
  }

  int _endIndex(double edge, int start) {
    final end = (edge / _tileDeg).ceil() - 1;
    return end < start ? start : end;
  }

  String _keyFor(double lat, double lon) =>
      '${(lat / _tileDeg).floor()}_${(lon / _tileDeg).floor()}';

  GeoBounds _boundsForKey(String key) {
    final parts = key.split('_');
    final y = int.parse(parts[0]);
    final x = int.parse(parts[1]);
    return GeoBounds(
      south: y * _tileDeg,
      west: x * _tileDeg,
      north: (y + 1) * _tileDeg,
      east: (x + 1) * _tileDeg,
    );
  }

  void _evict() {
    if (_tiles.length <= _maxTiles) return;
    final byAge = _tiles.entries.toList()
      ..sort((a, b) => a.value.fetchedAt.compareTo(b.value.fetchedAt));
    for (final e in byAge.take(_tiles.length - _maxTiles)) {
      _tiles.remove(e.key);
    }
  }

  /// Write the tile cache now instead of on the debounce.
  Future<void> flushPersist() async {
    _persistTimer?.cancel();
    await _persist();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persist);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  Future<void> _persist() async {
    final out = <String, dynamic>{};
    for (final e in _tiles.entries) {
      out[e.key] = {
        'at': e.value.fetchedAt.millisecondsSinceEpoch,
        'n': [
          for (final n in e.value.nodes)
            {
              'id': n.id,
              'lat': n.position.latitude,
              'lon': n.position.longitude,
              if (n.operator != null) 'op': n.operator,
              if (n.direction != null) 'dir': n.direction,
              if (n.zone != null) 'zone': n.zone,
              if (n.manufacturer != null) 'mfr': n.manufacturer,
            },
        ],
      };
    }
    await _prefs.setString(_keyCache, jsonEncode(out));
  }

  void _restore() {
    final raw = _prefs.getString(_keyCache);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final v = e.value as Map<String, dynamic>;
        final nodes = <AlprNode>[];
        for (final n in (v['n'] as List).cast<Map<String, dynamic>>()) {
          nodes.add(AlprNode(
            id: (n['id'] as num).toInt(),
            position:
                LatLng((n['lat'] as num).toDouble(), (n['lon'] as num).toDouble()),
            operator: n['op'] as String?,
            direction: n['dir'] as String?,
            zone: n['zone'] as String?,
            manufacturer: n['mfr'] as String?,
          ));
        }
        _tiles[e.key] = _Tile(
          nodes,
          DateTime.fromMillisecondsSinceEpoch((v['at'] as num).toInt()),
        );
      }
      _reindex();
      DebugLog.log('DEFLOCK: restored ${_tiles.length} tiles, $nodeCount nodes');
    } catch (e) {
      DebugLog.log('DEFLOCK: cache restore failed: $e');
    }
  }
}

final deflockProvider = ChangeNotifierProvider<DeflockProvider>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DeflockProvider(prefs);
});
