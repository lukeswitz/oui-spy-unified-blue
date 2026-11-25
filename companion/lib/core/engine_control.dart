// Copyright (c) 2026 Luke Switzer
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';

Future<void> setEngineEnabled(WidgetRef ref, Engine e, bool on, {String? targetNodeId}) async {
  final wd = ref.read(wardriveProvider);
  if (!on && wd.ownsEngine(e)) return wd.stopOwnedEngine(e);
  final app = ref.read(appStateProvider);
  final ble = ref.read(bleManagerProvider);
  if (on) {
    await ble.enableEngine(e, targetNodeId: targetNodeId, radio: app.engineRadio[e]);
  } else {
    if (e == Engine.foxhunter) app.endFoxhuntLiveActivity();
    await ble.disableEngine(e, targetNodeId: targetNodeId);
  }
}
