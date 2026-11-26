// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

const fpvChannelCount = 48;
const fpvPerBand = 8;
const fpvBandLetters = ['A', 'B', 'E', 'F', 'R', 'L'];
const fpvTuneMinMhz = 5180;
const fpvTuneMaxMhz = 5885;
const fpvNoLevel = 0xFF;
const fpvStateLen = 124;
const fpvStateVersion = 1;

const fpvFreqMhz = <int>[
  5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725,
  5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866,
  5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945,
  5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880,
  5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917,
  5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621,
];

const fpvBandNames = <String>[
  'Boscam A',
  'Boscam B',
  'Boscam E',
  'FatShark',
  'RaceBand',
  'LowBand',
];

const fpvDetectionMethod = 'odid_fpv';
const fpvMinCoherence = 40;
const fpvDefaultThreshold = 12;
const fpvMinThreshold = 4;
const fpvMaxThreshold = 80;

const fpvBleedMhz = 19;

Set<int> fpvBleedChannels(List<int> levels, bool Function(int) supported) {
  final order = [
    for (var i = 0; i < fpvChannelCount && i < levels.length; i++)
      if (supported(i) && levels[i] != fpvNoLevel) i,
  ];
  for (var a = 1; a < order.length; a++) {
    final key = order[a];
    var b = a;
    while (b > 0 && levels[order[b - 1]] < levels[key]) {
      order[b] = order[b - 1];
      b--;
    }
    order[b] = key;
  }
  final peaks = <int>[];
  final bleed = <int>{};
  for (final i in order) {
    if (peaks.any((j) => (fpvFreqMhz[j] - fpvFreqMhz[i]).abs() < fpvBleedMhz)) {
      bleed.add(i);
    } else {
      peaks.add(i);
    }
  }
  return bleed;
}

enum FpvMode { off, stop, scan, sweep, hop }

class FpvOp {
  const FpvOp._();
  static const enter = 0x01;
  static const leave = 0x02;
  static const mode = 0x03;
  static const tune = 0x04;
  static const step = 0x05;
  static const threshold = 0x06;
}

class FpvError {
  const FpvError._();
  static const none = 0;
  static const unsupported = 1;
  static const mesh = 2;
  static const radio = 3;
  static const capture = 4;
  static const tune = 5;
  static const noSignal = 6;

  static String label(int code) => switch (code) {
        unsupported => 'Channel is outside the 5180-5885 MHz receive window',
        mesh => 'Mesh or ESP-NOW hub is on and owns the radio',
        radio => 'Radio setup failed',
        capture => 'No valid samples from the receiver',
        tune => 'Tuning failed',
        noSignal => 'No signal',
        _ => '',
      };
}

bool fpvSupportedMhz(int mhz) => mhz >= fpvTuneMinMhz && mhz <= fpvTuneMaxMhz;

bool fpvChannelSupported(int idx) =>
    idx >= 0 && idx < fpvChannelCount && fpvSupportedMhz(fpvFreqMhz[idx]);

int fpvChannelMhz(int idx) =>
    idx >= 0 && idx < fpvChannelCount ? fpvFreqMhz[idx] : 0;

String fpvChannelName(int idx) {
  if (idx < 0 || idx >= fpvChannelCount) return '--';
  return '${fpvBandLetters[idx ~/ fpvPerBand]}${idx % fpvPerBand + 1}';
}

int? fpvStepChannel(int from, int dir) {
  final step = dir >= 0 ? 1 : -1;
  var i = from >= 0 && from < fpvChannelCount
      ? from
      : (step > 0 ? fpvChannelCount - 1 : 0);
  for (var n = 0; n < fpvChannelCount; n++) {
    i = (i + step + fpvChannelCount) % fpvChannelCount;
    if (fpvChannelSupported(i)) return i;
  }
  return null;
}

int fpvSupportedCount() {
  var n = 0;
  for (var i = 0; i < fpvChannelCount; i++) {
    if (fpvChannelSupported(i)) n++;
  }
  return n;
}

bool fpvIsTransmitter(int level, int coherence, int floor, int threshold) {
  if (level == fpvNoLevel) return false;
  return level >= floor + threshold && coherence >= fpvMinCoherence;
}

int fpvRssiToLevel(int rssi) => ((rssi + 128) * 2).clamp(0, 254);

Uint8List fpvEncodeEnter([FpvMode mode = FpvMode.scan]) =>
    Uint8List.fromList([FpvOp.enter, mode.index]);

Uint8List fpvEncodeLeave() => Uint8List.fromList([FpvOp.leave]);

Uint8List fpvEncodeMode(FpvMode mode) =>
    Uint8List.fromList([FpvOp.mode, mode.index]);

Uint8List fpvEncodeTune(int channel) =>
    Uint8List.fromList([FpvOp.tune, channel & 0xFF]);

Uint8List fpvEncodeStep(int dir) =>
    Uint8List.fromList([FpvOp.step, dir >= 0 ? 1 : 0xFF]);

Uint8List fpvEncodeThreshold(int threshold) => Uint8List.fromList(
    [FpvOp.threshold, threshold.clamp(fpvMinThreshold, fpvMaxThreshold)]);

/// Mirrors firmware fpv::State in src/engines/fpv_logic.h (124 bytes, little-endian).
class FpvState {
  const FpvState({
    required this.flags,
    required this.mode,
    required this.channel,
    required this.mhz,
    required this.level,
    required this.coherence,
    required this.floor,
    required this.threshold,
    required this.flaggedCount,
    required this.error,
    required this.passes,
    required this.supportedMask,
    required this.flaggedMask,
    required this.levels,
    required this.coherences,
  });

  final int flags;
  final int mode;
  final int channel;
  final int mhz;
  final int level;
  final int coherence;
  final int floor;
  final int threshold;
  final int flaggedCount;
  final int error;
  final int passes;
  final int supportedMask;
  final int flaggedMask;
  final List<int> levels;
  final List<int> coherences;

  static final empty = FpvState(
    flags: 0,
    mode: 0,
    channel: 0,
    mhz: fpvFreqMhz[0],
    level: 0,
    coherence: 0,
    floor: 0,
    threshold: fpvDefaultThreshold,
    flaggedCount: 0,
    error: 0,
    passes: 0,
    supportedMask: 0,
    flaggedMask: 0,
    levels: List<int>.filled(fpvChannelCount, fpvNoLevel),
    coherences: List<int>.filled(fpvChannelCount, 0),
  );

  bool get active => flags & 0x01 != 0;
  bool get locked => flags & 0x02 != 0;
  bool get channelFlagged => flags & 0x04 != 0;
  bool get parked => flags & 0x08 != 0;
  bool get hasError => flags & 0x10 != 0;
  FpvMode get modeEnum =>
      mode >= 0 && mode < FpvMode.values.length ? FpvMode.values[mode] : FpvMode.off;

  bool isSupported(int idx) =>
      idx >= 0 && idx < fpvChannelCount && (supportedMask >> idx) & 1 == 1;
  bool isFlagged(int idx) =>
      idx >= 0 && idx < fpvChannelCount && (flaggedMask >> idx) & 1 == 1;
  int? levelOf(int idx) {
    if (idx < 0 || idx >= fpvChannelCount) return null;
    final v = levels[idx];
    return v == fpvNoLevel ? null : v;
  }

  Set<int> get bleedChannels => fpvBleedChannels(levels, isSupported);

  List<int> get flaggedChannels => [
        for (var i = 0; i < fpvChannelCount; i++)
          if (isFlagged(i)) i,
      ]..sort((a, b) => (levels[b]).compareTo(levels[a]));

  static int _mask48(Uint8List b, int off) {
    var m = 0;
    for (var i = 0; i < 6; i++) {
      m |= b[off + i] << (8 * i);
    }
    return m;
  }

  static FpvState? decode(List<int> data) {
    if (data.length < fpvStateLen || data[0] != fpvStateVersion) return null;
    final b = Uint8List.fromList(data);
    final v = ByteData.sublistView(b);
    return FpvState(
      flags: b[1],
      mode: b[2],
      channel: b[3],
      mhz: v.getUint16(4, Endian.little),
      level: b[6],
      coherence: b[7],
      floor: b[8],
      threshold: b[9],
      flaggedCount: b[10],
      error: b[11],
      passes: v.getUint32(12, Endian.little),
      supportedMask: _mask48(b, 16),
      flaggedMask: _mask48(b, 22),
      levels: List<int>.unmodifiable(b.sublist(28, 28 + fpvChannelCount)),
      coherences: List<int>.unmodifiable(b.sublist(76, 76 + fpvChannelCount)),
    );
  }
}
