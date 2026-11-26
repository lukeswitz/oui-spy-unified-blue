// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';

enum PairingFailure {
  refused('This board is not taking new phones. Restart it, then pair within 2 minutes.'),
  wrongPin('Wrong PIN. Try again; a new board uses ${BleProtocol.blePinDefault}.'),
  unclear('Pairing failed. Check the PIN (a new board uses ${BleProtocol.blePinDefault}). '
      'If the board is not new, restart it and pair within 2 minutes.');

  const PairingFailure(this.message);
  final String message;

  static const androidRemoteTerminated = 19;
  static const _appleDisconnectCodes = {7, 14, 15};

  static PairingFailure? classify({required bool android, required Object error, int? disconnectCode}) {
    if (error is! FlutterBluePlusException) return null;
    final code = error.code;
    final droppedByBoard =
        error.platform == ErrorPlatform.fbp && code == FbpErrorCode.deviceIsDisconnected.index;
    if (android) {
      if (error.function == 'createBond' && (error.description ?? '').startsWith('Failed to create bond')) {
        return wrongPin;
      }
      final terminated = droppedByBoard ||
          (error.platform == ErrorPlatform.android && code == androidRemoteTerminated);
      return terminated && disconnectCode == androidRemoteTerminated ? refused : null;
    }
    if (droppedByBoard) {
      return _appleDisconnectCodes.contains(disconnectCode) ? unclear : null;
    }
    if (error.platform != ErrorPlatform.apple) return null;
    if (_appleDisconnectCodes.contains(code)) return unclear;
    return error.function == 'readCharacteristic' && code == 5 ? unclear : null;
  }
}
