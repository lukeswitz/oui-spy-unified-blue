// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';

/// Mirrors the live GET /api/me response shape.
Map<String, dynamic> me({Map<String, dynamic> overrides = const {}}) => {
      'ok': true,
      'user_id': 1,
      'username': 'tester',
      'country': 'US',
      'joined': '2026-07-13',
      'wifi': 57797,
      'ble': 54489,
      'aircraft': 0,
      'mesh': 0,
      'notes': 2,
      'cracked': 1,
      'reinforce': {'2': 13120, '3': 1194},
      'reinforce_total': 14811,
      'total': 112286,
      'recent_today': 0,
      'recent_7d': 8611,
      'gang': 'Biscuits',
      'gang_id': 16,
      'gang_role': 'member',
      'badges': ['first_blood', 'ble_10k'],
      'credits': {
        'balance': 97,
        'lifetime_earned': 120,
        'bounties_completed': 3,
      },
      'your_rank': {'all_time': null, 'today': null, 'week': null, 'top_n': 50},
      'new_ap_limit': {
        'used': 3558,
        'remaining': 496442,
        'cap': 500000,
        'window': '24h_rolling',
      },
      ...overrides,
    };

void main() {
  test('parses every field the stats card renders', () {
    final s = WdgwarsUserStats.fromJson(me());
    expect(s.username, 'tester');
    expect(s.wifi, 57797);
    expect(s.ble, 54489);
    expect(s.total, 112286);
    expect(s.badges, hasLength(2));
    expect(s.gang, 'Biscuits');
    expect(s.gangRole, 'member');
    expect(s.country, 'US');
    expect(s.joined, '2026-07-13');
    expect(s.recentToday, 0);
    expect(s.recent7d, 8611);
    expect(s.reinforced, 14811);
    expect(s.notes, 2);
    expect(s.cracked, 1);
    expect(s.credits, 97);
    expect(s.creditsLifetime, 120);
    expect(s.bountiesCompleted, 3);
    expect(s.dailyUsed, 3558);
    expect(s.dailyRemaining, 496442);
    expect(s.dailyCap, 500000);
  });

  test('unranked account yields a null rank so the badge stays hidden', () {
    expect(WdgwarsUserStats.fromJson(me()).rank, isNull);
    expect(
      WdgwarsUserStats.fromJson(me(overrides: {
        'your_rank': {'all_time': 12}
      })).rank,
      12,
    );
  });

  test('missing credits / rank / quota blocks degrade to zero, not a throw', () {
    final s = WdgwarsUserStats.fromJson({
      'ok': true,
      'username': 'bare',
      'wifi': 1,
      'ble': 2,
      'aircraft': 3,
      'mesh': 4,
      'total': 10,
    });
    expect(s.credits, 0);
    expect(s.creditsLifetime, 0);
    expect(s.bountiesCompleted, 0);
    expect(s.rank, isNull);
    expect(s.dailyCap, 0);
    expect(s.recent7d, 0);
    expect(s.gangRole, '');
    expect(s.badges, isEmpty);
  });
}
