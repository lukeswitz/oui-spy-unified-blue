import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/flood.dart';
import 'package:oui_spy/core/classify/fleet_decode.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/presence_class.dart';
import 'package:oui_spy/core/db/app_database.dart' show databaseProvider;
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_spec_row.dart';

enum DeviceSort { recent, rssi, confidence, kind, name, vendor, channel, firstSeen }

Color confidenceColor(Confidence c) => switch (c) {
  Confidence.high => AppTheme.success,
  Confidence.medium => AppTheme.warning,
  Confidence.low => AppTheme.gpsNone,
};


Color rssiColor(int rssi) => rssi >= -60
    ? AppTheme.success
    : rssi >= -75
        ? AppTheme.warning
        : AppTheme.gpsNone;


class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  SignatureClass? _class;
  bool _unclassifiedOnly = false;
  RadioKind? _radio;
  String? _source;
  DeviceSort _sort = DeviceSort.recent;
  bool _sortAscending = false;

  bool _matches(ClassifiedDevice d) {
    if (_radio != null && d.obs.kind != _radio) return false;
    if (_source != null && !d.sources.contains(_source)) return false;
    if (_unclassifiedOnly) return d.signatures.isEmpty;
    if (_class != null) return d.signatures.any((s) => s.kind == _class);
    return true;
  }

  int get _filterCount =>
      (_radio != null ? 1 : 0) +
      (_source != null ? 1 : 0) +
      (_class != null || _unclassifiedOnly ? 1 : 0);

  static String _sourceLabel(String? s) => switch (s) {
    'esp32' => 'NODE',
    'phone' => 'PHONE',
    _ => 'ALL',
  };

  Future<bool> _ensurePhoneScan(BuildContext ctx) async {
    final src = ref.read(phoneBleSourceProvider);
    if (src.active) return true;
    final yes = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Scan with this phone?'),
        content: const Text(
          "Use this phone's Bluetooth to listen for nearby devices too, in addition to the connected node. "
          'This uses more battery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('NOT NOW'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('SCAN'),
          ),
        ],
      ),
    );
    if (yes != true) return false;
    src.setActive(true);
    return true;
  }

  Future<void> _openFilterSheet(
    Map<SignatureClass, int> counts,
    int unclassified,
  ) {
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          final t = AppTheme.of(ctx);
          final gap = barGap(ctx);
          return CommandSheet(
            title: 'FILTER',
            trailing: _filterCount == 0
                ? null
                : TextButton(
                    onPressed: () => apply(() {
                      _radio = null;
                      _source = null;
                      _class = null;
                      _unclassifiedOnly = false;
                    }),
                    child: Text(
                      'RESET',
                      style: barLabelStyle(ctx, AppTheme.accent),
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommandSheetGroup(
                  label: 'HEARD BY',
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final s in <String?>[null, 'esp32', 'phone'])
                        CommandChip(
                          label: _sourceLabel(s),
                          selected: _source == s,
                          color: switch (s) {
                            'esp32' => AppTheme.warning,
                            'phone' => AppTheme.skySpy,
                            _ => kPillAll,
                          },
                          onTap: () async {
                            if (s == 'phone' && !await _ensurePhoneScan(ctx)) {
                              return;
                            }
                            apply(() => _source = s);
                          },
                        ),
                    ],
                  ),
                ),
                CommandSheetGroup(
                  label: 'RADIO',
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final r in <RadioKind?>[
                        null,
                        RadioKind.ble,
                        RadioKind.wifi,
                      ])
                        CommandChip(
                          label: r == null
                              ? 'ALL'
                              : (r == RadioKind.ble ? 'BLE' : 'WIFI'),
                          selected: _radio == r,
                          color: r == null
                              ? kPillAll
                              : (r == RadioKind.ble ? kPillBle : kPillWifi),
                          onTap: () => apply(() => _radio = r),
                        ),
                    ],
                  ),
                ),
                CommandSheetGroup(
                  label: 'CLASS',
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      CommandChip(
                        label: 'ALL',
                        selected: _class == null && !_unclassifiedOnly,
                        color: AppTheme.accent,
                        onTap: () => apply(() {
                          _class = null;
                          _unclassifiedOnly = false;
                        }),
                      ),
                      for (final k in SignatureClass.values)
                        if ((counts[k] ?? 0) > 0)
                          CommandChip(
                            label: k.label.toUpperCase(),
                            count: counts[k],
                            selected: _class == k,
                            color: classColor(k),
                            onTap: () => apply(() {
                              _unclassifiedOnly = false;
                              _class = k;
                            }),
                          ),
                      if (unclassified > 0)
                        CommandChip(
                          label: 'UNCLASSIFIED',
                          count: unclassified,
                          selected: _unclassifiedOnly,
                          color: t.textDim,
                          onTap: () => apply(() {
                            _class = null;
                            _unclassifiedOnly = true;
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _textKey(String s) => s.isEmpty ? '\u{10FFFF}' : s.toLowerCase();

  static String _sortLabel(DeviceSort s) => switch (s) {
    DeviceSort.recent => 'TIME',
    DeviceSort.rssi => 'RSSI',
    DeviceSort.confidence => 'CONF',
    DeviceSort.kind => 'CLASS',
    DeviceSort.name => 'NAME',
    DeviceSort.vendor => 'VENDOR',
    DeviceSort.channel => 'CH',
    DeviceSort.firstSeen => 'FIRST SEEN',
  };

  Future<void> _openSortSheet() => showSortSheet<DeviceSort>(
        context: context,
        options: DeviceSort.values,
        label: _sortLabel,
        current: () => _sort,
        ascending: () => _sortAscending,
        onPick: (s) => setState(() {
          if (_sort == s) {
            _sortAscending = !_sortAscending;
          } else {
            _sort = s;
            _sortAscending = false;
          }
        }),
        onToggleDirection: () => setState(() => _sortAscending = !_sortAscending),
      );

  Future<void> _openActionSheet() {
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => CommandSheet(
        title: 'ACTIONS',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandSheetTile(
              icon: Icons.phone_iphone,
              label: ref.read(phoneBleSourceProvider).active
                  ? 'STOP SCANNING WITH PHONE'
                  : 'SCAN WITH THIS PHONE',
              subtitle: ref.read(phoneBleSourceProvider).active
                  ? "This phone's Bluetooth is listening too"
                  : "Also listen with this phone's Bluetooth",
              color: ref.read(phoneBleSourceProvider).active
                  ? AppTheme.accent
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final src = ref.read(phoneBleSourceProvider);
                if (src.active) {
                  src.setActive(false);
                  if (_source == 'phone') _source = null;
                } else {
                  await _ensurePhoneScan(context);
                }
                if (mounted) setState(() {});
              },
            ),
            CommandSheetTile(
              icon: Icons.delete_sweep,
              label: 'CLEAR LIST',
              subtitle: 'Forget every device on this tab',
              color: AppTheme.error,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(deviceRegistryProvider).clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(deviceRegistryProvider);
    final t = AppTheme.of(context);
    final all = reg.devices.toList();
    final counts = <SignatureClass, int>{};
    var unclassified = 0;
    for (final d in all) {
      if (d.signatures.isEmpty) unclassified++;
      for (final k in {for (final s in d.signatures) s.kind}) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    final shown = all.where(_matches).toList();
    final guesses = {for (final d in shown) d.obs.key: d.guess};
    shown.sort(switch (_sort) {
      DeviceSort.recent => (a, b) => b.obs.lastSeenMs.compareTo(
        a.obs.lastSeenMs,
      ),
      DeviceSort.rssi => (a, b) => b.obs.rssi.compareTo(a.obs.rssi),
      DeviceSort.confidence =>
        (a, b) => guesses[a.obs.key]!.confidence.index.compareTo(
          guesses[b.obs.key]!.confidence.index,
        ),
      DeviceSort.kind => (a, b) => _textKey(a.signatures.isEmpty ? '' : a.signatures.first.kind.label)
          .compareTo(_textKey(b.signatures.isEmpty ? '' : b.signatures.first.kind.label)),
      DeviceSort.name => (a, b) => _textKey(a.obs.name).compareTo(_textKey(b.obs.name)),
      DeviceSort.vendor => (a, b) => _textKey(a.vendor ?? '').compareTo(_textKey(b.vendor ?? '')),
      DeviceSort.channel => (a, b) => (a.obs.channel > 0 ? a.obs.channel : 1 << 30)
          .compareTo(b.obs.channel > 0 ? b.obs.channel : 1 << 30),
      DeviceSort.firstSeen => (a, b) => b.obs.firstSeenMs.compareTo(a.obs.firstSeenMs),
    });
    final ordered = _sortAscending ? shown.reversed.toList() : shown;
    final flood = reg.pairingFlood.notice;
    final content = Column(
          children: [
            CommandHeader(
              title: 'DEVICES',
              count: _filterCount > 0 ? '${shown.length}/${all.length}' : '${all.length}',
              actions: [
                CommandBarAction(
                  icon: Icons.filter_alt,
                  label: 'Filter',
                  active: _filterCount > 0,
                  onTap: () => _openFilterSheet(counts, unclassified),
                ),
                CommandBarAction(
                  icon: _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  label: 'Sort: ${_sortLabel(_sort)}',
                  onTap: _openSortSheet,
                ),
                CommandBarAction(
                  icon: Icons.more_vert,
                  label: 'More',
                  onTap: _openActionSheet,
                ),
              ],
              chips: [
                          if (_radio != null)
                            CommandActiveChip(
                              label: _radio == RadioKind.ble ? 'BLE' : 'WIFI',
                              color: AppTheme.accent,
                              onClear: () => setState(() => _radio = null),
                            ),
                          if (_source != null)
                            CommandActiveChip(
                              label: _sourceLabel(_source),
                              color: AppTheme.accent,
                              onClear: () => setState(() => _source = null),
                            ),
                          if (_class != null || _unclassifiedOnly)
                            CommandActiveChip(
                              label: _unclassifiedOnly
                                  ? 'UNCLASSIFIED'
                                  : _class!.label.toUpperCase(),
                              color: AppTheme.accent,
                              onClear: () => setState(() {
                                _class = null;
                                _unclassifiedOnly = false;
                              }),
                            ),
              ],
            ),
            if (flood != null)
              _FloodBanner(notice: flood, onDismiss: reg.pairingFlood.dismiss),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? CommandEmptyState(
                      icon: Icons.devices_other,
                      title: 'NO DEVICES',
                      message: reg.ready
                          ? 'Devices heard by the connected node or this phone appear here, grouped by signature class.'
                          : 'Loading signature catalog.',
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(vertical: barGap(context)),
                          itemCount: ordered.length,
                          itemBuilder: (context, i) => DeviceRow(
                            device: ordered[i],
                            guess: guesses[ordered[i].obs.key]!,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(bottom: false, child: content),
    );
  }
}

class _FloodBanner extends StatelessWidget {
  const _FloodBanner({required this.notice, required this.onDismiss});

  final FloodNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final gap = barGap(context);
    return Material(
      color: AppTheme.error.withValues(alpha: 0.14),
      child: InkWell(
        onTap: onDismiss,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gap * 2, vertical: gap),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: barIconSize(context),
                color: AppTheme.error,
              ),
              SizedBox(width: gap),
              Expanded(
                child: Text(
                  notice.families.isEmpty
                      ? notice.line()
                      : '${notice.line()} · ${notice.families.join(', ')}',
                  style: barLabelStyle(context, AppTheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceRow extends ConsumerWidget {
  const DeviceRow({super.key, required this.device, required this.guess});

  final ClassifiedDevice device;
  final Guess guess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    final o = device.obs;
    final vendor = o.mac.isEmpty
        ? null
        : ref.read(ouiLookupProvider).lookup(o.mac);
    final title =
        DeviceExplain.listLabel(
          o,
          signatureNames: device.signatureNames,
          vendor: vendor,
          guessed: guess,
        ) ??
        (o.name.isNotEmpty ? o.name : (o.mac.isNotEmpty ? o.mac : o.key));
    final withYou = ref.read(deviceRegistryProvider).withYou(device);
    final live = [
      for (final s in device.signatures)
        if (s.decode case final d?) ...FleetDecode.decode(d, o).where((f) => f.live),
    ];
    final ble = o.kind == RadioKind.ble;
    final kinds = {for (final s in device.signatures) s.kind}.toList();
    final accent = kinds.isEmpty ? t.textDim : classColor(kinds.first);
    final text = Theme.of(context).textTheme;
    final iconSize = barIconSize(context) * 0.75;
    Widget flag(String tip, IconData i, Color c) => Padding(
          padding: EdgeInsets.only(left: gap * 0.6),
          child: Tooltip(message: tip, child: Icon(i, size: iconSize, color: c)),
        );
    Widget tag(String label, Color c, {IconData? icon}) => Container(
          padding: EdgeInsets.symmetric(horizontal: gap * 0.7, vertical: gap * 0.25),
          decoration: BoxDecoration(
            border: Border.all(color: c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: barIconSize(context) * 0.6, color: c),
                SizedBox(width: gap * 0.3),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: barLabelStyle(context, c).copyWith(fontSize: (text.labelSmall?.fontSize ?? 11) * 0.95),
                ),
              ),
            ],
          ),
        );
    final auth = o.authMode;
    final authMeta = auth == null ? null : wifiAuthMeta(auth);
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showCommandSheet<void>(
            context: context,
            builder: (_) => DeviceDetailSheet(device: device, vendor: vendor),
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: gap * 0.5, right: gap * 0.8),
                      child: Icon(
                        device.obs.kind == RadioKind.ble ? Icons.bluetooth : Icons.wifi,
                        size: 15,
                        color: accent,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: gap * 0.6),
                      child: Icon(Icons.circle, size: gap * 0.8, color: confidenceColor(guess.confidence)),
                    ),
                    SizedBox(width: gap * 0.6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: Color.lerp(accent, t.textPrimary, 0.35),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${o.rssi}',
                          style: text.titleMedium?.copyWith(
                            color: rssiColor(o.rssi),
                            fontFamily: AppTheme.mono,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: ' dBm', style: text.labelSmall?.copyWith(color: t.textDim)),
                      ]),
                    ),
                  ],
                ),
                SizedBox(height: gap * 0.6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (kinds.isNotEmpty) ...[
                        tag(kinds.first.label.toUpperCase(), classColor(kinds.first)),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (authMeta != null) ...[
                        Icon(auth == 0 ? Icons.lock_open : Icons.lock, size: iconSize, color: authMeta.$2),
                        SizedBox(width: gap * 0.3),
                        Text(authMeta.$1, style: barLabelStyle(context, authMeta.$2)),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (o.hiddenSsid) ...[
                        Icon(Icons.visibility_off, size: iconSize, color: AppTheme.warning),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (o.randomized) ...[
                        Icon(Icons.shuffle, size: iconSize, color: t.textDim),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (withYou) ...[
                        Icon(Icons.directions_walk, size: iconSize, color: AppTheme.error),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (!ble && o.channel > 0) ...[
                        Text(
                          'CH ${o.channel}',
                          style: text.labelMedium?.copyWith(
                            color: o.channel > 14 ? AppTheme.wardrive : AppTheme.detector,
                            fontFamily: AppTheme.mono,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: gap * 0.7),
                      ],
                      if (o.mac.isNotEmpty)
                        Text(
                          o.mac,
                          style: text.bodySmall?.copyWith(color: t.textDim, fontFamily: AppTheme.mono),
                        ),
                      for (final f in live) ...[
                        SizedBox(width: gap * 0.7),
                        tag(f.display.toUpperCase(), f.emphasis ? AppTheme.error : AppTheme.accent),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceDetailSheet extends ConsumerWidget {
  const DeviceDetailSheet({super.key, required this.device, this.vendor});

  final ClassifiedDevice device;
  final String? vendor;

  void _foxhunt(BuildContext context, WidgetRef ref) {
    final o = device.obs;
    Navigator.of(context).maybePop();
    ref.read(appStateProvider).setFoxhunterTarget(o.mac, channel: o.channel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Foxhunting ${o.mac.substring(0, 8)}...'),
        backgroundColor: AppTheme.foxhunter,
      ),
    );
  }

  void _showOnMap(BuildContext context, WidgetRef ref) {
    final fix = device.obs.gpsTrail.last;
    Navigator.of(context).maybePop();
    ref.read(wardriveProvider).requestZoom(fix.lat, fix.lon);
    context.go('/wardrive');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final o = device.obs;
    final g = device.guess;
    final connected = ref.read(appStateProvider).isConnected;
    final canFoxhunt = o.mac.isNotEmpty;
    final fields = [
      for (final m in o.mfgRecords) ...AdvPayloadDecoder.decodeManufacturer(m),
      for (final s in o.serviceData) ...AdvPayloadDecoder.decodeService(s),
    ];
    final decoded = [
      for (final s in device.signatures)
        if (s.decode case final d?) ...FleetDecode.decode(d, o),
    ];
    final classLabel = device.signatures.isNotEmpty
        ? device.signatures.first.kind.label.toUpperCase()
        : 'DEVICE';
    Widget kv(String k, String v, {bool mono = false}) => DSpecRow(label: k, value: v, mono: mono);
    Widget section(String label, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 2),
          child: DEyebrow(label),
        ),
        ...rows,
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.fill,
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      color: t.mark,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(
                        classLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.fill),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: DEyebrow(g.because, color: t.onFillDim)),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: t.onFill),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    g.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: t.onFill,
                          fontSize: 24,
                        ),
                  ),
                ),
                if (o.mac.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      o.mac,
                      style: TextStyle(color: t.onFillDim, fontSize: 12, fontFamily: AppTheme.mono),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('IDENTITY', [
                    if (o.mac.isNotEmpty) kv('Address', o.mac, mono: true),
                    if (o.mac.isEmpty) kv('Phone ID', o.key.substring(4), mono: true),
                    if (vendor != null) kv('Vendor', vendor!),
                    if (o.name.isNotEmpty) kv('Name', o.name),
                    kv('Address type', DeviceExplain.addressExplain(o)),
                    kv('Signal', '${DeviceExplain.rssiExplain(o.rssi)} (${o.rssiMin} to ${o.rssiMax})'),
                    kv('Heard by', device.sources.join(', ')),
                    if (o.mac.isNotEmpty && !o.randomized)
                      FutureBuilder<List<int>>(
                        future: ref.read(databaseProvider).sightingTimesForMac(o.mac),
                        builder: (context, snap) {
                          final ts = snap.data;
                          if (ts == null) return const SizedBox.shrink();
                          final now = DateTime.now().millisecondsSinceEpoch;
                          const p = PresenceParams();
                          final s = PresenceStats.fromSightings(ts, now, p);
                          if (s == null) return kv('Presence', 'Not in saved history yet');
                          return kv(
                            'Presence',
                            '${classifyPresence(s, now, p).label} · ${s.visitsInWindow} visit'
                                '${s.visitsInWindow == 1 ? '' : 's'} in 7 days · ${ts.length} sightings saved',
                          );
                        },
                      ),
                  ]),
                  if (device.signatures.isNotEmpty)
                    section('SIGNATURES', [
                      for (final s in device.signatures)
                        kv(s.kind.label,
                            [s.name, if (s.attentionNote.isNotEmpty) s.attentionNote].join('\n')),
                    ]),
                  if (decoded.isNotEmpty)
                    section('DECODED', [
                      for (final f in decoded)
                        kv(f.label, f.note.isEmpty ? f.display : '${f.display}\n${f.note}'),
                    ]),
                  if (fields.isNotEmpty)
                    section('ADVERTISEMENT', [for (final f in fields) kv(f.label, f.value)]),
                  if (o.serviceUuids.isNotEmpty)
                    section('SERVICES', [
                      for (final u in o.serviceUuids) kv(u, DeviceExplain.uuidGloss(u) ?? '', mono: true),
                    ]),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canFoxhunt) ...[
                  ElevatedButton(
                    onPressed: connected ? () => _foxhunt(context, ref) : null,
                    child: Row(
                      children: [
                        Expanded(child: Text(connected ? 'Foxhunt this device' : 'Node disconnected')),
                        Icon(Icons.gps_fixed, size: 18, color: t.buttonMark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton(
                  onPressed: o.gpsTrail.isEmpty ? null : () => _showOnMap(context, ref),
                  child: Row(
                    children: [
                      Expanded(child: Text(o.gpsTrail.isEmpty ? 'No GPS fix for this device' : 'Show on map')),
                      const Icon(Icons.map, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
