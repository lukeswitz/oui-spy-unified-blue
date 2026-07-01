import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display-time formatting that honors the user's 12h/24h preference.
///
/// [use24Hour] is a synchronously-readable mirror of the persisted pref so
/// plain (non-Consumer) widgets can format without threading a ref through.
/// Live list screens rebuild frequently, so a toggle change is reflected on
/// the next rebuild.
class AppTime {
  static bool use24Hour = false;

  static String time(DateTime dt) =>
      DateFormat(use24Hour ? 'HH:mm' : 'h:mm a').format(dt);

  /// "Jun 30, 2026  8:13 PM" / "Jun 30, 2026  20:13"
  static String dateTime(DateTime dt) =>
      DateFormat(use24Hour ? 'MMM d, yyyy  HH:mm' : 'MMM d, yyyy  h:mm a')
          .format(dt);

  /// "Jun 30  8:13 PM" / "Jun 30  20:13" — compact for narrow rows.
  static String dateTimeShort(DateTime dt) =>
      DateFormat(use24Hour ? 'MMM d  HH:mm' : 'MMM d  h:mm a').format(dt);

  /// "Jun 30, 2026  8:13:07 PM" / "...  20:13:07"
  static String dateTimeSeconds(DateTime dt) => DateFormat(
        use24Hour ? 'MMM d, yyyy  HH:mm:ss' : 'MMM d, yyyy  h:mm:ss a',
      ).format(dt);
}

class Use24HourTimeNotifier extends StateNotifier<bool> {
  Use24HourTimeNotifier() : super(AppTime.use24Hour) {
    _load();
  }

  static const _key = 'use_24h_time';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key) ?? false;
    AppTime.use24Hour = v;
    state = v;
  }

  Future<void> set(bool v) async {
    state = v;
    AppTime.use24Hour = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }
}

final use24HourTimeProvider =
    StateNotifierProvider<Use24HourTimeNotifier, bool>(
        (ref) => Use24HourTimeNotifier());
