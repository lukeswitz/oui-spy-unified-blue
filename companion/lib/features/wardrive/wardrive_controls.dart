part of 'wardrive_screen.dart';

class _IdleControls extends StatelessWidget {
  const _IdleControls({required this.wd, required this.ref, this.onGeofenceReturn});
  final WardriveController wd;
  final WidgetRef ref;
  final VoidCallback? onGeofenceReturn;

  @override
  Widget build(BuildContext context) {
    final th = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: SessionBar(),
        ),
        const SizedBox(height: 6),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: th.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: th.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.straighten, size: 12, color: th.textDim),
              const SizedBox(width: 6),
              Text('DIST', style: TextStyle(
                color: th.textDim, fontSize: 8,
                fontWeight: FontWeight.w600, letterSpacing: 1,
              )),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
                  child: Slider(
                    value: wd.markerDistanceM,
                    min: 1, max: 100,
                    activeColor: AppTheme.accent,
                    inactiveColor: th.border,
                    onChanged: (v) {
                      ref.read(wardriveProvider).markerDistanceM = v;
                    },
                  ),
                ),
              ),
              Text('${wd.markerDistanceM.round()}m', style: TextStyle(
                color: AppTheme.accent, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: ref.context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _SessionHistorySheet(),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: th.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: th.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 14, color: th.textSecondary),
                    const SizedBox(width: 6),
                    Text('SESSIONS', style: TextStyle(
                      color: th.textSecondary, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  ref.context,
                  MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                );
                onGeofenceReturn?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: th.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: th.border),
                ),
                child: Icon(Icons.fence, size: 14, color: AppTheme.warning),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          color: t.background, fontSize: 13,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(
          color: color, fontSize: 13,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.18)
                : t.surface.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? AppTheme.accent.withValues(alpha: 0.7)
                  : t.border,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? AppTheme.accent : t.textSecondary,
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class _CompassResetBtn extends StatelessWidget {
  const _CompassResetBtn({required this.rotation, required this.onTap});
  final double rotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Tooltip(
      message: 'Tap to reset north up',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.55),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: -rotation * pi / 180.0,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(28, 28),
                    painter: _CompassNeedlePainter(),
                  ),
                  Positioned(
                    top: 2,
                    child: Text(
                      'N',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final red = Paint()..color = const Color(0xFFE54848);
    final gray = Paint()..color = const Color(0xFF888888);
    final pathN = ui.Path()
      ..moveTo(c.dx, c.dy - 10)
      ..lineTo(c.dx - 4, c.dy)
      ..lineTo(c.dx + 4, c.dy)
      ..close();
    final pathS = ui.Path()
      ..moveTo(c.dx, c.dy + 10)
      ..lineTo(c.dx - 4, c.dy)
      ..lineTo(c.dx + 4, c.dy)
      ..close();
    canvas.drawPath(pathN, red);
    canvas.drawPath(pathS, gray);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeasuredBox extends StatefulWidget {
  const _MeasuredBox({
    required this.statsKey,
    required this.onHeightChanged,
    required this.child,
  });
  final GlobalKey statsKey;
  final ValueChanged<double> onHeightChanged;
  final Widget child;

  @override
  State<_MeasuredBox> createState() => _MeasuredBoxState();
}

class _MeasuredBoxState extends State<_MeasuredBox> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _MeasuredBox old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final box = widget.statsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onHeightChanged(box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: widget.statsKey, child: widget.child);
  }
}

const String _kAlprLayerAction = 'alpr-layer';
const String _kTerritoryLayerAction = 'wdg-territory-layer';

class _LayerLoadingPill extends StatelessWidget {
  const _LayerLoadingPill({
    required this.alprLoading,
    required this.territoriesLoading,
  });
  final bool alprLoading;
  final bool territoriesLoading;

  @override
  Widget build(BuildContext context) {
    if (!alprLoading && !territoriesLoading) return const SizedBox.shrink();
    final t = AppTheme.of(context);
    final color = alprLoading ? AppTheme.flockWifi : AppTheme.wdgwars;
    final label = alprLoading ? 'Loading ALPRs' : 'Loading territories';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStyleButton extends StatelessWidget {
  const _MapStyleButton({
    required this.ref,
    required this.mapStyle,
    this.onAlprToggled,
  });
  final WidgetRef ref;
  final MapStyle mapStyle;
  final VoidCallback? onAlprToggled;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final wdg = ref.watch(wdgwarsProvider);
    final df = ref.watch(deflockProvider);
    return PopupMenuButton<Object?>(
      initialValue: mapStyle,
      onSelected: (choice) async {
        if (choice is MapStyle) {
          ref.read(mapStyleProvider.notifier).setStyle(choice);
        } else if (choice == _kAlprLayerAction) {
          final on = !df.showAlpr;
          await ref.read(deflockProvider).setShowAlpr(on);
          if (on) onAlprToggled?.call();
        } else if (choice == _kTerritoryLayerAction) {
          final messenger = ScaffoldMessenger.of(context);
          final w = ref.read(wdgwarsProvider);
          final turningOn = !wdg.showTerritories;
          await w.setShowTerritories(turningOn);
          if (!turningOn) return;
          final err = w.territoryError;
          messenger.showSnackBar(SnackBar(
            content: Text(err ?? '${w.territories.length} territories loaded'),
            backgroundColor: err != null ? AppTheme.warning : AppTheme.wdgwars,
            duration: const Duration(seconds: 4),
          ));
        }
      },
      offset: const Offset(0, 40),
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.border),
      ),
      itemBuilder: (_) => [
        ...MapStyle.values.map((style) {
          final selected = style == mapStyle;
          return PopupMenuItem<Object?>(
            value: style,
            height: 36,
            child: Row(
              children: [
                Icon(
                  style.isDark ? Icons.dark_mode : Icons.light_mode,
                  size: 14,
                  color: selected ? AppTheme.accent : t.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  style.label,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : t.textPrimary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 14, color: AppTheme.accent),
                ],
              ],
            ),
          );
        }),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<Object?>(
          value: _kAlprLayerAction,
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.videocam_outlined,
                size: 14,
                color: df.showAlpr ? AppTheme.flockWifi : t.textDim,
              ),
              const SizedBox(width: 8),
              Text(
                'MAPPED ALPRs',
                style: TextStyle(
                  color: df.showAlpr ? AppTheme.flockWifi : t.textPrimary,
                  fontSize: 12,
                  fontWeight: df.showAlpr ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (df.loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.flockWifi,
                  ),
                )
              else if (df.showAlpr)
                Icon(Icons.check, size: 14, color: AppTheme.flockWifi),
            ],
          ),
        ),
        if (wdg.isLoggedIn) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem<Object?>(
            value: _kTerritoryLayerAction,
            height: 36,
            child: Row(
              children: [
                Icon(
                  Icons.flag,
                  size: 14,
                  color: wdg.showTerritories ? AppTheme.wdgwars : t.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  'WDG TERRITORY',
                  style: TextStyle(
                    color: wdg.showTerritories
                        ? AppTheme.wdgwars
                        : t.textPrimary,
                    fontSize: 12,
                    fontWeight: wdg.showTerritories
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                if (wdg.territoriesLoading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.wdgwars,
                    ),
                  )
                else if (wdg.showTerritories)
                  Icon(Icons.check, size: 14, color: AppTheme.wdgwars),
              ],
            ),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.border),
        ),
        child: Icon(Icons.layers, size: 16, color: t.textSecondary),
      ),
    );
  }
}

class _FocusedDetectionChip extends StatelessWidget {
  const _FocusedDetectionChip({required this.detection, required this.onClear});
  final Detection detection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final name = detection.deviceName.isNotEmpty
        ? detection.deviceName
        : (detection.ssid.isNotEmpty ? detection.ssid : detection.macAddress);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onClear,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: detection.engine.color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(detection.engine.icon, size: 12, color: detection.engine.color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('SHOW ALL',
                  style: TextStyle(
                    color: t.textDim,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  )),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 12, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionList extends StatelessWidget {
  const _DetectionList({required this.detections, this.onDetectionTap});
  final List<Detection> detections;
  final void Function(Detection)? onDetectionTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    if (detections.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<Detection>>{};
    for (final d in detections) {
      final key = d.engine == Engine.wardrive
          ? (d.isBleDetection ? 'WARDRIVE BLE' : 'WARDRIVE WIFI')
          : d.engine.label;
      (grouped[key] ??= []).add(d);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
              child: Row(
                children: [
                  Icon(entry.value.first.engine.icon,
                      size: 10, color: entry.value.first.engine.color),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.key.toUpperCase()}  ${entry.value.length}',
                    style: TextStyle(
                      color: entry.value.first.engine.color,
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.take(10).map((d) => _DetListRow(d: d, onTap: onDetectionTap)),
          ],
        ],
      ),
    );
  }
}

class _FeedToggle extends StatelessWidget {
  const _FeedToggle({
    required this.count,
    required this.collapsed,
    required this.onTap,
  });
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: t.background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
              color: t.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              collapsed ? 'DEVICES  $count' : 'HIDE DEVICES',
              style: TextStyle(
                color: t.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetListRow extends ConsumerWidget {
  const _DetListRow({required this.d, this.onTap});
  final Detection d;
  final void Function(Detection)? onTap;

  void _showDetailSheet(BuildContext context, WidgetRef ref) =>
      showDetectionDetails(context, ref, d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
    final bool isWifiAp = d.isWifiDetection;
    final bool isHidden = isWifiAp && d.ssid.isEmpty && d.deviceName.isEmpty;
    final vendor = ref.read(ouiLookupProvider).lookup(d.macAddress);
    final label = d.engine == Engine.detector
        ? detectorTitle(d)
        : isHidden
        ? '<hidden>'
        : d.ssid.isNotEmpty
            ? d.ssid
            : d.deviceName.isNotEmpty
                ? d.deviceName
                : vendor ?? '';
    final hasGps = d.latitude != null && d.longitude != null;

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showDetailSheet(context, ref);
        }
      },
      child: GestureDetector(
      onTap: hasGps && onTap != null ? () => onTap!(d) : null,
      onLongPress: () => _showDetailSheet(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Container(width: 2, height: 14,
            decoration: BoxDecoration(
              color: d.engine.color, borderRadius: BorderRadius.circular(1)),
          ),
          const SizedBox(width: 5),
          Text(d.macAddress.toUpperCase(),
            style: TextStyle(
              color: t.textPrimary, fontSize: 9,
              fontFamily: 'monospace', fontWeight: FontWeight.w500,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: vendor != null && d.ssid.isEmpty && d.deviceName.isEmpty
                    ? t.textDim
                    : t.textSecondary,
                fontSize: 9,
              ),
            )),
          ] else
            const Spacer(),
          if (d.count > 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('\u00d7${d.count}',
                style: TextStyle(
                  color: t.textDim, fontSize: 8,
                  fontFamily: 'monospace', fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text('${d.rssi}', style: TextStyle(
            color: rssiColor, fontSize: 9,
            fontFamily: 'monospace', fontWeight: FontWeight.w600,
          )),
        ],
      ),
    ),
    ),
    );
  }
}

class _DetectionLayers {
  const _DetectionLayers({
    required this.heat,
    required this.clusters,
    required this.pins,
    this.tethers = const [],
    this.trails = const [],
    this.rings = const [],
  });
  const _DetectionLayers.empty()
      : heat = const [],
        clusters = const [],
        pins = const [],
        tethers = const [],
        trails = const [],
        rings = const [];
  final List<CircleMarker> heat;
  final List<Marker> clusters;
  final List<Marker> pins;
  final List<Polyline> tethers;
  final List<Polyline> trails;
  final List<CircleMarker> rings;
}

class _ClusterDot extends StatelessWidget {
  const _ClusterDot({
    required this.fill,
    required this.engineColor,
    required this.secondaryEngineColor,
    required this.size,
    required this.count,
    this.neon = false,
  });
  final Color fill;
  final Color engineColor;
  final Color? secondaryEngineColor;
  final double size;
  final int count;
  final bool neon;

  @override
  Widget build(BuildContext context) {
    final label = count >= 1000
        ? '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k'
        : '$count';
    final ringColor = secondaryEngineColor ?? engineColor;
    return RepaintBoundary(
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: CustomPaint(
          painter: _ClusterPainter(
            fill: fill,
            engineColor: engineColor,
            ringColor: ringColor,
            neon: neon,
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.16 + 4),
            child: count > 1
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: neon ? ringColor : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.0,
                          letterSpacing: -0.3,
                          shadows: neon
                              ? [
                                  Shadow(
                                    color: ringColor.withValues(alpha: 0.8),
                                    blurRadius: 8,
                                  ),
                                ]
                              : const [
                                  Shadow(blurRadius: 3, color: Colors.black87),
                                ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _ClusterPainter extends CustomPainter {
  const _ClusterPainter({
    required this.fill,
    required this.engineColor,
    required this.ringColor,
    required this.neon,
  });
  final Color fill;
  final Color engineColor;
  final Color ringColor;
  final bool neon;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;
    if (neon) {
      // Glowing hex ring — synthwave wireframe vibe.
      final path = ui.Path();
      for (var i = 0; i < 6; i++) {
        final a = (pi / 3) * i - pi / 2;
        final x = c.dx + r * cos(a);
        final y = c.dy + r * sin(a);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      // Outer glow.
      canvas.drawPath(
        path,
        Paint()
          ..color = ringColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      // Inner fill.
      canvas.drawPath(
        path,
        Paint()..color = ringColor.withValues(alpha: 0.10),
      );
      // Crisp ring.
      canvas.drawPath(
        path,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    } else {
      canvas.drawCircle(
        c,
        r + 7,
        Paint()
          ..color = fill.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Body.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0),
      );
      // Glow.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = fill.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Stroke.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClusterPainter old) =>
      old.fill != fill ||
      old.engineColor != engineColor ||
      old.ringColor != ringColor ||
      old.neon != neon;
}

