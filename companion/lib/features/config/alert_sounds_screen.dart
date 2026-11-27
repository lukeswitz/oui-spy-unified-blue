// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/melody_state.dart';
import 'package:oui_spy/core/notifications/alert_gate.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';

void _preview(WidgetRef ref, List<MelodyNote> notes) {
  ref.read(bleManagerProvider).writeMelodyOps([MelodyState.previewOp(notes)]);
}

const _groups = <(String, List<String>)>[
  ('Watchlist', ['0:0', '0:1']),
  ('Trackers and devices', ['0:2', '0:3', '0:6', '0:7', '0:9', '0:10', '0:17', '0:18']),
  ('Attacks', ['0:4', '0:5', '5:255']),
  ('Flock', ['1:255', '2:255']),
  ('Drones', ['0:19', '4:255']),
  ('Body cameras', ['0:8', '254:1', '254:2']),
];

IconData _slotIcon(String key) => switch (key) {
      '0:0' => Icons.bluetooth_searching,
      '0:1' => Icons.wifi_find,
      '0:2' => Icons.track_changes,
      '0:3' => Icons.memory,
      '0:4' => Icons.wifi_off,
      '0:5' => Icons.waves,
      '0:6' => Icons.pets,
      '0:7' => Icons.visibility,
      '0:9' => Icons.videocam_outlined,
      '0:10' => Icons.sensors,
      '0:17' => Icons.camera_alt_outlined,
      '0:18' => Icons.directions_car_outlined,
      '0:19' => Icons.flight,
      '0:8' => Icons.badge_outlined,
      '254:1' => Icons.favorite_border,
      '254:2' => Icons.link_off,
      '1:255' => Icons.bluetooth,
      '2:255' => Icons.wifi,
      '4:255' => Icons.flight_takeoff,
      '5:255' => Icons.bug_report_outlined,
      _ => Icons.music_note,
    };

const _info = [
  'The board plays a short tune on its buzzer for each alert.',
  'Every alert starts on its default tune. Tap one to change it.',
  'The play button tries a tune on the board.',
  'Make your own tune with up to 8 notes. A manager board passes your tunes on to its nodes.',
];

String _notesLabel(List<MelodyNote> notes) {
  final ms = notes.fold<int>(0, (a, n) => a + n.onMs + n.gapMs);
  return '${notes.map((n) => n.label).join(' ')}  ·  ${(ms / 1000).toStringAsFixed(2)} s';
}

class AlertSoundsScreen extends ConsumerWidget {
  const AlertSoundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final mel = ref.watch(melodyProvider);
    final notif = ref.watch(notificationServiceProvider);
    final ble = ref.read(bleManagerProvider);
    final supported = !ble.isConnected || ble.hasMelodySupport;
    final slots = {for (final s in kAlertSlots) s.key: s};
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Alert Sounds')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (!supported)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Connected firmware has no melody support. Update the board to apply these.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12),
              ),
            ),
          for (final (i, (title, keys)) in _groups.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            ConfigSectionHeader(label: title, info: i == 0 ? _info : null),
            for (final k in keys)
              if (slots[k] != null) _SlotRow(slot: slots[k]!, mel: mel),
          ],
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'Tunes'),
          for (final m in mel.melodies) _MelodyRow(melody: m),
          ConfigActionRow(
            icon: Icons.add,
            label: 'Compose a tune',
            subtitle: 'Up to $melodyMaxNotes notes',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<String>(
              builder: (_) => const MelodyComposerScreen(),
            )),
          ),
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'Sound on this phone'),
          for (final s in AlertSfx.values)
            ConfigToggleRow(
              icon: switch (s) {
                AlertSfx.hit => Icons.radar,
                AlertSfx.tracker => Icons.track_changes,
                AlertSfx.watch => Icons.notifications_active,
                AlertSfx.drone => Icons.flight,
                AlertSfx.nodeDown => Icons.link_off,
                AlertSfx.nodeUp => Icons.link,
              },
              label: s.label,
              color: AppTheme.detector,
              value: notif.sfxOn(s),
              onChanged: (v) => notif.setSfxOn(s, v),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

({String text, List<MelodyNote> notes}) _resolve(MelodyState mel, AlertSlot slot) {
  final current = mel.assignmentFor(slot);
  if (current == melodySilent) return (text: 'Silent', notes: const []);
  final m = current == null ? null : mel.byId(current);
  if (m != null) return (text: m.name, notes: m.notes);
  final d = mel.defaultFor(slot);
  return (text: 'Default (${d.name})', notes: d.notes);
}

class _SlotRow extends ConsumerWidget {
  const _SlotRow({required this.slot, required this.mel});

  final AlertSlot slot;
  final MelodyState mel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = _resolve(mel, slot);
    return ConfigActionRow(
      key: ValueKey('slot-${slot.key}'),
      icon: _slotIcon(slot.key),
      label: slot.label,
      subtitle: r.text,
      onTap: () => _pickTune(context, slot, slot.label),
      trailing: IconButton(
        icon: const Icon(Icons.play_arrow),
        color: AppTheme.accent,
        tooltip: 'Play on board',
        onPressed: r.notes.isEmpty ? null : () => _preview(ref, r.notes),
      ),
    );
  }
}

Future<void> _pickTune(BuildContext context, AlertSlot slot, String label) {
  return showCommandSheet<void>(
    context: context,
    builder: (sheetCtx) => Consumer(builder: (ctx, ref, _) {
      final t = AppTheme.of(ctx);
      final mel = ref.watch(melodyProvider);
      final current = mel.assignmentFor(slot);
      final d = mel.defaultFor(slot);
      void pick(String? id) {
        mel.assign(slot, id);
        Navigator.of(sheetCtx).pop();
      }

      Widget tile({
        required String? id,
        required IconData icon,
        required String title,
        String? subtitle,
        required List<MelodyNote> notes,
      }) {
        final selected = id == current;
        return CommandSheetTile(
          key: ValueKey('pick-${id ?? 'default'}'),
          icon: selected ? Icons.check_circle : icon,
          color: selected ? AppTheme.accent : null,
          label: title,
          subtitle: subtitle,
          onTap: () => pick(id),
          trailing: IconButton(
            icon: const Icon(Icons.play_arrow),
            color: AppTheme.accent,
            tooltip: 'Play on board',
            onPressed: notes.isEmpty ? null : () => _preview(ref, notes),
          ),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            children: [
              Text(label, style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Pick a tune. Play tries it on the board.',
                  style: TextStyle(color: t.textDim, fontSize: 13)),
              const SizedBox(height: 8),
              tile(
                id: null,
                icon: Icons.music_note_outlined,
                title: 'Default',
                subtitle: d.name,
                notes: d.notes,
              ),
              tile(id: melodySilent, icon: Icons.volume_off_outlined, title: 'Silent', notes: const []),
              for (final m in mel.melodies)
                tile(
                  id: m.id,
                  icon: Icons.music_note,
                  title: m.name,
                  subtitle: _notesLabel(m.notes),
                  notes: m.notes,
                ),
              CommandSheetTile(
                icon: Icons.add,
                label: 'Compose a tune',
                onTap: () async {
                  final nav = Navigator.of(sheetCtx);
                  final id = await nav.push(MaterialPageRoute<String>(
                    builder: (_) => const MelodyComposerScreen(),
                  ));
                  if (id != null) pick(id);
                },
              ),
            ],
          ),
        ),
      );
    }),
  );
}

class _MelodyRow extends ConsumerWidget {
  const _MelodyRow({required this.melody});

  final Melody melody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    void edit() => Navigator.of(context).push(MaterialPageRoute<String>(
          builder: (_) => MelodyComposerScreen(initial: melody),
        ));
    return ConfigActionRow(
      key: ValueKey('tune-${melody.id}'),
      icon: melody.builtIn ? Icons.music_note_outlined : Icons.music_note,
      label: melody.name,
      subtitle: melody.builtIn ? 'Built in  ·  ${_notesLabel(melody.notes)}' : _notesLabel(melody.notes),
      onTap: melody.builtIn ? () => _preview(ref, melody.notes) : edit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            color: AppTheme.accent,
            tooltip: 'Play on board',
            onPressed: () => _preview(ref, melody.notes),
          ),
          if (!melody.builtIn) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              color: t.textSecondary,
              tooltip: 'Edit',
              onPressed: edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTheme.error,
              tooltip: 'Delete',
              onPressed: () => ref.read(melodyProvider).deleteMelody(melody.id),
            ),
          ],
        ],
      ),
    );
  }
}

class MelodyComposerScreen extends ConsumerStatefulWidget {
  const MelodyComposerScreen({super.key, this.initial});

  final Melody? initial;

  @override
  ConsumerState<MelodyComposerScreen> createState() => _MelodyComposerScreenState();
}

class _MelodyComposerScreenState extends ConsumerState<MelodyComposerScreen> {
  late final TextEditingController _name;
  late List<MelodyNote> _notes;

  static const _durations = [0, 20, 40, 50, 60, 80, 100, 120, 150, 200, 250, 300, 400, 500, 750, 1000];
  static final _pitches = [0, for (var m = 48; m <= 108; m++) m];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? 'My tune');
    _notes = List.of(widget.initial?.notes ?? const [MelodyNote(72, 100, 50)]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int _snap(int ms) =>
      _durations.reduce((a, b) => (a - ms).abs() <= (b - ms).abs() ? a : b);

  void _set(int i, {int? midi, int? on, int? gap}) {
    final n = _notes[i];
    setState(() => _notes[i] = MelodyNote(midi ?? n.midi, on ?? n.onMs, gap ?? n.gapMs));
  }

  void _step(int i, int semis) {
    final m = _notes[i].midi;
    final next = m == 0 ? 72 : (m + semis).clamp(_pitches[1], _pitches.last);
    _set(i, midi: next);
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'My tune' : _name.text.trim();
    final id = widget.initial?.id ?? 'u${DateTime.now().millisecondsSinceEpoch}';
    await ref.read(melodyProvider).saveMelody(Melody(id: id, name: name, notes: _notes));
    if (mounted) Navigator.of(context).pop(id);
  }

  Widget _msPicker(String label, int value, ValueChanged<int?> onChanged, TextStyle style, ResolvedTheme t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: style),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: _snap(value),
          underline: const SizedBox.shrink(),
          dropdownColor: t.surface,
          style: style.copyWith(color: t.textPrimary, fontFamily: AppTheme.mono),
          items: [for (final d in _durations) DropdownMenuItem(value: d, child: Text('$d ms'))],
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final style = TextStyle(color: t.textSecondary, fontSize: 13);
    final totalMs = _notes.fold<int>(0, (a, n) => a + n.onMs + n.gapMs);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Compose' : 'Edit tune'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play on board',
            onPressed: _notes.isEmpty ? null : () => _preview(ref, _notes),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _notes.isEmpty ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            style: TextStyle(color: t.textPrimary),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          ConfigSectionHeader(
            label: 'Notes ${_notes.length} of $melodyMaxNotes  ·  ${(totalMs / 1000).toStringAsFixed(2)} s',
            info: const [
              'Each note plays for its length, then the board waits for the pause before the next one.',
              'Pick rest for a silent beat. The arrows move a note up or down one semitone.',
              'Lengths are rounded to 10 ms on the board.',
            ],
          ),
          for (var i = 0; i < _notes.length; i++)
            Container(
              key: ValueKey('note-$i'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 28, child: Text('${i + 1}', style: style)),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip: 'Lower',
                        visualDensity: VisualDensity.compact,
                        onPressed: _notes[i].midi == _pitches[1] ? null : () => _step(i, -1),
                      ),
                      DropdownButton<int>(
                        value: _notes[i].midi,
                        underline: const SizedBox.shrink(),
                        dropdownColor: t.surface,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTheme.mono,
                        ),
                        items: [
                          for (final p in _pitches)
                            DropdownMenuItem(value: p, child: Text(MelodyNote(p, 0, 0).label)),
                        ],
                        onChanged: (v) => _set(i, midi: v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: 'Higher',
                        visualDensity: VisualDensity.compact,
                        onPressed: _notes[i].midi == _pitches.last ? null : () => _step(i, 1),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.play_arrow, size: 20),
                        color: AppTheme.accent,
                        tooltip: 'Play this note',
                        onPressed: () => _preview(ref, [_notes[i]]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        color: AppTheme.error,
                        tooltip: 'Remove note',
                        onPressed: () => setState(() => _notes.removeAt(i)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Wrap(
                      spacing: 16,
                      children: [
                        _msPicker('Length', _notes[i].onMs, (v) => _set(i, on: v), style, t),
                        _msPicker('Pause after', _notes[i].gapMs, (v) => _set(i, gap: v), style, t),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_notes.length < melodyMaxNotes)
            ConfigActionRow(
              icon: Icons.add,
              label: 'Add note',
              subtitle: 'Copies the last note',
              onTap: () => setState(() => _notes.add(
                  _notes.isEmpty ? const MelodyNote(72, 100, 50) : _notes.last)),
            ),
          const SizedBox(height: 8),
          ConfigActionRow(
            icon: Icons.play_circle_outline,
            label: 'Play on board',
            onTap: _notes.isEmpty ? null : () => _preview(ref, _notes),
          ),
          ConfigActionRow(
            icon: Icons.check,
            label: 'Save',
            onTap: _notes.isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}
