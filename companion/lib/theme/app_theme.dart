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

enum AppStyle {
  standard('Default', 'Blue accent, follows the Dark Mode switch', null, Color(0xFF6B8AFF)),
  cyberpunk('Cyberpunk', 'Deep purple with neon cyan', Brightness.dark, Color(0xFF05D9E8)),
  terminal('Terminal', 'Green on black, monospace text', Brightness.dark, Color(0xFF33FF66)),
  minimalLight('Minimal light', 'Plain white, black accents', Brightness.light, Color(0xFF1A1A1A)),
  minimalDark('Minimal dark', 'Plain black, white accents', Brightness.dark, Color(0xFFEDEDED));

  const AppStyle(this.label, this.description, this.brightness, this.accent);
  final String label;
  final String description;
  final Brightness? brightness;
  final Color accent;

  String? get fontFamily => this == terminal ? 'Menlo' : null;
  List<String>? get fontFallback => this == terminal ? const ['Courier', 'monospace'] : null;

  ResolvedTheme palette(Brightness b) => switch (this) {
        cyberpunk => const ResolvedTheme(
            background: Color(0xFF0D0221),
            surface: Color(0xFF1A0B2E),
            surfaceLight: Color(0xFF261447),
            border: Color(0xFF3D1E6D),
            textPrimary: Color(0xFFF5F0FF),
            textSecondary: Color(0xFFC9B8FF),
            textDim: Color(0xFF9A86C4),
          ),
        terminal => const ResolvedTheme(
            background: Color(0xFF000000),
            surface: Color(0xFF050D07),
            surfaceLight: Color(0xFF0B1A0E),
            border: Color(0xFF1C4426),
            textPrimary: Color(0xFF4DFF7A),
            textSecondary: Color(0xFF2FD45E),
            textDim: Color(0xFF22A548),
          ),
        minimalLight => const ResolvedTheme(
            background: Color(0xFFFFFFFF),
            surface: Color(0xFFFAFAFA),
            surfaceLight: Color(0xFFF0F0F0),
            border: Color(0xFFDDDDDD),
            textPrimary: Color(0xFF111111),
            textSecondary: Color(0xFF444444),
            textDim: Color(0xFF6E6E6E),
          ),
        minimalDark => const ResolvedTheme(
            background: Color(0xFF0A0A0A),
            surface: Color(0xFF141414),
            surfaceLight: Color(0xFF1E1E1E),
            border: Color(0xFF2C2C2C),
            textPrimary: Color(0xFFEDEDED),
            textSecondary: Color(0xFFB5B5B5),
            textDim: Color(0xFF8A8A8A),
          ),
        standard => b == Brightness.light ? AppTheme._lightPalette : AppTheme._darkPalette,
      };
}

class AppStyleNotifier extends StateNotifier<AppStyle> {
  AppStyleNotifier() : super(AppStyle.standard) {
    _load();
  }

  static const _key = 'app_style';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    final match = AppStyle.values.where((s) => s.name == value);
    if (match.isNotEmpty) state = match.first;
  }

  Future<void> setStyle(AppStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

final appStyleProvider = StateNotifierProvider<AppStyleNotifier, AppStyle>((ref) {
  return AppStyleNotifier();
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
      return (km * 0.621371).toStringAsFixed(1);
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



const String _esriRest =
    'https://services.arcgisonline.com/ArcGIS/rest/services';
const String _cartoGl = 'https://basemaps.cartocdn.com/gl';

const String _osm = '© OpenStreetMap';
const String _carto = '© CARTO, © OpenStreetMap';
const String _esriImagery = '© Esri, Maxar, Earthstar Geographics';
const String _esriTopo = '© Esri, HERE, Garmin, USGS, OpenStreetMap';

enum MapStyle {
  cartoDark('Carto Dark', '$_cartoGl/dark-matter-gl-style/style.json',
      attribution: _carto, isVector: true, isDark: true),
  cartoLight('Positron', '$_cartoGl/positron-gl-style/style.json',
      attribution: _carto, isVector: true),
  cartoVoyager('Voyager', '$_cartoGl/voyager-gl-style/style.json',
      attribution: _carto, isVector: true),
  satellite('Satellite', '$_esriRest/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      attribution: _esriImagery, isDark: true),
  osm('OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: _osm),
  openTopo('Topo', 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      attribution: '$_osm, SRTM, OpenTopoMap (CC-BY-SA)'),
  terrain('Terrain', '$_esriRest/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
      attribution: _esriTopo),
  ;

  const MapStyle(
    this.label,
    this.url, {
    required this.attribution,
    this.isVector = false,
    this.isDark = false,
  });

  final String label;
  final String url;
  final String attribution;
  final bool isVector;
  final bool isDark;
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
  static Color textDim = const Color(0xFF8890A8);
  static Color accent = AppStyle.standard.accent;
  static Color error = const Color(0xFFE65A6B);
  static Color success = const Color(0xFF5AE6A1);
  static Color warning = const Color(0xFFE6A85A);

  // Engine colors — muted neon, same saturation/lightness family
  static Color detector = const Color(0xFF6B8AFF);
  static Color flockBle = const Color(0xFF9B6BFF);
  static Color flockWifi = const Color(0xFFE66B9B);
  static Color foxhunter = const Color(0xFF5AE6A1);
  static Color skySpy = const Color(0xFF5AE6D6);
  static Color uniPwn = const Color(0xFFE65A6B);
  static Color wardrive = const Color(0xFFE6895A);

  // Upload targets
  static Color wigle = const Color(0xFFE6A85A);
  static Color wdgwars = const Color(0xFF00E5FF);
  static Color wdgwarsAlt = const Color(0xFFA855F7);

  // GPS quality colors
  static Color gpsGood = const Color(0xFF5AE6A1);
  static Color gpsFair = const Color(0xFFE6A85A);
  static Color gpsPoor = const Color(0xFFE65A6B);
  static Color gpsNone = const Color(0xFF8890A8);

  static const _base = <String, Color>{
    'error': Color(0xFFE65A6B),
    'success': Color(0xFF5AE6A1),
    'warning': Color(0xFFE6A85A),
    'detector': Color(0xFF6B8AFF),
    'flockBle': Color(0xFF9B6BFF),
    'flockWifi': Color(0xFFE66B9B),
    'foxhunter': Color(0xFF5AE6A1),
    'skySpy': Color(0xFF5AE6D6),
    'uniPwn': Color(0xFFE65A6B),
    'wardrive': Color(0xFFE6895A),
    'wigle': Color(0xFFE6A85A),
    'wdgwars': Color(0xFF00E5FF),
    'wdgwarsAlt': Color(0xFFA855F7),
    'gpsGood': Color(0xFF5AE6A1),
    'gpsFair': Color(0xFFE6A85A),
    'gpsPoor': Color(0xFFE65A6B),
    'gpsNone': Color(0xFF8890A8),
  };

  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static Color readableOnLight(Color c) {
    const white = Color(0xFFFFFFFF);
    var hsl = HSLColor.fromColor(c);
    while (contrast(hsl.toColor(), white) < 4.5 && hsl.lightness > 0.05) {
      hsl = hsl.withLightness(hsl.lightness - 0.02);
    }
    return hsl.toColor();
  }

  static Brightness? _applied;
  static final Map<int, Color> _lightCache = {};

  static Color themed(Color c) => _applied == Brightness.light
      ? _lightCache.putIfAbsent(c.toARGB32(), () => readableOnLight(c))
      : c;

  static bool applyBrightness(Brightness b) {
    if (_applied == b) return false;
    _applied = b;
    Color pick(String k) => b == Brightness.light ? readableOnLight(_base[k]!) : _base[k]!;
    error = pick('error');
    success = pick('success');
    warning = pick('warning');
    detector = pick('detector');
    flockBle = pick('flockBle');
    flockWifi = pick('flockWifi');
    foxhunter = pick('foxhunter');
    skySpy = pick('skySpy');
    uniPwn = pick('uniPwn');
    wardrive = pick('wardrive');
    wigle = pick('wigle');
    wdgwars = pick('wdgwars');
    wdgwarsAlt = pick('wdgwarsAlt');
    gpsGood = pick('gpsGood');
    gpsFair = pick('gpsFair');
    gpsPoor = pick('gpsPoor');
    gpsNone = pick('gpsNone');
    textDim = b == Brightness.light ? _lightTextDim : const Color(0xFF8890A8);
    return true;
  }

  static const _lightBackground = Color(0xFFF2F3F8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceLight = Color(0xFFEBECF2);
  static const _lightBorder = Color(0xFFB0B6C6);
  static const _lightTextPrimary = Color(0xFF151720);
  static const _lightTextSecondary = Color(0xFF4C5165);
  static const _lightTextDim = Color(0xFF6B7186);

  static const _lightPalette = ResolvedTheme(
    background: _lightBackground,
    surface: _lightSurface,
    surfaceLight: _lightSurfaceLight,
    border: _lightBorder,
    textPrimary: _lightTextPrimary,
    textSecondary: _lightTextSecondary,
    textDim: _lightTextDim,
  );

  static const _darkPalette = ResolvedTheme(
    background: background,
    surface: surface,
    surfaceLight: surfaceLight,
    border: border,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textDim: Color(0xFF8890A8),
  );

  static ResolvedTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ResolvedTheme>() ??
        (theme.brightness == Brightness.light ? _lightPalette : _darkPalette);
  }

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData themeFor(AppStyle style, Brightness brightness) => _buildTheme(brightness, style);

  static ThemeData _buildTheme(Brightness brightness, [AppStyle style = AppStyle.standard]) {
    final isDark = brightness == Brightness.dark;
    final p = style.palette(brightness);
    final accent = style.accent;

    final bg = p.background;
    final sf = p.surface;
    final sfLight = p.surfaceLight;
    final bd = p.border;
    final tp = p.textPrimary;
    final ts = p.textSecondary;
    final td = p.textDim;

    return ThemeData(
      brightness: brightness,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFallback,
      extensions: [p],
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
          borderRadius: const BorderRadius.all(Radius.circular(10)),
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent.withValues(alpha: 0.18) : sf,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : ts,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.selected) ? accent : bd),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? bg : sf,
        selectedItemColor: accent,
        unselectedItemColor: td,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sfLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bd),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bd),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent),
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
            borderRadius: BorderRadius.circular(10),
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
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}

/// Resolved palette for the current brightness. Use [AppTheme.of(context)].
class ResolvedTheme extends ThemeExtension<ResolvedTheme> {
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

  @override
  ResolvedTheme copyWith() => this;

  @override
  ResolvedTheme lerp(ResolvedTheme? other, double t) {
    if (other == null) return this;
    return ResolvedTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
    );
  }
}
