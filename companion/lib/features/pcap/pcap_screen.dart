import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class PcapScreen extends ConsumerStatefulWidget {
  const PcapScreen({super.key});

  @override
  ConsumerState<PcapScreen> createState() => _PcapScreenState();
}

class _PcapScreenState extends ConsumerState<PcapScreen> {
  PcapMode _mode = PcapMode.wifi;
  int _chanStart = 1;
  int _chanEnd = 11;
  bool _toggling = false;
  String? _targetNode;
  PcapStats? _heldStats;
  bool? _autoPcapOverride;
  int? _autoDurationOverride;
  int _autoDurationSec = 10;
  int? _autoCooldownOverride;
  int _autoCooldownSec = 0;

  File? _lastSaved;
  int _bytesWritten = 0;
  StreamSubscription<int>? _bytesSub;
  StreamSubscription<File>? _savedSub;
  Timer? _bytesTimer;
  int _pendingBytes = 0;

  @override
  void initState() {
    super.initState();
    final ble = ref.read(bleManagerProvider);
    _bytesWritten = ble.pcapBytesWrittenLatest;
    _pendingBytes = _bytesWritten;
    _bytesSub = ble.pcapBytesWritten.listen((v) {
      _pendingBytes = v;
    });
    _bytesTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (_pendingBytes != _bytesWritten) {
        setState(() => _bytesWritten = _pendingBytes);
      }
    });
    _savedSub = ble.pcapCaptureSaved.listen((f) {
      if (mounted) setState(() => _lastSaved = f);
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chanStart = (p.getInt('pcap_chanStart') ?? 1).clamp(1, 14);
      _chanEnd = (p.getInt('pcap_chanEnd') ?? 11).clamp(_chanStart, 14);
      final modeIdx = p.getInt('pcap_mode') ?? 0;
      _mode = modeIdx == 1 ? PcapMode.ble : PcapMode.wifi;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('pcap_chanStart', _chanStart);
    await p.setInt('pcap_chanEnd', _chanEnd);
    await p.setInt('pcap_mode', _mode == PcapMode.ble ? 1 : 0);
  }

  @override
  void dispose() {
    _bytesSub?.cancel();
    _savedSub?.cancel();
    _bytesTimer?.cancel();
    super.dispose();
  }

  Future<Directory> _pcapDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/pcaps');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<File>> _listSavedPcaps() async {
    final d = await _pcapDir();
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.pcap'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> _start() async {
    if (_toggling) return;
    final mgr = ref.read(appStateProvider).isManagerConnected;
    if (mgr && (_targetNode == null || _targetNode!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a node to capture on first')));
      return;
    }
    setState(() {
      _toggling = true;
      _heldStats = null;
    });
    try {
      await ref.read(bleManagerProvider).startPcap(
            mode: _mode == PcapMode.ble ? 1 : 0,
            channelStart: _chanStart,
            channelEnd: _chanEnd,
            targetNodeId: mgr ? _targetNode : null,
          );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _stop() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final mgr = ref.read(appStateProvider).isManagerConnected;
      await ref.read(bleManagerProvider).stopPcap(
            targetNodeId: mgr ? _targetNode : null,
          );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stop failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _shareFile(File f) async {
    if (!await f.exists()) return;
    final size = await f.length();
    if (!mounted) return;
    final size2 = MediaQuery.of(context).size;
    final origin = Rect.fromLTWH(size2.width / 2 - 1, size2.height / 2 - 1, 2, 2);
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/vnd.tcpdump.pcap')],
      subject: 'OUI-SPY PCAP ($size bytes)',
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final ble = ref.watch(bleManagerProvider);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('PCAP CAPTURE')),
      body: StreamBuilder<PcapStats>(
        stream: ble.pcapStats,
        initialData: ble.latestPcapStats,
        builder: (context, snap) {
          final s = snap.data ?? PcapStats.empty;
          final isCapturing = s.state == 1;
          if (isCapturing) _heldStats = s;
          final gridStats = isCapturing ? s : (_heldStats ?? s);
          final activeMode = isCapturing ? s.modeEnum : _mode;
          final hasFile = _lastSaved != null && !isCapturing;
          if (_autoPcapOverride != null && _autoPcapOverride == s.autoEnabled) {
            _autoPcapOverride = null;
          }
          if (_autoDurationOverride != null && _autoDurationOverride == s.autoDurationSec) {
            _autoDurationOverride = null;
          }
          if (_autoCooldownOverride != null && _autoCooldownOverride == s.autoCooldownSec) {
            _autoCooldownOverride = null;
          }
          final autoEnabled = _autoPcapOverride ?? s.autoEnabled;
          final autoDuration = _autoDurationOverride
              ?? (s.autoDurationSec > 0 ? s.autoDurationSec : _autoDurationSec);
          final autoCooldown = _autoCooldownOverride ?? s.autoCooldownSec;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StateCard(stats: s, t: t, localBytes: _bytesWritten),
                const SizedBox(height: 16),
                _AutoPcapCard(
                  enabled: autoEnabled,
                  durationSec: autoDuration,
                  cooldownSec: autoCooldown,
                  cooldownRemainingMs: s.autoCooldownRemainingMs,
                  onToggle: (v) async {
                    setState(() => _autoPcapOverride = v);
                    try {
                      await ble.setAutoPcap(v);
                    } on Exception catch (e) {
                      if (mounted) {
                        setState(() => _autoPcapOverride = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Auto-PCAP set failed: $e')),
                        );
                      }
                    }
                  },
                  onDuration: (v) async {
                    setState(() {
                      _autoDurationOverride = v;
                      _autoDurationSec = v;
                    });
                    try {
                      await ble.setAutoPcapDuration(v);
                    } on Exception catch (e) {
                      if (mounted) {
                        setState(() => _autoDurationOverride = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Duration set failed: $e')),
                        );
                      }
                    }
                  },
                  onCooldown: (v) async {
                    setState(() {
                      _autoCooldownOverride = v;
                      _autoCooldownSec = v;
                    });
                    try {
                      await ble.setAutoPcapCooldown(v);
                    } on Exception catch (e) {
                      if (mounted) {
                        setState(() => _autoCooldownOverride = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Cooldown set failed: $e')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                _NodePicker(
                  selected: _targetNode,
                  enabled: !isCapturing,
                  onChanged: (id) => setState(() => _targetNode = id),
                ),
                const SizedBox(height: 16),
                _ModeSelector(
                  mode: _mode,
                  enabled: !isCapturing,
                  onChanged: (m) {
                    setState(() => _mode = m);
                    _savePrefs();
                  },
                ),
                if (_mode == PcapMode.wifi) ...[
                  const SizedBox(height: 12),
                  _WifiConfigCard(
                    chanStart: _chanStart,
                    chanEnd: _chanEnd,
                    enabled: !isCapturing,
                    onChanStart: (v) {
                      setState(() {
                        _chanStart = v;
                        if (v > _chanEnd) _chanEnd = v;
                      });
                      _savePrefs();
                    },
                    onChanEnd: (v) {
                      setState(() => _chanEnd = v);
                      _savePrefs();
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (activeMode == PcapMode.wifi)
                  _WifiStatsGrid(stats: gridStats, t: t)
                else
                  _BleStatsGrid(stats: gridStats, t: t),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _toggling ? null : (isCapturing ? _stop : _start),
                  icon: _toggling
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(isCapturing ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(_toggling
                      ? (isCapturing ? 'WRITING FILE…' : 'STARTING…')
                      : (isCapturing ? 'STOP' : 'START')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isCapturing ? AppTheme.error : AppTheme.success,
                    side: BorderSide(color: isCapturing ? AppTheme.error : AppTheme.success),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: hasFile ? () => _shareFile(_lastSaved!) : null,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('SHARE LAST PCAP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                _SavedPcapsSection(
                  loader: _listSavedPcaps,
                  refreshTick: _lastSaved?.path.hashCode ?? 0,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.stats, required this.t, required this.localBytes});
  final PcapStats stats;
  final ResolvedTheme t;
  final int localBytes;

  @override
  Widget build(BuildContext context) {
    Color stateColor;
    switch (stats.state) {
      case 1: stateColor = AppTheme.success;
      case 2: stateColor = AppTheme.warning;
      case 3: stateColor = AppTheme.error;
      default: stateColor = t.textDim;
    }
    final uptimeS = stats.uptimeMs ~/ 1000;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(stats.stateLabel,
                  style: TextStyle(color: stateColor, fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(width: 12),
              Text(stats.modeLabel,
                  style: TextStyle(color: t.textDim, fontFamily: 'monospace',
                      fontSize: 11, letterSpacing: 2)),
              const Spacer(),
              if (stats.modeEnum == PcapMode.wifi)
                Text('CH ${stats.currentChannel}',
                    style: TextStyle(color: t.textDim, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'uptime ${uptimeS}s  •  Sent ${_humanBytes(stats.bytesWritten)}  •  Received ${_humanBytes(localBytes)}  •  dropped ${stats.droppedFrames}',
            style: TextStyle(color: t.textDim, fontSize: 12, fontFamily: 'monospace'),
          ),
          if (stats.isAutoTriggered) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, size: 13, color: AppTheme.warning),
                  const SizedBox(width: 4),
                  Text(
                    'AUTO',
                    style: const TextStyle(
                      color: AppTheme.warning, fontSize: 10,
                      fontFamily: 'monospace', fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    stats.autoTriggerEngineName.toUpperCase(),
                    style: TextStyle(
                      color: t.textPrimary, fontSize: 11,
                      fontFamily: 'monospace', fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      stats.autoTriggerMacStr,
                      style: TextStyle(
                        color: AppTheme.accent, fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stats.autoRemainingMs > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(stats.autoRemainingMs / 1000).ceil()}s',
                      style: TextStyle(
                        color: t.textDim, fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.enabled, required this.onChanged});
  final PcapMode mode;
  final bool enabled;
  final ValueChanged<PcapMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: _modeBtn(context, PcapMode.wifi, 'WIFI 802.11')),
          Expanded(child: _modeBtn(context, PcapMode.ble, 'BLE LL PHDR')),
        ],
      ),
    );
  }

  Widget _modeBtn(BuildContext context, PcapMode m, String label) {
    final t = AppTheme.of(context);
    final selected = mode == m;
    return GestureDetector(
      onTap: enabled ? () => onChanged(m) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.accent : (enabled ? t.textPrimary : t.textDim),
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            )),
      ),
    );
  }
}

class _WifiConfigCard extends StatelessWidget {
  const _WifiConfigCard({
    required this.chanStart, required this.chanEnd, required this.enabled,
    required this.onChanStart, required this.onChanEnd,
  });
  final int chanStart;
  final int chanEnd;
  final bool enabled;
  final ValueChanged<int> onChanStart;
  final ValueChanged<int> onChanEnd;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHANNELS',
              style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 11)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _ChanDropdown(label: 'START', value: chanStart, enabled: enabled, onChanged: onChanStart)),
              const SizedBox(width: 8),
              Expanded(child: _ChanDropdown(label: 'END', value: chanEnd, enabled: enabled, min: chanStart, onChanged: onChanEnd)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChanDropdown extends StatelessWidget {
  const _ChanDropdown({
    required this.label, required this.value, required this.enabled,
    required this.onChanged, this.min = 1,
  });
  final String label;
  final int value;
  final bool enabled;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final items = <int>[for (int i = min; i <= 14; i++) i];
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 2),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: items.contains(value) ? value : items.first,
          isDense: true,
          onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text('$i'))],
        ),
      ),
    );
  }
}

class _WifiStatsGrid extends StatelessWidget {
  const _WifiStatsGrid({required this.stats, required this.t});
  final PcapStats stats;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final rows = <(_StatTile, _StatTile)>[
      (_StatTile(label: 'BEACONS', value: stats.beaconCount, color: AppTheme.accent),
       _StatTile(label: 'PROBES (REQ)', value: stats.probeReqCount, color: AppTheme.warning)),
      (_StatTile(label: 'PROBES (RESP)', value: stats.probeRespCount, color: AppTheme.warning),
       _StatTile(label: 'DEAUTH', value: stats.deauthCount, color: AppTheme.error)),
      (_StatTile(label: 'DISASSOC', value: stats.disassocCount, color: AppTheme.error),
       _StatTile(label: 'DATA', value: stats.dataCount, color: AppTheme.success)),
      (_StatTile(label: 'CTRL', value: stats.ctrlCount, color: t.textDim),
       _StatTile(label: 'MGMT OTHER', value: stats.mgmtOtherCount, color: t.textDim)),
      (_StatTile(label: 'DROPPED', value: stats.droppedFrames, color: AppTheme.error),
       _StatTile(label: 'TX BYTES', value: stats.bytesWritten, color: t.textSecondary)),
    ];
    return _gridBox(context, rows);
  }
}

class _BleStatsGrid extends StatelessWidget {
  const _BleStatsGrid({required this.stats, required this.t});
  final PcapStats stats;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final rows = <(_StatTile, _StatTile)>[
      (_StatTile(label: 'ADVS', value: stats.bleAdvCount, color: AppTheme.accent),
       _StatTile(label: 'SCAN RSP', value: stats.bleScanCount, color: AppTheme.warning)),
      (_StatTile(label: 'DROPPED', value: stats.droppedFrames, color: AppTheme.error),
       _StatTile(label: 'TX BYTES', value: stats.bytesWritten, color: t.textSecondary)),
    ];
    return _gridBox(context, rows);
  }
}

Widget _gridBox(BuildContext context, List<(_StatTile, _StatTile)> rows) {
  final t = AppTheme.of(context);
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        for (final row in rows)
          Row(children: [Expanded(child: row.$1), Expanded(child: row.$2)]),
      ],
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 2),
          Text(_fmt(value),
              style: TextStyle(color: color, fontFamily: 'monospace',
                  fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static String _fmt(int v) {
    if (v < 1000) return v.toString();
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '${(v / 1000000).toStringAsFixed(2)}M';
  }
}

String _humanBytes(int n) {
  if (n < 1024) return '${n}B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
  return '${(n / 1024 / 1024).toStringAsFixed(2)}MB';
}

class _SavedPcapsSection extends StatefulWidget {
  const _SavedPcapsSection({required this.loader, required this.refreshTick});
  final Future<List<File>> Function() loader;
  final int refreshTick;

  @override
  State<_SavedPcapsSection> createState() => _SavedPcapsSectionState();
}

class _SavedPcapsSectionState extends State<_SavedPcapsSection> {
  late Future<List<File>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  void didUpdateWidget(covariant _SavedPcapsSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) {
      _future = widget.loader();
    }
  }

  void _reload() => setState(() => _future = widget.loader());

  Future<void> _clearAll() async {
    final files = await widget.loader();
    if (files.isEmpty) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all captures?'),
        content: Text('${files.length} pcap file(s) will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in files) {
      if (await f.exists()) await f.delete();
    }
    _reload();
  }

  Future<void> _shareFile(File f) async {
    final size = await f.length();
    if (!mounted) return;
    final size2 = MediaQuery.of(context).size;
    final origin = Rect.fromLTWH(size2.width / 2 - 1, size2.height / 2 - 1, 2, 2);
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/vnd.tcpdump.pcap')],
      subject: 'OUI-SPY PCAP ($size bytes)',
      sharePositionOrigin: origin,
    );
  }

  Future<void> _deleteFile(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete capture?'),
        content: Text(f.uri.pathSegments.last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (await f.exists()) await f.delete();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('SAVED CAPTURES',
                style: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 2)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              color: t.textDim,
              onPressed: _reload,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 18),
              color: AppTheme.error,
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
          ],
        ),
        FutureBuilder<List<File>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Loading…', style: TextStyle(color: t.textDim)),
              );
            }
            final files = snap.data!;
            if (files.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.border),
                ),
                child: Text('No captures yet.', style: TextStyle(color: t.textDim)),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  for (final f in files) _PcapRow(
                    file: f,
                    onShare: () => _shareFile(f),
                    onDelete: () => _deleteFile(f),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PcapRow extends StatelessWidget {
  const _PcapRow({required this.file, required this.onShare, required this.onDelete});
  final File file;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final name = file.uri.pathSegments.last;
    final isBle = name.contains('_ble_');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(isBle ? Icons.bluetooth : Icons.wifi,
              color: isBle ? AppTheme.flockBle : AppTheme.accent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<int>(
              future: file.length(),
              builder: (ctx, snap) {
                final sz = snap.data ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(color: t.textPrimary, fontSize: 12, fontFamily: 'monospace')),
                    Text(_humanBytes(sz),
                        style: TextStyle(color: t.textDim, fontSize: 10)),
                  ],
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, size: 18),
            color: AppTheme.accent,
            onPressed: onShare,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppTheme.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _AutoPcapCard extends StatelessWidget {
  const _AutoPcapCard({
    required this.enabled,
    required this.durationSec,
    required this.cooldownSec,
    required this.cooldownRemainingMs,
    required this.onToggle,
    required this.onDuration,
    required this.onCooldown,
  });
  final bool enabled;
  final int durationSec;
  final int cooldownSec;
  final int cooldownRemainingMs;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onDuration;
  final ValueChanged<int> onCooldown;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on,
                  color: enabled ? AppTheme.accent : t.textDim, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-PCAP on detect',
                        style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                      enabled
                          ? 'Any detection (OUI/Flock) starts a capture'
                          : 'Off — detections are not auto-captured',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onToggle, activeThumbColor: AppTheme.accent),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Window', style: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: durationSec.toDouble().clamp(3, 120),
                    min: 3, max: 120, divisions: 39,
                    label: '${durationSec}s',
                    activeColor: AppTheme.accent,
                    onChanged: (v) => onDuration(v.round()),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${durationSec}s',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: t.textPrimary, fontFamily: 'monospace')),
                ),
              ],
            ),
            Row(
              children: [
                Text('Cooldown', style: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: cooldownSec.toDouble().clamp(0, 600),
                    min: 0, max: 600, divisions: 60,
                    label: cooldownSec == 0 ? 'off' : '${cooldownSec}s',
                    activeColor: AppTheme.warning,
                    onChanged: (v) => onCooldown(v.round()),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    cooldownSec == 0 ? 'off' : '${cooldownSec}s',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: t.textPrimary, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            if (cooldownRemainingMs > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_bottom, size: 12, color: AppTheme.warning),
                    const SizedBox(width: 4),
                    Text(
                      'cooldown active — ${(cooldownRemainingMs / 1000).ceil()}s remaining',
                      style: const TextStyle(
                        color: AppTheme.warning, fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NodePicker extends ConsumerWidget {
  const _NodePicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final t = AppTheme.of(context);
    final mgr = appState.isManagerConnected;

    final box = BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(8),
    );

    if (!mgr) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Row(
          children: [
            Icon(Icons.memory, color: t.textDim, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LOCAL CAPTURE',
                      style: TextStyle(
                        color: t.textPrimary, fontSize: 12,
                        letterSpacing: 1.5, fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text('Captures on this device.',
                      style: TextStyle(color: t.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final nodes = appState.liveKnownNodes
        .where((id) => id != appState.nodeId)
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lan, color: AppTheme.accent, size: 18),
              const SizedBox(width: 10),
              Text('PCAP NODE',
                  style: TextStyle(
                    color: AppTheme.accent, fontSize: 12,
                    letterSpacing: 1.5, fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          if (nodes.isEmpty)
            Text('No live nodes yet — wait for nodes to report in.',
                style: TextStyle(color: t.textSecondary, fontSize: 11))
          else
            DropdownButton<String>(
              value: nodes.contains(selected) ? selected : null,
              hint: Text('Select a node',
                  style: TextStyle(color: t.textDim, fontSize: 13)),
              isExpanded: true,
              dropdownColor: t.surface,
              underline: const SizedBox.shrink(),
              items: nodes
                  .map((id) => DropdownMenuItem(
                        value: id,
                        child: Text(appState.labelForNode(id),
                            style: TextStyle(color: t.textPrimary)),
                      ))
                  .toList(),
              onChanged: enabled ? onChanged : null,
            ),
        ],
      ),
    );
  }
}
