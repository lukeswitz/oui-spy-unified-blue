import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyScreenNotifier extends StateNotifier<bool> {
  PrivacyScreenNotifier() : super(false) {
    _load();
  }

  static const _key = 'privacy_screen';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool on) async {
    state = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, on);
  }
}

final privacyScreenProvider =
    StateNotifierProvider<PrivacyScreenNotifier, bool>((ref) => PrivacyScreenNotifier());

class RxOnlyNotifier extends StateNotifier<bool?> {
  RxOnlyNotifier() : super(null) {
    _load();
  }

  static const _key = 'radio_rx_only';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  Future<void> set(bool on) async {
    state = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, on);
  }
}

final rxOnlyProvider = StateNotifierProvider<RxOnlyNotifier, bool?>((ref) => RxOnlyNotifier());

String maskMac(String mac, bool on) {
  if (!on) return mac;
  final hex = mac.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return 'XX:XX:XX:XX:XX:XX';
  return '${hex.substring(0, 2)}:${hex.substring(2, 4)}:XX:XX:XX:XX';
}

String maskName(String s, bool on) {
  if (!on || s.length <= 3) return s;
  return '${s.substring(0, 3)}${'•' * (s.length - 3).clamp(1, 8)}';
}
