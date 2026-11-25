// Copyright (c) 2026 Luke Switzer
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapPin {
  const MapPin({required this.id, required this.name, required this.at});
  final String id;
  final String name;
  final LatLng at;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'lat': at.latitude, 'lon': at.longitude};

  factory MapPin.fromJson(Map<String, dynamic> j) => MapPin(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        at: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
      );
}

/// Pins you drop on the map, kept on this phone.
class MapPinsNotifier extends StateNotifier<List<MapPin>> {
  MapPinsNotifier() : super(const []) {
    _load();
  }

  static const _key = 'map_pins';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      state = [for (final e in jsonDecode(raw) as List) MapPin.fromJson(Map<String, dynamic>.from(e as Map))];
    } on FormatException {
      state = const [];
    }
  }

  Future<void> _save() async {
    _changed = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final pin in state) pin.toJson()]));
  }

  Future<void> add(String name, LatLng at) async {
    state = [...state, MapPin(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, at: at)];
    await _save();
  }

  Future<void> rename(String id, String name) async {
    state = [for (final p in state) p.id == id ? MapPin(id: p.id, name: name, at: p.at) : p];
    await _save();
  }

  Future<void> remove(String id) async {
    state = [for (final p in state) if (p.id != id) p];
    await _save();
  }
}

final mapPinsProvider = StateNotifierProvider<MapPinsNotifier, List<MapPin>>((ref) => MapPinsNotifier());

double pathLengthM(List<LatLng> pts) {
  const d = Distance();
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += d.as(LengthUnit.Meter, pts[i - 1], pts[i]);
  }
  return total;
}
