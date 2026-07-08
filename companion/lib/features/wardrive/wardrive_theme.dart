import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Wardrive visual modes — Classic baseline or Nightrider arcade.
enum WardriveTheme { classic, nightrider }

class WardriveThemeData {
  const WardriveThemeData({
    required this.theme,
    required this.label,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.secondary,
    required this.tertiary,
    required this.routeColor,
    required this.currentPosColor,
    required this.driverPov,
    required this.synthwaveSky,
    required this.speedLines,
    required this.speedoHud,
    required this.scoreChip,
    required this.detectionBanner,
    required this.neonClusters,
    required this.tileTint,
    required this.mapTileOverride,
    required this.engineOverrides,
    required this.routeAlpha,
    required this.markerSaturation,
  });

  final WardriveTheme theme;
  final String label;
  final String tagline;
  final IconData icon;

  final Color accent;
  final Color secondary;
  final Color tertiary;
  final Color routeColor;
  final Color currentPosColor;

  /// Lock map rotation to GPS heading (native flutter_map rotation).
  final bool driverPov;

  /// Top band: deep-space gradient + retro sun + horizon hairline + stars.
  final bool synthwaveSky;

  /// Streaking lines emanating from horizon, intensity-tied to speed.
  final bool speedLines;

  /// Bottom-center retro digital speedometer (respects unit prefs).
  final bool speedoHud;

  /// Top-right glowing arcade-style detection count.
  final bool scoreChip;

  /// Brief "DETECTED" banner pulse when a new flock device is captured.
  final bool detectionBanner;

  /// Clusters render as glowing neon hex rings instead of filled discs.
  final bool neonClusters;

  /// Color filter applied to raster tiles for neon retint.
  final ColorFilter? tileTint;
  final String? mapTileOverride;

  final Map<Engine, Color> engineOverrides;
  final double routeAlpha;
  final double markerSaturation;

  Color engineColor(Engine e) => engineOverrides[e] ?? e.color;
}

final ColorFilter _nightriderTileTint = ColorFilter.matrix(<double>[
  0.85, 0.0, 0.6, 0, 20,
  0.0, 0.3, 0.4, 0, 5,
  0.6, 0.1, 0.95, 0, 35,
  0, 0, 0, 1, 0,
]);

final Map<WardriveTheme, WardriveThemeData> wardriveThemes = {
  WardriveTheme.classic: const WardriveThemeData(
    theme: WardriveTheme.classic,
    label: 'Classic',
    tagline: 'Stock HUD',
    icon: Icons.tune,
    accent: AppTheme.accent,
    secondary: Color(0xFF9B6BFF),
    tertiary: Color(0xFFFFFFFF),
    routeColor: Color(0xFFFFFFFF),
    currentPosColor: AppTheme.accent,
    driverPov: false,
    synthwaveSky: false,
    speedLines: false,
    speedoHud: false,
    scoreChip: false,
    detectionBanner: false,
    neonClusters: false,
    tileTint: null,
    mapTileOverride: null,
    engineOverrides: {},
    routeAlpha: 0.85,
    markerSaturation: 0.07,
  ),
  WardriveTheme.nightrider: WardriveThemeData(
    theme: WardriveTheme.nightrider,
    label: 'Nightrider',
    tagline: 'Arcade racer · driver POV',
    icon: Icons.electric_bolt,
    accent: const Color(0xFFFF2E88),
    secondary: const Color(0xFF18E7F0),
    tertiary: const Color(0xFFFFC857),
    routeColor: const Color(0xFFFF2E88),
    currentPosColor: const Color(0xFF18E7F0),
    driverPov: true,
    synthwaveSky: true,
    speedLines: true,
    speedoHud: true,
    scoreChip: true,
    detectionBanner: true,
    neonClusters: true,
    tileTint: _nightriderTileTint,
    mapTileOverride:
        'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
    engineOverrides: const {
      Engine.detector: Color(0xFF18E7F0),
      Engine.flockBle: Color(0xFFC07BFF),
      Engine.flockWifi: Color(0xFFFF2E88),
      Engine.foxhunter: Color(0xFF7CFF6B),
      Engine.skySpy: Color(0xFF4DEAC1),
      Engine.uniPwn: Color(0xFFFF5252),
      Engine.wardrive: Color(0xFFFFC857),
    },
    routeAlpha: 0.95,
    markerSaturation: 0.12,
  ),
};

class WardriveThemeNotifier extends StateNotifier<WardriveTheme> {
  WardriveThemeNotifier() : super(WardriveTheme.classic) {
    _load();
  }
  static const _key = 'wardrive_theme';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null) return;
    final match = WardriveTheme.values.where((t) => t.name == value);
    if (match.isNotEmpty) state = match.first;
  }

  Future<void> setTheme(WardriveTheme t) async {
    state = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, t.name);
  }

  Future<void> toggle() async {
    await setTheme(state == WardriveTheme.classic
        ? WardriveTheme.nightrider
        : WardriveTheme.classic);
  }
}

final wardriveThemeProvider =
    StateNotifierProvider<WardriveThemeNotifier, WardriveTheme>((ref) {
  return WardriveThemeNotifier();
});

final wardriveThemeDataProvider = Provider<WardriveThemeData>((ref) {
  return wardriveThemes[WardriveTheme.classic]!;
});
