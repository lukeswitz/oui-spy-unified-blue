import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';

const int melodyMaxNotes = 8;
const int melodyAny = 0xFF;
const int melodyEngineAxon = 0xFE;
const int melodyOpClearAll = 0x03;
const int melodyOpPreview = 0x04;
const int melodyOpSync = 0x05;
const String melodySilent = 'silent';

class MelodyNote {
  const MelodyNote(this.midi, this.onMs, this.gapMs);

  final int midi;
  final int onMs;
  final int gapMs;

  static const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  String get label => midi == 0 ? 'rest' : '${names[midi % 12]}${midi ~/ 12 - 1}';

  List<int> encode() => [
        midi.clamp(0, 127),
        (onMs ~/ 10).clamp(0, 255),
        (gapMs ~/ 10).clamp(0, 255),
      ];

  Map<String, dynamic> toJson() => {'m': midi, 'on': onMs, 'gap': gapMs};

  factory MelodyNote.fromJson(Map<String, dynamic> j) =>
      MelodyNote(j['m'] as int, j['on'] as int, j['gap'] as int);
}

class Melody {
  Melody({required this.id, required this.name, required this.notes, this.builtIn = false});

  final String id;
  String name;
  List<MelodyNote> notes;
  final bool builtIn;

  List<int> encodeNotes() => [
        for (final n in notes.take(melodyMaxNotes)) ...n.encode(),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  factory Melody.fromJson(Map<String, dynamic> j) => Melody(
        id: j['id'] as String,
        name: j['name'] as String,
        notes: (j['notes'] as List)
            .map((e) => MelodyNote.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AlertSlot {
  const AlertSlot(this.engine, this.method, this.label);

  final int engine;
  final int method;
  final String label;

  String get key => '$engine:$method';
}

const kAlertSlots = <AlertSlot>[
  AlertSlot(melodyAny, melodyAny, 'All other alerts'),
  AlertSlot(0, 0, 'BLE watchlist'),
  AlertSlot(0, 1, 'WiFi watchlist'),
  AlertSlot(0, 2, 'Tracker / AirTag'),
  AlertSlot(0, 3, 'Flipper'),
  AlertSlot(0, 4, 'Deauth'),
  AlertSlot(0, 5, 'Probe flood'),
  AlertSlot(0, 6, 'Pwnagotchi'),
  AlertSlot(0, 7, 'Meta glasses'),
  AlertSlot(0, 8, 'Axon: appeared'),
  AlertSlot(melodyEngineAxon, 1, 'Axon: still near (heartbeat)'),
  AlertSlot(melodyEngineAxon, 2, 'Axon: lost'),
  AlertSlot(0, 9, 'Security camera'),
  AlertSlot(0, 10, 'Amazon Sidewalk'),
  AlertSlot(1, melodyAny, 'Flock BLE'),
  AlertSlot(2, melodyAny, 'Flock WiFi'),
  AlertSlot(4, melodyAny, 'Drone Remote ID'),
  AlertSlot(5, melodyAny, 'UniPwn'),
];

final kBuiltInMelodies = <Melody>[
  Melody(id: 'chime', name: 'Chime', builtIn: true, notes: const [
    MelodyNote(88, 50, 20), MelodyNote(92, 50, 20), MelodyNote(95, 50, 20),
  ]),
  Melody(id: 'arpeggio', name: 'Arpeggio', builtIn: true, notes: const [
    MelodyNote(72, 70, 30), MelodyNote(76, 70, 30), MelodyNote(79, 70, 30),
    MelodyNote(84, 70, 30), MelodyNote(88, 80, 60),
  ]),
  Melody(id: 'lubdub', name: 'Lub-dub', builtIn: true, notes: const [
    MelodyNote(72, 60, 40), MelodyNote(67, 110, 30),
  ]),
  Melody(id: 'falling', name: 'Falling', builtIn: true, notes: const [
    MelodyNote(76, 150, 80), MelodyNote(64, 260, 40),
  ]),
  Melody(id: 'siren', name: 'Siren', builtIn: true, notes: const [
    MelodyNote(84, 120, 0), MelodyNote(79, 120, 0), MelodyNote(84, 120, 0), MelodyNote(79, 120, 0),
  ]),
  Melody(id: 'blip', name: 'Blip', builtIn: true, notes: const [
    MelodyNote(96, 40, 0),
  ]),
  Melody(id: 'triple', name: 'Triple beep', builtIn: true, notes: const [
    MelodyNote(81, 60, 60), MelodyNote(81, 60, 60), MelodyNote(81, 60, 60),
  ]),
];

class MelodyState extends ChangeNotifier {
  MelodyState() {
    _load();
  }

  static const _prefsMelodies = 'melodies_v1';
  static const _prefsAssign = 'melody_assign_v1';

  final List<Melody> _custom = [];
  final Map<String, String> _assign = {};
  VoidCallback? onChanged;

  List<Melody> get melodies => [...kBuiltInMelodies, ..._custom];

  Melody? byId(String id) {
    for (final m in melodies) {
      if (m.id == id) return m;
    }
    return null;
  }

  String? assignmentFor(AlertSlot s) => _assign[s.key];

  Future<void> assign(AlertSlot s, String? melodyId) async {
    if (melodyId == null) {
      _assign.remove(s.key);
    } else {
      _assign[s.key] = melodyId;
    }
    await _save();
  }

  Future<void> saveMelody(Melody m) async {
    final i = _custom.indexWhere((e) => e.id == m.id);
    if (i >= 0) {
      _custom[i] = m;
    } else {
      _custom.add(m);
    }
    await _save();
  }

  Future<void> deleteMelody(String id) async {
    _custom.removeWhere((e) => e.id == id);
    _assign.removeWhere((_, v) => v == id);
    await _save();
  }

  List<Uint8List> serializeForFirmware() {
    final entries = <List<int>>[];
    for (final slot in kAlertSlots) {
      final id = _assign[slot.key];
      if (id == null) continue;
      final List<int> notes;
      if (id == melodySilent) {
        notes = const [];
      } else {
        final m = byId(id);
        if (m == null) continue;
        notes = m.encodeNotes();
      }
      entries.add([slot.engine, slot.method, notes.length ~/ 3, ...notes]);
    }
    if (entries.isEmpty) return [Uint8List.fromList([melodyOpClearAll])];
    return [
      for (var i = 0; i < entries.length; i++)
        Uint8List.fromList([melodyOpSync, i, entries.length, ...entries[i]]),
    ];
  }

  static Uint8List previewOp(List<MelodyNote> notes) {
    final enc = [for (final n in notes.take(melodyMaxNotes)) ...n.encode()];
    return Uint8List.fromList([melodyOpPreview, enc.length ~/ 3, ...enc]);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final m = prefs.getString(_prefsMelodies);
      if (m != null) {
        _custom
          ..clear()
          ..addAll((jsonDecode(m) as List)
              .map((e) => Melody.fromJson(e as Map<String, dynamic>)));
      }
      final a = prefs.getString(_prefsAssign);
      if (a != null) {
        _assign
          ..clear()
          ..addAll((jsonDecode(a) as Map<String, dynamic>).cast<String, String>());
      }
    } on FormatException catch (e) {
      DebugLog.log('Melody: stored prefs unreadable: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsMelodies, jsonEncode(_custom.map((e) => e.toJson()).toList()));
    await prefs.setString(_prefsAssign, jsonEncode(_assign));
    onChanged?.call();
  }
}

final melodyProvider = ChangeNotifierProvider<MelodyState>((ref) {
  final state = MelodyState();
  final ble = ref.read(bleManagerProvider);
  state.onChanged = () => ble.writeMelodyOps(state.serializeForFirmware());
  final sub = ble.connectionState.listen((s) {
    if (s == NodeConnectionState.ready) {
      ble.writeMelodyOps(state.serializeForFirmware());
    }
  });
  ref.onDispose(sub.cancel);
  return state;
});
