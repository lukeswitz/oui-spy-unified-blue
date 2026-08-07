import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set by the CONFIG tab button; the config screen opens or closes the
/// SECTION sheet to match.
final configMenuWantedProvider = StateProvider<bool>((ref) => false);

/// Latched once the CONFIG tab has auto-opened the sheet this launch.
final configMenuAutoOpenedProvider = StateProvider<bool>((ref) => false);
