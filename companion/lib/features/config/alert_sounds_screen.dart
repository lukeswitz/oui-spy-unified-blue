import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/melody_state.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

void _preview(WidgetRef ref, List<MelodyNote> notes) {
  ref.read(bleManagerProvider).writeMelodyOps([MelodyState.previewOp(notes)]);
}

class AlertSoundsScreen extends ConsumerWidget {
  const AlertSoundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final mel = ref.watch(melodyProvider);
    final supported = ref.read(bleManagerProvider).hasMelodySupport;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Alert sounds')),
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
          const ConfigSectionHeader(label: 'Assignments'),
          for (final slot in kAlertSlots) _SlotRow(slot: slot, mel: mel),
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'Melodies'),
          for (final m in mel.melodies) _MelodyRow(melody: m),
          ConfigActionRow(
            icon: Icons.add,
            label: 'Compose melody',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MelodyComposerScreen(),
            )),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SlotRow extends ConsumerWidget {
  const _SlotRow({required this.slot, required this.mel});

  final AlertSlot slot;
  final MelodyState mel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final current = mel.assignmentFor(slot);
    final valid = current == null || current == melodySilent || mel.byId(current) != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(slot.label,
                style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          DropdownButton<String?>(
            value: valid ? current : null,
            underline: const SizedBox.shrink(),
            dropdownColor: t.surface,
            style: TextStyle(color: t.textSecondary, fontSize: 12),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Default')),
              const DropdownMenuItem<String?>(value: melodySilent, child: Text('Silent')),
              for (final m in mel.melodies)
                DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
            ],
            onChanged: (v) => mel.assign(slot, v),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 18),
            color: AppTheme.accent,
            tooltip: 'Play on board',
            onPressed: current == null || current == melodySilent || mel.byId(current) == null
                ? null
                : () => _preview(ref, mel.byId(current)!.notes),
          ),
        ],
      ),
    );
  }
}

class _MelodyRow extends ConsumerWidget {
  const _MelodyRow({required this.melody});

  final Melody melody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(melody.name,
                    style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(melody.notes.map((n) => n.label).join(' '),
                    style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: AppTheme.mono)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 18),
            color: AppTheme.accent,
            tooltip: 'Play on board',
            onPressed: () => _preview(ref, melody.notes),
          ),
          if (!melody.builtIn) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              color: t.textSecondary,
              tooltip: 'Edit',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MelodyComposerScreen(initial: melody),
              )),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
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

  static const _durations = [0, 20, 40, 60, 80, 100, 120, 150, 200, 250, 300, 400, 500, 750, 1000];
  static final _pitches = [0, for (var m = 48; m <= 108; m++) m];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? 'My melody');
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

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty ? 'My melody' : _name.text.trim();
    final id = widget.initial?.id ?? 'u${DateTime.now().millisecondsSinceEpoch}';
    await ref.read(melodyProvider).saveMelody(Melody(id: id, name: name, notes: _notes));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final style = TextStyle(color: t.textSecondary, fontSize: 12);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Compose'),
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
          ConfigSectionHeader(label: 'Notes ${_notes.length}/$melodyMaxNotes'),
          for (var i = 0; i < _notes.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Row(
                children: [
                  SizedBox(width: 20, child: Text('${i + 1}', style: style)),
                  DropdownButton<int>(
                    value: _notes[i].midi,
                    underline: const SizedBox.shrink(),
                    dropdownColor: t.surface,
                    style: style,
                    items: [
                      for (final p in _pitches)
                        DropdownMenuItem(value: p, child: Text(MelodyNote(p, 0, 0).label)),
                    ],
                    onChanged: (v) => _set(i, midi: v),
                  ),
                  const SizedBox(width: 8),
                  Text('on', style: style),
                  DropdownButton<int>(
                    value: _snap(_notes[i].onMs),
                    underline: const SizedBox.shrink(),
                    dropdownColor: t.surface,
                    style: style,
                    items: [for (final d in _durations) DropdownMenuItem(value: d, child: Text('${d}ms'))],
                    onChanged: (v) => _set(i, on: v),
                  ),
                  const SizedBox(width: 8),
                  Text('gap', style: style),
                  DropdownButton<int>(
                    value: _snap(_notes[i].gapMs),
                    underline: const SizedBox.shrink(),
                    dropdownColor: t.surface,
                    style: style,
                    items: [for (final d in _durations) DropdownMenuItem(value: d, child: Text('${d}ms'))],
                    onChanged: (v) => _set(i, gap: v),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: AppTheme.error,
                    onPressed: () => setState(() => _notes.removeAt(i)),
                  ),
                ],
              ),
            ),
          if (_notes.length < melodyMaxNotes)
            ConfigActionRow(
              icon: Icons.add,
              label: 'Add note',
              onTap: () => setState(() => _notes.add(
                  _notes.isEmpty ? const MelodyNote(72, 100, 50) : _notes.last)),
            ),
        ],
      ),
    );
  }
}
