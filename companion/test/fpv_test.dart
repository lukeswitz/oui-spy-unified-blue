// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/features/fpv/fpv_screen.dart';
import 'package:oui_spy/features/fpv/fpv_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

const _golden =
    '0103030499163c520a0c020004030201ffff1fff7fff10020000000000050a0f14191e23282d32373c41464b50555a5f64'
    'ffffff787d82878c91969ba0a5aaafb4b9beff00050a0f14191e2300070e151c232a31383f464d545b62040b12192027'
    '000000434a51585f01080f161d242b323940004e555c63050c131a';

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
    ];

Uint8List _fpvDetection({required int idx, required int level, required int coh}) {
  final b = Uint8List(155);
  final v = ByteData.sublistView(b);
  final f = fpvFreqMhz[idx];
  b[0] = 4;
  b.setAll(1, [0x02, 0x46, 0x50, 0x56, f >> 8, f & 0xFF]);
  v.setInt8(7, (level ~/ 2) - 128);
  b[8] = idx + 1;
  v.setUint32(9, 1234, Endian.little);
  b[13] = 4;
  b.setAll(14, 'AABBC'.codeUnits);
  final id = 'FPV ${fpvChannelName(idx)} $f'.codeUnits;
  b.setAll(19, id);
  final self = 'analog video coh $coh%'.codeUnits;
  b.setAll(101, self);
  v.setInt16(77, -1000, Endian.little);
  v.setInt16(79, -1000, Endian.little);
  v.setInt16(81, 255, Endian.little);
  v.setInt16(83, 361, Endian.little);
  v.setInt16(125, -1000, Endian.little);
  v.setInt16(127, 63, Endian.little);
  v.setInt16(129, -1000, Endian.little);
  v.setInt16(135, -1000, Endian.little);
  v.setInt16(137, -1000, Endian.little);
  v.setUint16(139, 0xFFFF, Endian.little);
  return b;
}

FpvState _goldenState() => FpvState.decode(_hex(_golden))!;

void main() {
  group('channel table', () {
    test('48 channels with the standard names and frequencies', () {
      expect(fpvFreqMhz.length, fpvChannelCount);
      expect(fpvChannelName(0), 'A1');
      expect(fpvChannelMhz(0), 5865);
      expect(fpvChannelName(8), 'B1');
      expect(fpvChannelMhz(8), 5733);
      expect(fpvChannelName(20), 'E5');
      expect(fpvChannelMhz(20), 5885);
      expect(fpvChannelName(24), 'F1');
      expect(fpvChannelName(36), 'R5');
      expect(fpvChannelMhz(36), 5806);
      expect(fpvChannelName(47), 'L8');
      expect(fpvChannelMhz(47), 5621);
      expect(fpvChannelName(48), '--');
      expect(fpvChannelMhz(-1), 0);
    });

    test('44 channels are tunable and R8, E6, E7, E8 are listed as unsupported', () {
      expect(fpvSupportedCount(), 44);
      for (final i in [21, 22, 23, 39]) {
        expect(fpvChannelSupported(i), isFalse, reason: fpvChannelName(i));
      }
      expect(fpvChannelMhz(39), 5917);
      expect(fpvChannelMhz(21), 5905);
      expect(fpvChannelMhz(22), 5925);
      expect(fpvChannelMhz(23), 5945);
      for (var i = 0; i < fpvChannelCount; i++) {
        if (fpvChannelSupported(i)) {
          expect(fpvChannelMhz(i), inInclusiveRange(5180, 5885));
        }
      }
      expect(fpvSupportedMhz(5885), isTrue);
      expect(fpvSupportedMhz(5886), isFalse);
      expect(fpvSupportedMhz(5179), isFalse);
    });

    test('stepping skips unsupported channels and wraps', () {
      expect(fpvStepChannel(0, 1), 1);
      expect(fpvStepChannel(0, -1), 47);
      expect(fpvStepChannel(47, 1), 0);
      expect(fpvStepChannel(20, 1), 24);
      expect(fpvStepChannel(24, -1), 20);
      expect(fpvStepChannel(38, 1), 40);
      expect(fpvStepChannel(40, -1), 38);
      expect(fpvStepChannel(21, 1), 24);
      expect(fpvStepChannel(21, -1), 20);
    });
  });

  group('flag logic', () {
    test('needs level over the floor plus threshold and a steady carrier', () {
      expect(fpvIsTransmitter(30, 60, 10, 12), isTrue);
      expect(fpvIsTransmitter(22, 40, 10, 12), isTrue);
      expect(fpvIsTransmitter(21, 60, 10, 12), isFalse);
      expect(fpvIsTransmitter(60, 39, 10, 12), isFalse);
      expect(fpvIsTransmitter(fpvNoLevel, 100, 0, 0), isFalse);
    });

    test('level and pseudo RSSI convert both ways', () {
      expect(fpvRssiToLevel(-128), 0);
      expect(fpvRssiToLevel(-1), 254);
      for (var l = 0; l <= 254; l += 2) {
        expect(fpvRssiToLevel((l ~/ 2) - 128), l);
      }
    });
  });

  group('state packet', () {
    test('decodes the packet the firmware test produces', () {
      final s = _goldenState();
      expect(s.active, isTrue);
      expect(s.locked, isTrue);
      expect(s.channelFlagged, isFalse);
      expect(s.modeEnum, FpvMode.sweep);
      expect(s.channel, 4);
      expect(s.mhz, 5785);
      expect(s.level, 60);
      expect(s.coherence, 82);
      expect(s.floor, 10);
      expect(s.threshold, 12);
      expect(s.flaggedCount, 2);
      expect(s.error, 0);
      expect(s.passes, 0x01020304);
      expect(s.supportedMask, 0xFF7FFF1FFFFF);
      expect(s.flaggedMask, (1 << 4) | (1 << 9));
      expect(s.isFlagged(4), isTrue);
      expect(s.isFlagged(5), isFalse);
      expect(s.flaggedChannels, [9, 4]);
      for (var i = 0; i < fpvChannelCount; i++) {
        expect(s.isSupported(i), fpvChannelSupported(i), reason: fpvChannelName(i));
      }
      expect(s.levelOf(0), 0);
      expect(s.levelOf(1), 5);
      expect(s.levelOf(21), isNull);
      expect(s.levelOf(48), isNull);
      expect(s.coherences[1], 7);
    });

    test('rejects a wrong version or a short packet', () {
      final bytes = _hex(_golden);
      expect(FpvState.decode(bytes.sublist(0, fpvStateLen - 1)), isNull);
      final bad = [...bytes]..[0] = 2;
      expect(FpvState.decode(bad), isNull);
      expect(FpvState.decode(const []), isNull);
      expect(bytes.length, fpvStateLen);
    });

    test('control commands encode the documented opcodes', () {
      expect(fpvEncodeEnter(), [1, 2]);
      expect(fpvEncodeEnter(FpvMode.sweep), [1, 3]);
      expect(fpvEncodeLeave(), [2]);
      expect(fpvEncodeMode(FpvMode.hop), [3, 4]);
      expect(fpvEncodeMode(FpvMode.stop), [3, 1]);
      expect(fpvEncodeTune(12), [4, 12]);
      expect(fpvEncodeStep(1), [5, 1]);
      expect(fpvEncodeStep(-1), [5, 0xFF]);
      expect(fpvEncodeThreshold(12), [6, 12]);
      expect(fpvEncodeThreshold(500), [6, fpvMaxThreshold]);
      expect(fpvEncodeThreshold(0), [6, fpvMinThreshold]);
    });

    test('error codes have readable text', () {
      expect(FpvError.label(FpvError.mesh), contains('Mesh'));
      expect(FpvError.label(FpvError.none), '');
    });
  });

  group('detections', () {
    test('an FPV detection decodes as a Sky Spy drone with no position', () {
      final f = _fpvDetection(idx: 0, level: 120, coh: 82);
      final d = BleProtocol.decodeDetection(f, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026));
      expect(d.engine, Engine.skySpy);
      expect(d.method, fpvDetectionMethod);
      expect(d.odid!.uavId, 'FPV A1 5865');
      expect(d.odid!.selfId, 'analog video coh 82%');
      expect(d.odid!.altitudeMsl, isNull);
      expect(d.odid!.droneSpeed, isNull);
      expect(d.odid!.droneHeading, isNull);
      expect(d.odid!.locTimestamp, isNull);
      expect(fpvRssiToLevel(d.rssi), 120);
      expect(d.isWifiDetection, isTrue);
      expect(d.isBleDetection, isFalse);
    });
  });

  group('screen widgets', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets('heat map taps tune a supported channel and ignore unsupported ones', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(host(FpvHeatMap(state: _goldenState(), onTune: taps.add)));
      await tester.tap(find.byKey(const ValueKey('fpv-cell-3')));
      await tester.tap(find.byKey(const ValueKey('fpv-cell-39')));
      await tester.tap(find.byKey(const ValueKey('fpv-cell-21')));
      expect(taps, [3]);
      expect(find.text('N/A'), findsNWidgets(4));
      expect(find.byIcon(Icons.bolt), findsNWidgets(2));
    });

    testWidgets('transmitter list shows the flagged channels strongest first and tunes on tap', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(host(FpvFlaggedList(state: _goldenState(), onTune: taps.add)));
      expect(find.text('B2'), findsOneWidget);
      expect(find.text('A5'), findsOneWidget);
      expect(tester.getTopLeft(find.text('B2')).dy, lessThan(tester.getTopLeft(find.text('A5')).dy));
      await tester.tap(find.byKey(const ValueKey('fpv-flag-4')));
      expect(taps, [4]);
    });

    testWidgets('state card shows lock state and channel', (tester) async {
      await tester.pumpWidget(host(Builder(
        builder: (context) => FpvStateCard(state: _goldenState(), t: AppTheme.of(context)),
      )));
      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.textContaining('A5'), findsWidgets);
      expect(find.textContaining('5785'), findsWidgets);
    });

    testWidgets('mode selector reports taps', (tester) async {
      final modes = <FpvMode>[];
      await tester.pumpWidget(host(FpvModeSelector(mode: FpvMode.scan, onChanged: modes.add)));
      await tester.tap(find.byKey(const ValueKey('fpv-mode-hop')));
      await tester.tap(find.byKey(const ValueKey('fpv-mode-stop')));
      expect(modes, [FpvMode.hop, FpvMode.stop]);
    });

    test('state labels follow active, locked and mode', () {
      expect(fpvStateLabel(FpvState.empty), 'OFF');
      expect(fpvStateLabel(_goldenState()), 'LOCKED');
      expect(fpvHeat(null, 10), 0);
      expect(fpvHeat(10, 10), 0);
      expect(fpvHeat(60, 10), 0.5);
      expect(fpvHeat(250, 10), 1);
    });
  });
}
