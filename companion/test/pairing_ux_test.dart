// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/pairing_failure.dart';
import 'package:oui_spy/core/ble/pin_prompt.dart';
import 'package:oui_spy/features/config/ble_pin_flow.dart';

FlutterBluePlusException _fbp(ErrorPlatform p, String fn, int? code, String? d) =>
    FlutterBluePlusException(p, fn, code, d);

void main() {
  group('device info pin flag', () {
    test('pindef=1 is default, pindef=0 is set', () {
      final on = BleManager.deviceInfoKeyed(['0.7.0', 'OUISPY-ABCD', 'xiao_s3', 'node', '1', 'proto=2', 'spool=1', 'pindef=1']);
      final off = BleManager.deviceInfoKeyed(['0.7.0', 'OUISPY-ABCD', 'xiao_s3', 'node', '1', 'proto=2', 'pindef=0']);
      expect(BleManager.pinIsDefaultFromInfo(on), isTrue);
      expect(BleManager.pinIsDefaultFromInfo(off), isFalse);
    });

    test('old firmware without the field or a bad value is unknown', () {
      final old = BleManager.deviceInfoKeyed(['0.7.0', 'OUISPY-ABCD', 'xiao_s3', 'node', '1', 'proto=2', 'epoch=0a1b2c3d', 'boot=17', 'spool=1']);
      expect(BleManager.pinIsDefaultFromInfo(old), isNull);
      expect(BleManager.pinIsDefaultFromInfo({'pindef': 'x'}), isNull);
    });

    test('the board never reports a PIN value', () {
      final kv = BleManager.deviceInfoKeyed(['0.7.0', 'OUISPY-ABCD', 'xiao_s3', 'node', '1', 'pindef=1']);
      expect(kv.keys.any((k) => k == 'pin'), isFalse);
    });
  });

  group('PIN choice', () {
    test('the default PIN is not accepted as your own', () {
      expect(BleProtocol.blePinChosen('123456'), isFalse);
      expect(BleProtocol.blePinChosen('654321'), isTrue);
      expect(BleProtocol.blePinChosen('012345'), isFalse);
    });

    test('hint line names the default PIN', () {
      expect(pinHintLine, 'PIN 123456 unless you changed it');
    });
  });

  group('PinPromptGate', () {
    test('prompts only for a known default PIN on an identified board', () {
      final g = PinPromptGate();
      expect(g.shouldPrompt(nodeId: 'OUISPY-ABCD', pinIsDefault: true), isTrue);
      expect(g.shouldPrompt(nodeId: 'OUISPY-ABCD', pinIsDefault: false), isFalse);
      expect(g.shouldPrompt(nodeId: 'OUISPY-ABCD', pinIsDefault: null), isFalse);
      expect(g.shouldPrompt(nodeId: '', pinIsDefault: true), isFalse);
    });

    test('LATER suppresses that board only', () {
      final g = PinPromptGate()..answered('OUISPY-ABCD');
      expect(g.shouldPrompt(nodeId: 'OUISPY-ABCD', pinIsDefault: true), isFalse);
      expect(g.shouldPrompt(nodeId: 'OUISPY-1234', pinIsDefault: true), isTrue);
    });

    test('a new gate (next app start) prompts again', () {
      expect(PinPromptGate().shouldPrompt(nodeId: 'OUISPY-ABCD', pinIsDefault: true), isTrue);
    });
  });

  group('pairing failure classification', () {
    test('Android bond failure is a wrong PIN', () {
      final e = _fbp(ErrorPlatform.fbp, 'createBond', 12345, 'Failed to create bond. BmBondStateEnum.none');
      expect(PairingFailure.classify(android: true, error: e, disconnectCode: null), PairingFailure.wrongPin);
    });

    test('Android board hang-up with remote-terminated reason is a refusal', () {
      final e = _fbp(ErrorPlatform.fbp, 'createBond', FbpErrorCode.deviceIsDisconnected.index, 'device is not connected');
      expect(PairingFailure.classify(android: true, error: e, disconnectCode: 19), PairingFailure.refused);
      final native = _fbp(ErrorPlatform.android, 'connect', 19, 'REMOTE_USER_TERMINATED_CONNECTION');
      expect(PairingFailure.classify(android: true, error: native, disconnectCode: 19), PairingFailure.refused);
    });

    test('Android drops for other reasons and timeouts stay unclassified', () {
      final dropped = _fbp(ErrorPlatform.fbp, 'createBond', FbpErrorCode.deviceIsDisconnected.index, 'device is not connected');
      expect(PairingFailure.classify(android: true, error: dropped, disconnectCode: 8), isNull);
      expect(PairingFailure.classify(android: true, error: dropped, disconnectCode: null), isNull);
      final timeout = _fbp(ErrorPlatform.fbp, 'createBond', FbpErrorCode.timeout.index, 'Timed out after 90s');
      expect(PairingFailure.classify(android: true, error: timeout, disconnectCode: null), isNull);
      expect(PairingFailure.classify(android: true, error: Exception('x'), disconnectCode: 19), isNull);
    });

    test('iOS pairing-shaped errors give the combined message, other errors none', () {
      final removed = _fbp(ErrorPlatform.apple, 'readCharacteristic', 14, 'Peer removed pairing information');
      expect(PairingFailure.classify(android: false, error: removed, disconnectCode: null), PairingFailure.unclear);
      final auth = _fbp(ErrorPlatform.apple, 'readCharacteristic', 5, 'Authentication is insufficient');
      expect(PairingFailure.classify(android: false, error: auth, disconnectCode: null), PairingFailure.unclear);
      final gone = _fbp(ErrorPlatform.fbp, 'readCharacteristic', FbpErrorCode.deviceIsDisconnected.index, 'Device is disconnected');
      expect(PairingFailure.classify(android: false, error: gone, disconnectCode: 7), PairingFailure.unclear);
      expect(PairingFailure.classify(android: false, error: gone, disconnectCode: 6), isNull);
      final canceled = _fbp(ErrorPlatform.apple, 'connect', 5, 'canceled');
      expect(PairingFailure.classify(android: false, error: canceled, disconnectCode: null), isNull);
    });

    test('messages match the requested wording', () {
      expect(PairingFailure.refused.message, 'This board is not taking new phones. Restart it, then pair within 2 minutes.');
      expect(PairingFailure.wrongPin.message, 'Wrong PIN. Try again; a new board uses 123456.');
      expect(PairingFailure.unclear.message, contains('123456'));
    });
  });

  group('set PIN prompt', () {
    Future<void> open(WidgetTester tester, BleManager ble) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(onPressed: () => showSetPinPrompt(ctx, ble), child: const Text('go')),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows both actions and LATER closes it', (tester) async {
      await open(tester, BleManager());
      expect(find.text('Set your own Bluetooth PIN'), findsOneWidget);
      expect(find.text('SET PIN'), findsOneWidget);
      expect(find.text('LATER'), findsOneWidget);
      await tester.tap(find.text('LATER'));
      await tester.pumpAndSettle();
      expect(find.text('Set your own Bluetooth PIN'), findsNothing);
      expect(find.text('Bluetooth PIN'), findsNothing);
    });

    testWidgets('SET PIN opens the existing PIN entry and rejects the default', (tester) async {
      await open(tester, BleManager());
      await tester.tap(find.text('SET PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth PIN'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '654321');
      await tester.pump();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE')).onPressed, isNotNull);
    });
  });
}
