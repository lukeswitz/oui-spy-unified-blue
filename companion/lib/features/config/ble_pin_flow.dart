// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/widgets/text_prompt_dialog.dart';

Future<void> changeBlePin(BuildContext context, BleManager ble) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final pin = await showDialog<String>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: 'Bluetooth PIN',
      confirmLabel: 'SAVE',
      message: 'Six digits, not starting with 0, and not ${BleProtocol.blePinDefault}. '
          'Phones already paired stay paired. A new phone enters this PIN when it pairs.',
      labelText: 'New PIN',
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      isValid: BleProtocol.blePinChosen,
    ),
  );
  if (pin == null) return;
  bool? ok;
  try {
    ok = await ble.setBlePin(int.parse(pin));
  } catch (e) {
    DebugLog.log('CONFIG: setBlePin failed: $e');
  }
  messenger?.showSnackBar(SnackBar(
    content: Text(switch (ok) {
      true => 'PIN saved. Use it the next time a phone pairs.',
      false => 'The board refused the PIN.',
      null => 'The board did not answer. Update its firmware, then try again.',
    }),
  ));
}

Future<void> showSetPinPrompt(BuildContext context, BleManager ble) async {
  final setPin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set your own Bluetooth PIN'),
      content: const Text('This board still uses the default PIN, ${BleProtocol.blePinDefault}. '
          'Set your own so only people you tell can pair a phone with it.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('LATER')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SET PIN')),
      ],
    ),
  );
  if (setPin == true && context.mounted) await changeBlePin(context, ble);
}
