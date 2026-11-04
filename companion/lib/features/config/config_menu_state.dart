import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final configNavKey = GlobalKey<NavigatorState>();

final configMenuWantedProvider = StateProvider<bool>((ref) => false);

final historyFilterRequestProvider = StateProvider<String?>((ref) => null);

final configSectionRequestProvider = StateProvider<String?>((ref) => null);
