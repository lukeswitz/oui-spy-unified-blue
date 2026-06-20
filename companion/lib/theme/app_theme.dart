import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode state — persisted to SharedPreferences.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.light ? 'light' : 'dark');
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});


enum UnitSystem { metric, imperial }

class UnitSystemNotifier extends StateNotifier<UnitSystem> {
  UnitSystemNotifier() : super(UnitSystem.metric) {
    _load();
  }

  static const _key = 'unit_system';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == 'imperial') {
      state = UnitSystem.imperial;
    }
  }

  Future<void> toggle() async {
    state = state == UnitSystem.metric ? UnitSystem.imperial : UnitSystem.metric;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state == UnitSystem.imperial ? 'imperial' : 'metric');
  }

  Future<void> setSystem(UnitSystem system) async {
    state = system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, system == UnitSystem.imperial ? 'imperial' : 'metric');
  }
}

final unitSystemProvider =
    StateNotifierProvider<UnitSystemNotifier, UnitSystem>((ref) {
  return UnitSystemNotifier();
});

/// Helper to format distances and speeds respecting unit preference.
class UnitFormatter {
  const UnitFormatter._();

  static String distance(double km, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      final mi = km * 0.621371;
      return '${mi.toStringAsFixed(1)} mi';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  static String distanceShort(double km, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      return '${(km * 0.621371).toStringAsFixed(1)}';
    }
    return km.toStringAsFixed(1);
  }

  static String distanceLabel(UnitSystem units) {
    return units == UnitSystem.imperial ? 'MI' : 'KM';
  }

  static String speed(double kmh, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      final mph = kmh * 0.621371;
      return '${mph.toStringAsFixed(0)} mph';
    }
    return '${kmh.toStringAsFixed(0)} km/h';
  }

  static String speedShort(double kmh, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      return (kmh * 0.621371).toStringAsFixed(0);
    }
    return kmh.toStringAsFixed(0);
  }

  static String speedLabel(UnitSystem units) {
    return units == UnitSystem.imperial ? 'MPH' : 'KM/H';
  }

  static String altitude(double meters, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      return '${(meters * 3.28084).toStringAsFixed(0)}ft';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  static String detPerDist(double detsPerKm, UnitSystem units) {
    if (units == UnitSystem.imperial) {
      return (detsPerKm * 1.60934).toStringAsFixed(0);
    }
    return detsPerKm.toStringAsFixed(0);
  }

  static String detPerDistLabel(UnitSystem units) {
    return units == UnitSystem.imperial ? 'DET/MI' : 'DET/KM';
  }
}



enum MapStyle {
  cartoDark('Carto Dark', 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'),
  cartoLight('Carto Light', 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png'),
  cartoVoyager('Voyager', 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png'),
  osm('OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  openTopo('Topo', 'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
  stamenToner('Toner', 'https://basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}@2x.png'),
  stamenTerrain('Terrain', 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}'),
  ;

  const MapStyle(this.label, this.urlTemplate);
  final String label;
  final String urlTemplate;

  bool get isDark => this == cartoDark || this == stamenToner;
}

class MapStyleNotifier extends StateNotifier<MapStyle> {
  MapStyleNotifier() : super(MapStyle.cartoDark) {
    _load();
  }

  static const _key = 'map_style';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null) {
      final match = MapStyle.values.where((s) => s.name == value);
      if (match.isNotEmpty) state = match.first;
    }
  }

  Future<void> setStyle(MapStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

final mapStyleProvider =
    StateNotifierProvider<MapStyleNotifier, MapStyle>((ref) {
  return MapStyleNotifier();
});

class AppTheme {
  const AppTheme._();

  static const background = Color(0xFF08090E);
  static const surface = Color(0xFF0F1117);
  static const surfaceLight = Color(0xFF161822);
  static const border = Color(0xFF232736);
  static const textPrimary = Color(0xFFF0F1F5);
  static const textSecondary = Color(0xFFB0B5C8);
  static const textDim = Color(0xFF8890A8);
  static const accent = Color(0xFF6B8AFF);
  static const error = Color(0xFFE65A6B);
  static const success = Color(0xFF5AE6A1);
  static const warning = Color(0xFFE6A85A);

  // Engine colors — muted neon, same saturation/lightness family
  static const detector = Color(0xFF6B8AFF);
  static const flockBle = Color(0xFF9B6BFF);
  static const flockWifi = Color(0xFFE66B9B);
  static const foxhunter = Color(0xFF5AE6A1);
  static const skySpy = Color(0xFF5AE6D6);
  static const uniPwn = Color(0xFFE65A6B);
  static const wardrive = Color(0xFFE6895A);

  // GPS quality colors
  static const gpsGood = Color(0xFF5AE6A1);
  static const gpsFair = Color(0xFFE6A85A);
  static const gpsPoor = Color(0xFFE65A6B);
  static const gpsNone = Color(0xFF8890A8);

  static const _lightBackground = Color(0xFFF2F3F8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceLight = Color(0xFFEBECF2);
  static const _lightBorder = Color(0xFFB0B6C6);
  static const _lightTextPrimary = Color(0xFF151720);
  static const _lightTextSecondary = Color(0xFF4C5165);
  static const _lightTextDim = Color(0xFF6B7186);

  static ResolvedTheme of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? const ResolvedTheme(
            background: _lightBackground,
            surface: _lightSurface,
            surfaceLight: _lightSurfaceLight,
            border: _lightBorder,
            textPrimary: _lightTextPrimary,
            textSecondary: _lightTextSecondary,
            textDim: _lightTextDim,
          )
        : const ResolvedTheme(
            background: background,
            surface: surface,
            surfaceLight: surfaceLight,
            border: border,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textDim: textDim,
          );
  }

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? background : _lightBackground;
    final sf = isDark ? surface : _lightSurface;
    final sfLight = isDark ? surfaceLight : _lightSurfaceLight;
    final bd = isDark ? border : _lightBorder;
    final tp = isDark ? textPrimary : _lightTextPrimary;
    final ts = isDark ? textSecondary : _lightTextSecondary;
    final td = isDark ? textDim : _lightTextDim;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        surface: sf,
        onSurface: tp,
        primary: accent,
        onPrimary: isDark ? bg : Colors.white,
        secondary: ts,
        onSecondary: tp,
        error: error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: tp,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: tp,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: sf,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: bd, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: tp, fontSize: 24,
          fontWeight: FontWeight.w700, letterSpacing: 0.5,
        ),
        headlineMedium: TextStyle(
          color: tp, fontSize: 20, fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: tp, fontSize: 16, fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: tp, fontSize: 14, fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: ts, fontSize: 13, fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: td, fontSize: 11,
          fontWeight: FontWeight.w400, fontFamily: 'monospace',
        ),
        labelLarge: TextStyle(
          color: tp, fontSize: 14,
          fontWeight: FontWeight.w600, letterSpacing: 0.5,
        ),
        labelSmall: TextStyle(
          color: ts, fontSize: 10,
          fontWeight: FontWeight.w500, letterSpacing: 1.0,
        ),
      ),
      iconTheme: IconThemeData(color: ts, size: 20),
      dividerTheme: DividerThemeData(
        color: bd, thickness: 0.5, space: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return td;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: 0.3);
          }
          return bd;
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: sf,
        selectedItemColor: accent,
        unselectedItemColor: td,
        type: BottomNavigationBarType.fixed,
        elevation: isDark ? 0 : 2,
        selectedLabelStyle:
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sfLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: bd),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: bd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: TextStyle(color: td, fontSize: 14),
        labelStyle: TextStyle(color: ts, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? bg : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tp,
          side: BorderSide(color: bd),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}

/// Resolved palette for the current brightness. Use [AppTheme.of(context)].
class ResolvedTheme {
  const ResolvedTheme({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDim,
  });

  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDim;
}
