// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';

const pinHintLine = 'PIN ${BleProtocol.blePinDefault} unless you changed it';

class PinPromptGate {
  final Set<String> _answered = {};

  bool shouldPrompt({required String nodeId, required bool? pinIsDefault}) =>
      pinIsDefault == true && nodeId.isNotEmpty && !_answered.contains(nodeId);

  void answered(String nodeId) => _answered.add(nodeId);
}

final pinPromptGateProvider = Provider<PinPromptGate>((ref) => PinPromptGate());
