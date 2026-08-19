import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set by the CONFIG tab button; the config screen opens or closes the
/// SECTION sheet to match.
final configMenuWantedProvider = StateProvider<bool>((ref) => false);
