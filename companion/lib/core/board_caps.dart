// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/zigbee.dart';

/// Whether a control works with the connected board, and a one-line reason when it does not.
class Cap {
  const Cap.on()
      : enabled = true,
        reason = null;
  const Cap.off(String this.reason) : enabled = false;

  final bool enabled;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is Cap && other.enabled == enabled && other.reason == reason;

  @override
  int get hashCode => Object.hash(enabled, reason);
}

const _noBuzzerBoards = {'tdongle_s3', 'tdongle_c5', 'stickc'};

bool boardHasBuzzer(String board) => !_noBuzzerBoards.contains(board);

class BoardCaps {
  const BoardCaps({required this.board, required this.connected, required this.manager});

  final String board;
  final bool connected;
  final bool manager;

  Cap get _c5 => !connected
      ? const Cap.off('Needs an ESP32-C5 board. Connect one to use this.')
      : boardHas802154(board)
          ? const Cap.on()
          : const Cap.off('Needs an ESP32-C5 board. The connected board is not one.');

  Cap get wifi5Ghz => _c5;
  Cap get ieee802154 => _c5;

  Cap get buzzer => boardHasBuzzer(board)
      ? const Cap.on()
      : const Cap.off('This board has no buzzer.');

  Cap get managerOnly => manager
      ? const Cap.on()
      : Cap.off(connected
          ? 'Needs a manager board. The connected board is a single node.'
          : 'Needs a manager board. Connect to one to use this.');

  @override
  bool operator ==(Object other) =>
      other is BoardCaps &&
      other.board == board &&
      other.connected == connected &&
      other.manager == manager;

  @override
  int get hashCode => Object.hash(board, connected, manager);
}

final boardCapsProvider = Provider<BoardCaps>((ref) {
  final app = ref.watch(appStateProvider);
  final ble = ref.read(bleManagerProvider);
  return BoardCaps(
    board: ble.board,
    connected: app.isConnected,
    manager: app.isManagerConnected,
  );
});
