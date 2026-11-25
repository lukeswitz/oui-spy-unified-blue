// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/map_pins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('path length sums each leg', () {
    expect(pathLengthM(const [LatLng(0, 0)]), 0);
    final one = pathLengthM(const [LatLng(0, 0), LatLng(0, 0.01)]);
    expect(one, closeTo(1113, 5));
    expect(pathLengthM(const [LatLng(0, 0), LatLng(0, 0.01), LatLng(0, 0.02)]), closeTo(one * 2, 1));
  });

  test('pins add, rename and remove, and are saved', () async {
    SharedPreferences.setMockInitialValues({});
    final pins = MapPinsNotifier();
    await pins.add('Gate', const LatLng(10, 20));
    final id = pins.state.single.id;
    await pins.rename(id, 'North gate');
    expect(pins.state.single.name, 'North gate');
    final p = await SharedPreferences.getInstance();
    expect((jsonDecode(p.getString('map_pins')!) as List).single['name'], 'North gate');
    await pins.remove(id);
    expect(pins.state, isEmpty);
  });
}
