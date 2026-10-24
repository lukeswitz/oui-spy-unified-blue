part of 'wardrive_screen.dart';

class _CompletedSessionBar extends ConsumerStatefulWidget {
  const _CompletedSessionBar({required this.wd, required this.onZoomDetection});
  final WardriveController wd;
  final void Function(Detection) onZoomDetection;

  @override
  ConsumerState<_CompletedSessionBar> createState() => _CompletedSessionBarState();
}

class _CompletedSessionBarState extends ConsumerState<_CompletedSessionBar> {
  WardriveController get wd => widget.wd;

  bool get _flockExpanded => wd.flockFilter;
  bool get _detectorExpanded => wd.detectorFilter;

  void _showFlockDetailSheet(BuildContext context, Detection d) =>
      showDetectionDetails(context, ref, d);

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final wigle = ref.watch(wigleProvider);
    final wdg = ref.watch(wdgwarsProvider);
    final sid = wd.lastCompletedSessionId ?? wd.sessionId;
    final isUploaded = wigle.isUploaded(sid);
    final isUploading = wigle.isUploading(sid);
    final wdgUploaded = wdg.isUploaded(sid);
    final wdgUploading = wdg.isUploading(sid);
    final wdgQueued = wdg.isQueued(sid);
    final flockDets = wd.flockDetections;
    final detectorDets = wd.detectorDetections;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: stats text
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: AppTheme.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${wd.uniqueMacs.length} unique  \u00b7  ${wd.rawDetectionCount} total  \u00b7  ${UnitFormatter.distance(wd.distanceKm, units)}',
                  style: TextStyle(
                    color: t.textSecondary, fontSize: 10,
                    fontFamily: AppTheme.mono, fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => wd.clearMapData(),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 14, color: t.textDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: cam chip + action buttons
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wd.flockCount > 0
                    ? () => wd.toggleFlockFilter()
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _flockExpanded
                        ? AppTheme.flockBle.withValues(alpha: 0.25)
                        : wd.flockCount > 0
                            ? AppTheme.flockBle.withValues(alpha: 0.10)
                            : t.surface.withValues(alpha: 0.5),
                    border: Border.all(
                      color: _flockExpanded
                          ? AppTheme.flockBle.withValues(alpha: 0.7)
                          : wd.flockCount > 0
                              ? AppTheme.flockBle.withValues(alpha: 0.35)
                              : t.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 12,
                          color: wd.flockCount > 0
                              ? AppTheme.flockBle
                              : t.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${wd.flockCount}',
                        style: TextStyle(
                          color: wd.flockCount > 0
                              ? AppTheme.flockBle
                              : t.textDim,
                          fontSize: 10,
                          fontFamily: AppTheme.mono, fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (wd.flockCount > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _flockExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 12, color: AppTheme.flockBle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: wd.droneCount > 0
                      ? AppTheme.skySpy.withValues(alpha: 0.10)
                      : t.surface.withValues(alpha: 0.5),
                  border: Border.all(
                    color: wd.droneCount > 0
                        ? AppTheme.skySpy.withValues(alpha: 0.35)
                        : t.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flight, size: 12,
                        color: wd.droneCount > 0
                            ? AppTheme.skySpy
                            : t.textDim),
                    const SizedBox(width: 4),
                    Text(
                      '${wd.droneCount}',
                      style: TextStyle(
                        color: wd.droneCount > 0
                            ? AppTheme.skySpy
                            : t.textDim,
                        fontSize: 10,
                        fontFamily: AppTheme.mono, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wd.detectorCount > 0
                    ? () => wd.toggleDetectorFilter()
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _detectorExpanded
                        ? AppTheme.detector.withValues(alpha: 0.25)
                        : wd.detectorCount > 0
                            ? AppTheme.detector.withValues(alpha: 0.10)
                            : t.surface.withValues(alpha: 0.5),
                    border: Border.all(
                      color: _detectorExpanded
                          ? AppTheme.detector.withValues(alpha: 0.7)
                          : wd.detectorCount > 0
                              ? AppTheme.detector.withValues(alpha: 0.35)
                              : t.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar, size: 12,
                          color: wd.detectorCount > 0
                              ? AppTheme.detector
                              : t.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${wd.detectorCount}',
                        style: TextStyle(
                          color: wd.detectorCount > 0
                              ? AppTheme.detector
                              : t.textDim,
                          fontSize: 10,
                          fontFamily: AppTheme.mono, fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (wd.detectorCount > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _detectorExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 12, color: AppTheme.detector,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _shareCsv(context),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, size: 14, color: AppTheme.accent),
                      SizedBox(width: 4),
                      Text('CSV', style: TextStyle(
                        color: AppTheme.accent, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5,
                      )),
                    ],
                  ),
                ),
              ),
              if (wigle.isLoggedIn) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isUploaded || isUploading
                      ? null
                      : () => _uploadToWigle(context, ref, sid),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isUploaded ? AppTheme.success : AppTheme.warning)
                          .withValues(alpha: 0.15),
                      border: Border.all(
                        color: (isUploaded ? AppTheme.success : AppTheme.warning)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUploading)
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppTheme.warning,
                            ),
                          )
                        else
                          Icon(
                            isUploaded ? Icons.cloud_done : Icons.cloud_upload_outlined,
                            size: 14,
                            color: isUploaded ? AppTheme.success : AppTheme.warning,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          isUploaded ? 'SENT' : 'WIGLE',
                          style: TextStyle(
                            color: isUploaded ? AppTheme.success : AppTheme.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (wdg.isLoggedIn) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: wdgUploaded || wdgUploading
                      ? null
                      : () => _uploadToWdgwars(context, ref, sid),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (wdgUploaded ? AppTheme.success : AppTheme.wdgwars)
                          .withValues(alpha: 0.15),
                      border: Border.all(
                        color: (wdgUploaded ? AppTheme.success : AppTheme.wdgwars)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wdgQueued)
                          Icon(Icons.hourglass_top,
                              size: 14, color: AppTheme.wdgwars)
                        else if (wdgUploading)
                          SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppTheme.wdgwars,
                            ),
                          )
                        else
                          Icon(
                            wdgUploaded ? Icons.cloud_done : Icons.sports_esports,
                            size: 14,
                            color: wdgUploaded ? AppTheme.success : AppTheme.wdgwars,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          wdgQueued
                              ? 'QUEUED'
                              : wdgUploading
                                  ? 'SENDING'
                                  : (wdgUploaded ? 'SENT' : 'WDG'),
                          style: TextStyle(
                            color: wdgUploaded ? AppTheme.success : AppTheme.wdgwars,
                            fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Expandable flock detections panel
          if (_flockExpanded && flockDets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.95),
                border: Border.all(color: AppTheme.flockBle.withValues(alpha: 0.3)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: flockDets.length,
                itemBuilder: (_, i) {
                  final d = flockDets[i];
                  final isBle = d.engine == Engine.flockBle;
                  final engineColor = isBle ? AppTheme.flockBle : AppTheme.flockWifi;
                  final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
                  final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
                  final hasGps = d.latitude != null && d.longitude != null;
                  final isRaven = d.flock?.isRaven ?? false;

                  return Listener(
                    onPointerDown: (event) {
                      if (event.kind == PointerDeviceKind.mouse &&
                          event.buttons == kSecondaryMouseButton) {
                        _showFlockDetailSheet(context, d);
                      }
                    },
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: hasGps ? () => widget.onZoomDetection(d) : null,
                    onLongPress: () => _showFlockDetailSheet(context, d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: i < flockDets.length - 1
                            ? Border(bottom: BorderSide(
                                color: t.border.withValues(alpha: 0.5), width: 0.5))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3, height: 20,
                            decoration: BoxDecoration(
                              color: engineColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      d.macAddress.toUpperCase(),
                                      style: TextStyle(
                                        color: t.textPrimary, fontSize: 10,
                                        fontFamily: AppTheme.mono,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 0.5),
                                      decoration: BoxDecoration(
                                        color: engineColor.withValues(alpha: 0.15),
                                      ),
                                      child: Text(
                                        isBle ? 'BLE' : 'WiFi',
                                        style: TextStyle(
                                          color: engineColor, fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (isRaven) ...[
                                      const SizedBox(width: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3, vertical: 0.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.warning.withValues(alpha: 0.15),
                                        ),
                                        child: Text('RAVEN',
                                          style: TextStyle(
                                            color: AppTheme.warning, fontSize: 7,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'ch${d.channel}',
                                      style: TextStyle(
                                        color: t.textDim, fontSize: 8,
                                        fontFamily: AppTheme.mono,
                                      ),
                                    ),
                                    if (hasGps) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.location_on, size: 8,
                                          color: AppTheme.success.withValues(alpha: 0.7)),
                                    ],
                                    if (!hasGps) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.location_off, size: 8,
                                          color: t.textDim),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${d.rssi}',
                            style: TextStyle(
                              color: rssiColor, fontSize: 12,
                              fontFamily: AppTheme.mono,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('dBm', style: TextStyle(
                            color: t.textDim, fontSize: 7,
                          )),
                        ],
                      ),
                    ),
                  ),
                  );
                },
              ),
            ),
          ],
          if (_detectorExpanded && detectorDets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.95),
                border: Border.all(
                    color: AppTheme.detector.withValues(alpha: 0.3)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: detectorDets.length,
                itemBuilder: (_, i) {
                  final d = detectorDets[i];
                  final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
                  final rssiColor =
                      Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
                  final hasGps = d.latitude != null && d.longitude != null;
                  final desc = d.detector?.filterDescription ?? '';
                  final isFullMac = d.detector?.isFullMac ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: hasGps ? () => widget.onZoomDetection(d) : null,
                    onLongPress: () => _showFlockDetailSheet(context, d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: i < detectorDets.length - 1
                            ? Border(
                                bottom: BorderSide(
                                    color: t.border.withValues(alpha: 0.5),
                                    width: 0.5))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3, height: 20,
                            decoration: BoxDecoration(
                              color: AppTheme.detector,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      d.macAddress.toUpperCase(),
                                      style: TextStyle(
                                        color: t.textPrimary, fontSize: 10,
                                        fontFamily: AppTheme.mono,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 0.5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.detector
                                            .withValues(alpha: 0.15),
                                      ),
                                      child: Text(
                                        isFullMac ? 'MAC' : 'OUI',
                                        style: TextStyle(
                                          color: AppTheme.detector, fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (desc.isNotEmpty || d.deviceName.isNotEmpty)
                                  Text(
                                    desc.isNotEmpty ? desc : d.deviceName,
                                    style: TextStyle(
                                      color: t.textDim, fontSize: 9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (!hasGps) ...[
                            Icon(Icons.location_off,
                                size: 8, color: t.textDim),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${d.rssi}',
                            style: TextStyle(
                              color: rssiColor, fontSize: 12,
                              fontFamily: AppTheme.mono,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('dBm', style: TextStyle(
                            color: t.textDim, fontSize: 7,
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _shareCsv(BuildContext context) async {
    final sid = wd.lastCompletedSessionId ?? wd.sessionId;
    if (sid.isEmpty) return;
    final file = await wd.getCsvFile(sid);
    if (file == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No detection data found for this session')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'OUI-SPY WiGLE CSV',
      sharePositionOrigin: origin,
    ));
  }

  Future<void> _uploadToWigle(BuildContext context, WidgetRef wRef, String sid) async {
    if (sid.isEmpty) return;
    if (!await _confirmWigleUpload(context)) return;
    if (!context.mounted) return;
    final wigle = wRef.read(wigleProvider);
    final result = await wigle.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            'Queued for WiGLE processing',
          ),
        ),
      );
    } else if (wigle.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wigle.error}'),
        ),
      );
    }
  }

  Future<void> _uploadToWdgwars(BuildContext context, WidgetRef wRef, String sid) async {
    if (sid.isEmpty) return;
    if (!await _confirmWdgwarsUpload(context)) return;
    if (!context.mounted) return;
    final wdg = wRef.read(wdgwarsProvider);
    final result = await wdg.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.wdgwars,
          content: Text(result.summary,
              style: TextStyle(color: AppTheme.background)),
        ),
      );
    } else if (wdg.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wdg.error}'),
        ),
      );
    }
  }
}

class _SessionHistorySheet extends ConsumerStatefulWidget {
  const _SessionHistorySheet();

  @override
  ConsumerState<_SessionHistorySheet> createState() =>
      _SessionHistorySheetState();
}

class _SessionHistorySheetState extends ConsumerState<_SessionHistorySheet> {
  bool _selectMode = false;
  final Set<String> _selected = <String>{};
  bool _importing = false;

  void _toggleSelect(String sid) {
    setState(() {
      if (_selected.contains(sid)) {
        _selected.remove(sid);
      } else {
        _selected.add(sid);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final db = ref.watch(databaseProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: t.background,
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32, height: 3,
                decoration: BoxDecoration(
                  color: t.textDim),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectMode
                            ? '${_selected.length} SELECTED'
                            : 'WARDRIVE SESSIONS',
                        style: TextStyle(
                          color: t.textPrimary, fontSize: 12,
                          fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    if (_selectMode) ...[
                      _ToolbarChip(
                        label: 'DELETE',
                        color: AppTheme.error,
                        enabled: _selected.isNotEmpty,
                        onTap: () => _deleteSelected(context),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: 'CANCEL',
                        color: t.textDim,
                        onTap: _exitSelectMode,
                      ),
                    ] else ...[
                      _ToolbarChip(
                        label: 'SELECT',
                        color: AppTheme.accent,
                        onTap: () => setState(() => _selectMode = true),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: _importing ? 'IMPORTING' : 'IMPORT',
                        color: AppTheme.warning,
                        isLoading: _importing,
                        onTap: _importing ? null : () => _importCsv(context),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: 'CLEAR ALL',
                        color: AppTheme.error,
                        onTap: () => _clearAllSessions(context, ref),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<Session>>(
                  stream: db.watchWardriveSessions(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator(
                        color: AppTheme.accent, strokeWidth: 2));
                    }
                    final sessions = snapshot.data!
                        .where((s) => s.endedAt != null)
                        .toList();
                    if (sessions.isEmpty) {
                      return Center(child: Text(
                        'No completed sessions',
                        style: TextStyle(color: t.textDim, fontSize: 12),
                      ));
                    }
                    final wigle = ref.watch(wigleProvider);
                    final wdg = ref.watch(wdgwarsProvider);
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: sessions.length,
                      itemBuilder: (_, i) {
                        final sid = sessions[i].id;
                        final isSelected = _selected.contains(sid);
                        return _SessionRow(
                          session: sessions[i],
                          flockCountFuture: db.flockMacCount(sid),
                          detectorCountFuture: db.detectorMacCount(sid),
                          droneCountFuture: db.droneMacCount(sid),
                          wifiBleFuture: db.wifiBleUniqueCounts(sid),
                          selectable: _selectMode,
                          selected: isSelected,
                          onTap: () {
                            if (_selectMode) {
                              _toggleSelect(sid);
                            } else {
                              Navigator.pop(context);
                              ref.read(wardriveProvider).loadSession(sid);
                            }
                          },
                          onLongPress: () {
                            if (!_selectMode) {
                              setState(() {
                                _selectMode = true;
                                _selected.add(sid);
                              });
                            }
                          },
                          onShare: () => _shareSession(context, ref, sid),
                          onDelete: () => _deleteSession(context, ref, sessions[i]),
                          onUploadWigle: wigle.isLoggedIn
                              ? () => _uploadToWigle(context, ref, sid)
                              : null,
                          wigleUploaded: wigle.isUploaded(sid),
                          wigleUploading: wigle.isUploading(sid),
                          onUploadWdgwars: wdg.isLoggedIn
                              ? () => _uploadToWdgwars(context, ref, sid)
                              : null,
                          wdgwarsUploaded: wdg.isUploaded(sid),
                          wdgwarsUploading: wdg.isUploading(sid),
                          wdgwarsQueued: wdg.isQueued(sid),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selected.isEmpty) return;
    final t = AppTheme.of(context);
    final db = ref.read(databaseProvider);
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Delete $count Sessions', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete $count selected sessions and all their detections? This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final wd = ref.read(wardriveProvider);
    final toDelete = _selected.toList();
    await db.deleteSessions(toDelete);
    if (toDelete.contains(wd.loadedSessionId)) {
      wd.clearLoadedSession();
    }
    if (mounted) _exitSelectMode();
  }

  Future<void> _importCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final path = file.path;
    if (path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not access selected file')),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      final db = ref.read(databaseProvider);
      final watchlist =
          List<WatchlistEntry>.from(ref.read(watchlistProvider).entries);
      final res = await WigleCsvImport.importFile(
        db,
        File(path),
        watchlist: watchlist,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.success,
        content: Text(
          'Imported ${res.detectionCount} detections '
          '(${res.uniqueMacs} unique MACs'
          '${res.detectorMacs > 0 ? ", ${res.detectorMacs} watchlist" : ""}'
          '${res.flockMacs > 0 ? ", ${res.flockMacs} flock" : ""}'
          '${res.skipped > 0 ? ", ${res.skipped} skipped" : ""})',
        ),
      ));
    } on FormatException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Import failed: ${e.message}'),
      ));
    } on FileSystemException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Import failed: ${e.message}'),
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clearAllSessions(BuildContext context, WidgetRef ref) async {
    final t = AppTheme.of(context);
    final db = ref.read(databaseProvider);
    final sessions = await db.getWardriveSessions();
    final completed = sessions.where((s) => s.endedAt != null).toList();
    if (completed.isEmpty) return;
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Clear All Sessions', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete all ${completed.length} wardrive sessions and their detections? This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await db.deleteSessions([for (final s in completed) s.id]);
      ref.read(wardriveProvider).clearMapData();
    }
  }

  Future<void> _deleteSession(BuildContext context, WidgetRef ref, Session session) async {
    final t = AppTheme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Delete Session', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete this session and all its ${session.detectionCount} detections? This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.deleteSession(session.id);
      // Clear loaded session if it was the deleted one
      final wd = ref.read(wardriveProvider);
      if (wd.loadedSessionId == session.id) {
        wd.clearLoadedSession();
      }
    }
  }

  Future<void> _shareSession(BuildContext context, WidgetRef ref, String sid) async {
    final wd = ref.read(wardriveProvider);
    final file = await wd.getCsvFile(sid);
    if (file != null) {
      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'OUI-SPY WiGLE CSV',
        sharePositionOrigin: origin,
      ));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No detection data found for this session')),
        );
      }
    }
  }

  Future<void> _uploadToWigle(BuildContext context, WidgetRef ref, String sid) async {
    final wigle = ref.read(wigleProvider);
    final wd = ref.read(wardriveProvider);

    if (wigle.isUploading(sid)) return;
    if (!await _confirmWigleUpload(context)) return;
    if (!context.mounted) return;

    final result = await wigle.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            'Queued for WiGLE processing',
          ),
        ),
      );
    } else if (wigle.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wigle.error}'),
        ),
      );
    }
  }

  Future<void> _uploadToWdgwars(BuildContext context, WidgetRef ref, String sid) async {
    final wdg = ref.read(wdgwarsProvider);
    final wd = ref.read(wardriveProvider);

    if (wdg.isUploading(sid)) return;
    if (!await _confirmWdgwarsUpload(context)) return;
    if (!context.mounted) return;

    final result = await wdg.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.wdgwars,
          content: Text(result.summary,
              style: TextStyle(color: AppTheme.background)),
        ),
      );
    } else if (wdg.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wdg.error}'),
        ),
      );
    }
  }
}

Future<bool> _confirmWdgwarsUpload(BuildContext context) async {
  final t = AppTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      title: Text('Upload to WDGWars?',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
      content: Text(
        'This publishes this session — network MACs, SSIDs and GPS coordinates — '
        'to the WDGWars map for your gang. Once uploaded it cannot be retracted.',
        style: TextStyle(color: t.textDim, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.wdgwars,
            foregroundColor: AppTheme.background,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('UPLOAD'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<bool> _confirmWigleUpload(BuildContext context) async {
  final t = AppTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      title: Text('Upload to WiGLE?',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
      content: Text(
        'This publishes this session — network MACs, SSIDs and GPS coordinates — '
        'to the public WiGLE.net database. Once uploaded it cannot be retracted.',
        style: TextStyle(color: t.textDim, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('UPLOAD'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
    this.onLongPress,
    this.selectable = false,
    this.selected = false,
    this.onUploadWigle,
    this.wigleUploaded = false,
    this.wigleUploading = false,
    this.onUploadWdgwars,
    this.wdgwarsUploaded = false,
    this.wdgwarsUploading = false,
    this.wdgwarsQueued = false,
    this.flockCountFuture,
    this.detectorCountFuture,
    this.droneCountFuture,
    this.wifiBleFuture,
  });
  final Session session;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool selectable;
  final bool selected;
  final VoidCallback? onUploadWigle;
  final bool wigleUploaded;
  final bool wigleUploading;
  final VoidCallback? onUploadWdgwars;
  final bool wdgwarsUploaded;
  final bool wdgwarsUploading;
  final bool wdgwarsQueued;
  final Future<int>? flockCountFuture;
  final Future<int>? detectorCountFuture;
  final Future<int>? droneCountFuture;
  final Future<({int wifi, int ble})>? wifiBleFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final wd = ref.watch(wardriveProvider);
    final isRescanning = wd.rescanSessionId == session.id;
    final start = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
    final dateStr = AppTime.dateTime(start);
    final duration = session.endedAt != null
        ? Duration(milliseconds: session.endedAt! - session.startedAt)
        : Duration.zero;
    final durStr = '${duration.inMinutes}m ${duration.inSeconds % 60}s';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : t.surface,
          border: Border.all(
            color: selected ? AppTheme.accent : t.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 440;
            final selectBox = selectable
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: selected ? AppTheme.accent : t.textDim,
                    ),
                  )
                : const SizedBox.shrink();
            final routeIcon = Icon(Icons.route, size: 16, color: AppTheme.accent);
            final dateText = Text(dateStr, style: TextStyle(
              color: t.textPrimary, fontSize: 11,
              fontFamily: AppTheme.mono, fontWeight: FontWeight.w500,
            ));
            final durText = SizedBox(
              width: 46,
              child: Text(durStr, style: TextStyle(
                color: t.textDim, fontSize: 10,
                fontFamily: AppTheme.mono,
              )),
            );
            final wifiStat = SizedBox(
              width: 44,
              child: FutureBuilder<({int wifi, int ble})>(
                future: wifiBleFuture,
                builder: (_, wbSnap) {
                  final wb = wbSnap.data;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi, size: 11, color: AppTheme.accent),
                      const SizedBox(width: 2),
                      Text(
                        '${wb?.wifi ?? session.uniqueMacCount}',
                        style: TextStyle(
                          color: AppTheme.accent, fontSize: 10,
                          fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
            final bleStat = SizedBox(
              width: 40,
              child: FutureBuilder<({int wifi, int ble})>(
                future: wifiBleFuture,
                builder: (_, wbSnap) {
                  final wb = wbSnap.data;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth, size: 11, color: Colors.blue),
                      const SizedBox(width: 1),
                      Text(
                        '${wb?.ble ?? 0}',
                        style: TextStyle(
                          color: Colors.blue, fontSize: 10,
                          fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
            final distText = Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 66,
                child: Text(
                  UnitFormatter.distance(session.distanceKm, units),
                  style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontFamily: AppTheme.mono,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
            final flockStat = SizedBox(
              width: 32,
              child: flockCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: flockCountFuture,
                      builder: (_, snap) {
                        final fc = snap.data ?? 0;
                        if (fc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, size: 11, color: AppTheme.flockBle),
                            const SizedBox(width: 2),
                            Text(
                              '$fc',
                              style: TextStyle(
                                color: AppTheme.flockBle, fontSize: 10,
                                fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final detectorStat = SizedBox(
              width: 32,
              child: detectorCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: detectorCountFuture,
                      builder: (_, snap) {
                        final dc = snap.data ?? 0;
                        if (dc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radar, size: 11, color: AppTheme.detector),
                            const SizedBox(width: 2),
                            Text(
                              '$dc',
                              style: TextStyle(
                                color: AppTheme.detector, fontSize: 10,
                                fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final droneStat = SizedBox(
              width: 32,
              child: droneCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: droneCountFuture,
                      builder: (_, snap) {
                        final dc = snap.data ?? 0;
                        if (dc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flight,
                                size: 11, color: AppTheme.skySpy),
                            const SizedBox(width: 2),
                            Text(
                              '$dc',
                              style: TextStyle(
                                color: AppTheme.skySpy, fontSize: 10,
                                fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final csvBtn = _SessionIconBtn(
              icon: Icons.file_download_outlined,
              label: 'CSV',
              color: AppTheme.accent,
              onTap: onShare,
            );
            final wigleBtn = onUploadWigle == null
                ? null
                : _SessionIconBtn(
                    icon: wigleUploading
                        ? Icons.cloud_sync
                        : (wigleUploaded
                            ? Icons.cloud_done
                            : Icons.cloud_upload_outlined),
                    label: wigleUploading
                        ? 'SENDING'
                        : (wigleUploaded ? 'SENT' : 'WIGLE'),
                    color: wigleUploading
                        ? AppTheme.warning
                        : (wigleUploaded ? AppTheme.success : AppTheme.warning),
                    onTap: (wigleUploaded || wigleUploading) ? null : onUploadWigle,
                    isLoading: wigleUploading,
                  );
            final wdgwarsBtn = onUploadWdgwars == null
                ? null
                : _SessionIconBtn(
                    icon: wdgwarsQueued
                        ? Icons.hourglass_top
                        : (wdgwarsUploading
                            ? Icons.cloud_sync
                            : (wdgwarsUploaded
                                ? Icons.cloud_done
                                : Icons.sports_esports)),
                    label: wdgwarsQueued
                        ? 'QUEUED'
                        : (wdgwarsUploading
                            ? 'SENDING'
                            : (wdgwarsUploaded ? 'SENT' : 'WDG')),
                    color: wdgwarsUploaded ? AppTheme.success : AppTheme.wdgwars,
                    onTap: (wdgwarsUploaded || wdgwarsUploading) ? null : onUploadWdgwars,
                    isLoading: wdgwarsUploading && !wdgwarsQueued,
                  );
            final delBtn = _SessionIconBtn(
              icon: Icons.delete_forever_outlined,
              label: 'DEL',
              color: AppTheme.error,
              onTap: onDelete,
            );
            final actionButtons = <Widget>[
              csvBtn,
              const SizedBox(width: 4),
              if (wigleBtn != null) ...[
                wigleBtn,
                const SizedBox(width: 4),
              ],
              if (wdgwarsBtn != null) ...[
                wdgwarsBtn,
                const SizedBox(width: 4),
              ],
              delBtn,
            ];
            final buttons = <Widget>[
              csvBtn,
              ?wigleBtn,
              ?wdgwarsBtn,
              delBtn,
            ];
            final actionBar = Row(
              children: [
                for (int i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: buttons[i]),
                ],
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (narrow) ...[
                  Row(
                    children: [
                      selectBox,
                      routeIcon,
                      const SizedBox(width: 8),
                      Expanded(child: dateText),
                      durText,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      wifiStat,
                      bleStat,
                      distText,
                      flockStat,
                      droneStat,
                      detectorStat,
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  actionBar,
                ] else
                  Row(
                    children: [
                      selectBox,
                      routeIcon,
                      const SizedBox(width: 8),
                      dateText,
                      const SizedBox(width: 10),
                      durText,
                      wifiStat,
                      bleStat,
                      distText,
                      flockStat,
                      droneStat,
                      detectorStat,
                      const Spacer(),
                      ...actionButtons,
                    ],
                  ),
                if (isRescanning) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.detector,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        wd.rescanTotal == 0
                            ? 'CHECKING OUIs'
                            : 'CHECK ${wd.rescanCur}/${wd.rescanTotal}'
                                '${wd.rescanNewDetector > 0 ? ' +${wd.rescanNewDetector}d' : ''}'
                                '${wd.rescanNewFlock > 0 ? ' +${wd.rescanNewFlock}f' : ''}',
                        style: TextStyle(
                          color: AppTheme.detector,
                          fontSize: 9,
                          fontFamily: AppTheme.mono,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionIconBtn extends StatelessWidget {
  const _SessionIconBtn({
    required this.icon,
    required this.color,
    this.label,
    this.onTap,
    this.isLoading = false,
  });
  final IconData icon;
  final Color color;
  final String? label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || isLoading;
    final c = enabled ? color : color.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 5),
        constraints: BoxConstraints(minWidth: label == null ? 26 : 0),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: c),
              )
            else
              Icon(icon, size: 15, color: c),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label!,
                style: TextStyle(
                  color: c,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.color,
    this.onTap,
    this.enabled = true,
    this.isLoading = false,
  });
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final live = enabled && onTap != null && !isLoading;
    final c = live ? color : color.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: live ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 9, height: 9,
                child: CircularProgressIndicator(strokeWidth: 1.2, color: c),
              ),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              color: c.withValues(alpha: 0.9),
              fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
          ],
        ),
      ),
    );
  }
}

class _FoxhuntBadge extends StatelessWidget {
  const _FoxhuntBadge({required this.mac});
  final String mac;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.9),
        border: Border.all(color: AppTheme.foxhunter.withValues(alpha: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.gps_fixed, color: AppTheme.foxhunter, size: 20),
        const SizedBox(height: 4),
        Text(
          mac.substring(0, 8),
          style: TextStyle(
            color: AppTheme.foxhunter, fontSize: 9, fontFamily: AppTheme.mono,
          ),
        ),
      ]),
    );
  }
}


