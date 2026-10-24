import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_adsb.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/features/sdr/sdr433_classify.dart';
import 'package:oui_spy/theme/app_theme.dart';

class SdrScreen extends ConsumerStatefulWidget {
  const SdrScreen({super.key});

  @override
  ConsumerState<SdrScreen> createState() => _SdrScreenState();
}

class _SdrScreenState extends ConsumerState<SdrScreen> {
  late final SdrController _c = ref.read(sdrControllerProvider);
  final _freq = TextEditingController(text: '100.1');
  SdrMode _mode = SdrMode.spectrum;
  final Set<int> _bands = {433};
  static const _bandHz = {315: 315000000, 433: 433920000, 915: 915000000};
  String? _deviceId;
  String _deviceName = '';
  bool _busy = false;
  bool _showRaw = false;
  Object? _catFilter;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _freq.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ds = await Sdr.list();
    if (!mounted) return;
    setState(() {
      if (ds.isNotEmpty) {
        _deviceId = ds.first.id;
        _deviceName = ds.first.name.isNotEmpty ? ds.first.name : 'RTL-SDR ${ds.first.vidPid}';
      } else {
        _deviceId = null;
        _deviceName = '';
      }
    });
  }

  int _rateFor(SdrMode m) => switch (m) {
        SdrMode.adsb => 2000000,
        SdrMode.tpms => 1024000,
        SdrMode.rtl433 => 1024000,
        SdrMode.spectrum => 2048000,
      };

  bool get _isIsm => _mode == SdrMode.tpms || _mode == SdrMode.rtl433;

  List<int> _bandsHz() =>
      [for (final b in const [315, 433, 915]) if (_bands.contains(b)) _bandHz[b]!];

  int _freqHz() {
    if (_mode == SdrMode.adsb) return 1090000000;
    if (_isIsm) {
      final b = _bandsHz();
      return b.isEmpty ? 433920000 : b.first;
    }
    final mhz = double.tryParse(_freq.text) ?? 100.1;
    return (mhz * 1e6).round();
  }

  Future<void> _start() async {
    final id = _deviceId;
    if (id == null) {
      await _refresh();
      if (_deviceId == null) {
        _snack('No RTL-SDR dongle detected — plug it in');
        return;
      }
    }
    setState(() => _busy = true);
    await _c.start(_deviceId!, _mode, _freqHz(), _rateFor(_mode),
        freqsHz: _isIsm ? _bandsHz() : const []);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await _c.stop();
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _uploadAdsb() async {
    final wdg = ref.read(wdgwarsProvider);
    if (!wdg.isLoggedIn) {
      _snack('Link WDGWars in Settings first');
      return;
    }
    final recs = [
      for (final a in _c.adsbAircraft)
        if (a.hasFix)
          AdsbRecord(
            icao: a.icao,
            callsign: a.callsign,
            lat: a.lat!,
            lon: a.lon!,
            altFt: a.altFt,
            speedKt: a.velocityKt,
            heading: a.heading,
            firstSeen: a.firstSeen,
          ),
    ];
    if (recs.isEmpty) {
      _snack('No aircraft with a position fix yet');
      return;
    }
    setState(() => _busy = true);
    final res = await wdg.uploadAircraft(recs);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(res != null
        ? 'WDGWars: ${res.imported} new, ${res.alreadySeen} seen (${res.sent} sent)'
        : wdg.error ?? 'Upload failed');
  }

  void _setMode(SdrMode m) {
    setState(() {
      _mode = m;
      _catFilter = null;
      _freq.text = switch (m) {
        SdrMode.adsb => '1090',
        SdrMode.tpms => '433.92',
        SdrMode.rtl433 => '433.92',
        SdrMode.spectrum => '100.1',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final running = _c.state == SdrState.running || _c.state == SdrState.starting;
    final showChips = _mode == SdrMode.tpms || _mode == SdrMode.rtl433;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RTL-SDR'),
        actions: [
          Row(
            children: [
              Text('RAW', style: TextStyle(fontSize: 12, color: t.textSecondary)),
              Switch(value: _showRaw, onChanged: (v) => setState(() => _showRaw = v)),
            ],
          ),
          IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_deviceId == null ? 'No dongle (0bda:2832/2838)' : _deviceName,
                style: TextStyle(color: t.textDim, fontSize: 12)),
            const SizedBox(height: 10),
            SegmentedButton<SdrMode>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                side: WidgetStatePropertyAll(BorderSide(color: t.border)),
                backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? t.fill : Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? t.textPrimary : t.textDim),
              ),
              segments: const [
                ButtonSegment(value: SdrMode.spectrum, label: Text('Spectrum')),
                ButtonSegment(value: SdrMode.adsb, label: Text('ADS-B')),
                ButtonSegment(value: SdrMode.tpms, label: Text('TPMS')),
                ButtonSegment(value: SdrMode.rtl433, label: Text('SCAN')),
              ],
              selected: {_mode},
              onSelectionChanged: running ? null : (s) => _setMode(s.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _isIsm
                      ? _BandSelector(
                          bands: _bands,
                          enabled: !running,
                          t: t,
                          onToggle: (mhz) => setState(() {
                            if (_bands.contains(mhz)) {
                              if (_bands.length > 1) _bands.remove(mhz);
                            } else {
                              _bands.add(mhz);
                            }
                          }),
                        )
                      : TextField(
                          controller: _freq,
                          enabled: !running && _mode != SdrMode.adsb,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _mode == SdrMode.adsb ? 'Frequency (fixed 1090 MHz)' : 'Frequency (MHz)',
                            isDense: true,
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.border)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: t.textSecondary)),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : (running ? _stop : _start),
                  style: running ? FilledButton.styleFrom(backgroundColor: AppTheme.error) : null,
                  child: Text(running ? 'STOP' : 'START'),
                ),
              ],
            ),
            if (_isIsm)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _bands.length > 1
                      ? 'Hopping ${_bandsHz().length} bands (~2s each) — one dongle, one band at a time'
                      : 'Single band — add more to hop and catch 315/433/915 devices',
                  style: TextStyle(color: t.textDim, fontSize: 11),
                ),
              ),
            if (_isIsm && running)
              StreamBuilder<SdrFrame>(
                stream: _c.frameStream,
                builder: (context, _) => _c.scanStatus.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_c.scanStatus,
                            style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 11,
                                fontFamily: AppTheme.mono)),
                      ),
              ),
            if (_mode == SdrMode.adsb) ...[
              const SizedBox(height: 8),
              StreamBuilder<SdrFrame>(
                stream: _c.frameStream,
                builder: (context, _) {
                  final n = _c.adsbAircraft.where((a) => a.hasFix).length;
                  return OutlinedButton.icon(
                    onPressed: _busy || n == 0 ? null : _uploadAdsb,
                    icon: const Icon(Icons.flight_takeoff, size: 18),
                    label: Text('Upload $n aircraft to WDGWars'),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            if (showChips)
              StreamBuilder<SdrFrame>(
                stream: _c.frameStream,
                builder: (context, _) => _CategoryBar(
                  detections: _c.detections,
                  selected: _catFilter,
                  t: t,
                  onSelect: (c) => setState(() => _catFilter = c),
                ),
              ),
            if (showChips) const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: StreamBuilder<SdrFrame>(
                stream: _c.frameStream,
                builder: (context, _) => _mode == SdrMode.spectrum
                    ? _SpectrumView(power: _c.power, color: AppTheme.accent, grid: t.border)
                    : _DetectionList(
                        detections: _c.detections,
                        t: t,
                        showRaw: _showRaw,
                        catFilter: showChips ? _catFilter : null,
                      ),
              ),
            ),
            if (_mode == SdrMode.spectrum) ...[
              const SizedBox(height: 8),
              Expanded(
                flex: 1,
                child: StreamBuilder<SdrFrame>(
                  stream: _c.frameStream,
                  builder: (context, _) => _DetectionList(
                      detections: _c.detections, t: t, showRaw: _showRaw, catFilter: null),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Sdr433Category? _categoryOf(SdrDetection d) {
  switch (d.kind) {
    case 'tpms':
      return Sdr433Category.tpms;
    case 'rtl433':
      return classify433((d.fields['model'] as String?) ?? '', d.fields.keys);
    default:
      return null;
  }
}

Color _catColor(Sdr433Category c) => AppTheme.themed(switch (c) {
      Sdr433Category.tpms => AppTheme.wardrive,
      Sdr433Category.meter => AppTheme.wigle,
      Sdr433Category.security => AppTheme.error,
      Sdr433Category.fob => AppTheme.flockBle,
      Sdr433Category.environmental => AppTheme.detector,
      Sdr433Category.weather => AppTheme.skySpy,
      Sdr433Category.unknown => AppTheme.textDim,
    });

class _BandSelector extends StatelessWidget {
  const _BandSelector(
      {required this.bands, required this.enabled, required this.t, required this.onToggle});

  final Set<int> bands;
  final bool enabled;
  final ResolvedTheme t;
  final void Function(int) onToggle;

  @override
  Widget build(BuildContext context) {
    Widget chip(int mhz, bool last) {
      final on = bands.contains(mhz);
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: last ? 0 : 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onToggle(mhz) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? t.fill : Colors.transparent,
                border: Border.all(color: on ? AppTheme.accent : t.border),
              ),
              child: Text('$mhz',
                  style: TextStyle(
                    color: on ? t.textPrimary : t.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppTheme.mono,
                  )),
            ),
          ),
        ),
      );
    }

    return Row(children: [chip(315, false), chip(433, false), chip(915, true)]);
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.detections, required this.selected, required this.t, required this.onSelect});

  final List<SdrDetection> detections;
  final Object? selected;
  final ResolvedTheme t;
  final void Function(Object?) onSelect;

  @override
  Widget build(BuildContext context) {
    final counts = <Sdr433Category, int>{};
    var total = 0;
    for (final d in detections) {
      final c = _categoryOf(d);
      if (c == null) continue;
      counts[c] = (counts[c] ?? 0) + 1;
      total++;
    }
    final chips = <Widget>[
      _chip(label: 'All', count: total, color: t.textPrimary, active: selected == null, onTap: () => onSelect(null)),
      for (final c in Sdr433Category.values)
        _chip(
          label: c.label,
          count: counts[c] ?? 0,
          color: _catColor(c),
          active: selected == c,
          onTap: () => onSelect(c),
        ),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _chip({
    required String label,
    required int count,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.fill : Colors.transparent,
          border: Border.all(color: active ? color : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  color: active ? t.textPrimary : t.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(width: 6),
            Text('$count',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: AppTheme.mono,
                )),
          ],
        ),
      ),
    );
  }
}

class _SpectrumView extends StatelessWidget {
  const _SpectrumView({required this.power, required this.color, required this.grid});

  final List<double> power;
  final Color color;
  final Color grid;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SpectrumPainter(power, color, grid), child: const SizedBox.expand());
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.power, this.color, this.grid);

  final List<double> power;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final gp = Paint()
      ..color = grid.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (power.length < 2) return;
    const minDb = -100.0;
    const maxDb = 0.0;
    final path = Path();
    final fill = Path();
    for (var i = 0; i < power.length; i++) {
      final x = size.width * i / (power.length - 1);
      final norm = ((power[i] - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
      final y = size.height * norm;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => true;
}

class _DetectionList extends StatelessWidget {
  const _DetectionList({required this.detections, required this.t, required this.showRaw, required this.catFilter});

  final List<SdrDetection> detections;
  final ResolvedTheme t;
  final bool showRaw;
  final Object? catFilter;

  @override
  Widget build(BuildContext context) {
    final items = detections.where((d) {
      if (d.kind == 'ism') return showRaw;
      if (catFilter is Sdr433Category) return _categoryOf(d) == catFilter;
      return true;
    }).toList();
    if (items.isEmpty) {
      final ismCount = detections.where((d) => d.kind == 'ism').length;
      final msg = (ismCount > 0 && !showRaw)
          ? 'No decoded devices yet — $ismCount raw burst${ismCount == 1 ? '' : 's'} heard.\nTurn on RAW (top right) to see them.'
          : 'No signals yet';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 12)),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => _DetectionCard(d: items[i], t: t),
    );
  }
}

void _showSdrDetail(BuildContext context, SdrDetection d, ResolvedTheme t) {
  final cat = _categoryOf(d);
  final accent = cat != null ? _catColor(cat) : t.textDim;
  final f = d.fields;
  final hz = d.frequency;
  final isIsm = d.kind == 'tpms' || d.kind == 'rtl433';
  final vehicle = isIsm ? identifyVehicle(f['model'] as String?) : null;
  final desc = switch (d.kind) {
    'adsb' => 'Aircraft broadcasting ADS-B position',
    'ism' => 'Raw 433 MHz burst (not decoded to a known device)',
    'rf' => 'RF signal peak',
    _ => cat != null ? describeModel(f['model'] as String?, cat) : 'RF signal',
  };
  final title = switch (d.kind) {
    'adsb' => ((f['callsign'] as String?)?.trim().isNotEmpty ?? false)
        ? (f['callsign'] as String).trim()
        : '${f['icao'] ?? 'ADS-B'}',
    'tpms' || 'rtl433' => '${f['model'] ?? d.kind}',
    'ism' => '${f['modulation'] ?? 'burst'}',
    _ => hz != null ? '${(hz / 1e6).toStringAsFixed(3)} MHz' : 'RF',
  };

  final rows = <(String, String)>[];
  for (final e in f.entries) {
    if (const {'kind'}.contains(e.key)) continue;
    final v = e.value;
    if (v == null) continue;
    final s = v is double ? _trimDouble(v) : '$v';
    if (s.isEmpty) continue;
    rows.add((sdrFieldLabel(e.key), s));
  }
  if (d.kind == 'tpms') {
    final kpa = (f['pressureKpa'] as num?)?.toDouble();
    if (kpa != null) {
      rows.add(('Pressure (psi)', (kpa * 0.1450377).toStringAsFixed(1)));
      rows.add(('Pressure (bar)', (kpa * 0.01).toStringAsFixed(2)));
    }
    final c = (f['tempC'] as num?)?.toDouble();
    if (c != null) rows.add(('Temperature (°F)', (c * 9 / 5 + 32).toStringAsFixed(1)));
  }
  if (hz != null) {
    rows.add(('Frequency', '${(hz / 1e6).toStringAsFixed(3)} MHz'));
  }

  void copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied', style: TextStyle(color: t.textPrimary)),
      backgroundColor: t.surfaceLight,
      duration: const Duration(seconds: 1),
    ));
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    builder: (ctx) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.fill,
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                _Badge(label: cat?.label ?? d.kind, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontFamily: AppTheme.mono,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: t.textSecondary),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc,
                      style: TextStyle(color: t.textSecondary, fontSize: 13)),
                  if (vehicle != null) ...[
                    const SizedBox(height: 6),
                    Text(vehicle.text,
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 12),
                  for (final r in rows)
                    GestureDetector(
                      onTap: () => copy(r.$1, r.$2),
                      onLongPress: () => copy(r.$1, r.$2),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(r.$1,
                                  style: TextStyle(
                                      color: t.textDim, fontSize: 12)),
                            ),
                            Expanded(
                              child: Text(r.$2,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 12,
                                    fontFamily: AppTheme.mono,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text('tap any row to copy',
                        style: TextStyle(
                            color: t.textDim,
                            fontSize: 10,
                            fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _trimDouble(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(v.abs() < 1 ? 5 : 3);
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.d, required this.t});

  final SdrDetection d;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final cat = _categoryOf(d);
    final accent = cat != null ? _catColor(cat) : t.textDim;
    final f = d.fields;

    final String badge;
    final String title;
    final List<String> specs = [];
    String? sub;

    switch (d.kind) {
      case 'tpms':
        badge = 'TPMS';
        title = '${f['model'] ?? 'TPMS'}';
        sub = identifyVehicle(f['model'] as String?)?.text;
        final id = f['id'];
        if (id != null) specs.add('id $id');
        final p = f['pressureKpa'] as num?;
        if (p != null) specs.add('${p.toStringAsFixed(0)} kPa (${(p * 0.1450377).toStringAsFixed(0)} psi)');
        final tc = f['tempC'] as num?;
        if (tc != null) specs.add('${tc.toStringAsFixed(0)}°C');
        final flags = f['flags'] as String?;
        if (flags != null && flags.isNotEmpty) specs.add(flags);
        break;
      case 'rtl433':
        badge = cat?.label ?? 'RTL433';
        title = '${f['model'] ?? 'device'}';
        sub = identifyVehicle(f['model'] as String?)?.text;
        final id = f['id'];
        if (id != null) specs.add('id $id');
        for (final k in const ['temperature_C', 'humidity', 'pressure_kPa', 'wind_avg_km_h', 'rain_mm', 'moisture', 'battery_ok']) {
          final v = f[k];
          if (v != null) specs.add('$k $v');
        }
        break;
      case 'adsb':
        badge = 'ADS-B';
        final cs = (f['callsign'] as String?)?.trim();
        title = cs != null && cs.isNotEmpty ? cs : '${f['icao']}';
        final lat = f['lat'] as num?;
        final lon = f['lon'] as num?;
        if (lat != null && lon != null) specs.add('${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}');
        final alt = f['altitude'] as num?;
        if (alt != null) specs.add('$alt ft');
        final vel = f['velocity'] as num?;
        if (vel != null) specs.add('${vel.toStringAsFixed(0)} kt');
        final hdg = f['heading'] as num?;
        if (hdg != null) specs.add('${hdg.toStringAsFixed(0)}°');
        if (cs != null && cs.isNotEmpty) sub = '${f['icao']}';
        break;
      case 'ism':
        badge = 'RAW';
        title = '${f['modulation'] ?? 'burst'}';
        specs.add('${f['bitCount']} bits');
        final rssi = d.rssi;
        if (rssi != null) specs.add('$rssi dB');
        final bits = f['bits'] as String?;
        if (bits != null) specs.add(bits.length > 24 ? '${bits.substring(0, 24)}…' : bits);
        break;
      default:
        badge = 'RF';
        final hz = d.frequency ?? 0;
        title = '${(hz / 1e6).toStringAsFixed(3)} MHz';
        specs.add('${d.rssi ?? 0} dB');
    }
    final rssi = d.rssi;
    if (d.kind != 'ism' && d.kind != 'rf' && rssi != null) specs.add('$rssi dB');
    final count = f['count'] as int?;
    if (count != null && count > 1) specs.add('×$count');

    final isRaw = d.kind == 'ism';
    final titleColor = isRaw ? t.textSecondary : accent;
    final hz = d.frequency;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSdrDetail(context, d, t),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(left: BorderSide(color: accent, width: 3), bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(label: badge, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontFamily: AppTheme.mono,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hz != null && d.kind != 'adsb')
                Text('${(hz / 1e6).toStringAsFixed(3)} MHz',
                    style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: AppTheme.mono)),
            ],
          ),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(color: t.textSecondary, fontSize: 11)),
          ],
          if (specs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final s in specs)
                  Text(s,
                      style: TextStyle(
                        color: isRaw ? t.textDim : t.textSecondary,
                        fontSize: 11,
                        fontFamily: AppTheme.mono,
                      )),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: AppTheme.mono,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
