// Copyright (c) 2026 Luke Switzer
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';

void main() {
  Map<String, dynamic> sample({dynamic hull, String? color}) => {
        'gang_id': 20,
        'name': 'Black Wire Militia',
        'color': color ?? '#ef4444',
        'members': 299,
        'points': 11187,
        'rank': 4,
        'hull': hull ??
            [
              [-38.59, 145.47],
              [-38.60, 145.49],
              [-38.62, 145.44],
            ],
      };

  test('parses the live /api/territories row shape', () {
    final t = WdgwarsTerritory.fromJson(sample());
    expect(t.gangId, 20);
    expect(t.name, 'Black Wire Militia');
    expect(t.members, 299);
    expect(t.points, 11187);
    expect(t.rank, 4);
    expect(t.color, const Color(0xFFEF4444));
    expect(t.hull, hasLength(3));
    expect(t.hull.first.latitude, closeTo(-38.59, 1e-9));
    expect(t.hull.first.longitude, closeTo(145.47, 1e-9));
  });

  test('hull is [lat, lng] — bounds must not transpose them', () {
    final b = WdgwarsTerritory.fromJson(sample()).bounds;
    expect(b.minLat, closeTo(-38.62, 1e-9));
    expect(b.maxLat, closeTo(-38.59, 1e-9));
    expect(b.minLon, closeTo(145.44, 1e-9));
    expect(b.maxLon, closeTo(145.49, 1e-9));
  });

  test('survives malformed colours and hull entries', () {
    expect(WdgwarsTerritory.fromJson(sample(color: 'nonsense')).color,
        const Color(0xFF8B5CF6));
    expect(WdgwarsTerritory.fromJson(sample(color: 'ef4444')).color,
        const Color(0xFFEF4444));

    final ragged = WdgwarsTerritory.fromJson(sample(hull: [
      [1.0, 2.0],
      ['bad', 'row'],
      [3.0],
      null,
      [4.0, 5.0],
    ]));
    expect(ragged.hull, hasLength(2));
  });

  test('empty hull yields no points so the layer can drop it', () {
    expect(WdgwarsTerritory.fromJson(sample(hull: const [])).hull, isEmpty);
    expect(WdgwarsTerritory.fromJson(sample(hull: 'garbage')).hull, isEmpty);
  });
}
