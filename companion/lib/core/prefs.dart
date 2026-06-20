import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences, loaded before runApp and injected via ProviderScope
/// override so widgets can read persisted values synchronously at first build
/// (no async-in-initState → no toggles animating from a default to the real
/// value when a screen mounts).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);
