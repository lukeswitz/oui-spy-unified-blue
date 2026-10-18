part of 'device_config.dart';

class _OuiDatabaseSection extends ConsumerStatefulWidget {
  const _OuiDatabaseSection();

  @override
  ConsumerState<_OuiDatabaseSection> createState() => _OuiDatabaseSectionState();
}

class _OuiDatabaseSectionState extends ConsumerState<_OuiDatabaseSection> {
  bool _updating = false;
  String? _status;

  Future<void> _checkUpdate() async {
    setState(() {
      _updating = true;
      _status = null;
    });
    try {
      final oui = ref.read(ouiLookupProvider);
      final updated = await oui.checkForUpdate();
      setState(() {
        _updating = false;
        _status = updated
            ? 'Updated to ${oui.entryCount} vendors'
            : 'Already up to date (${oui.entryCount} vendors)';
      });
    } catch (e) {
      setState(() {
        _updating = false;
        _status = 'Update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final oui = ref.read(ouiLookupProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MAC vendor lookup database (IEEE MA-L, MA-M and MA-S registries via Wireshark manuf)',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.storage, size: 14, color: t.textSecondary),
            const SizedBox(width: 8),
            Text(
              '${oui.entryCount} vendors loaded',
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
            if (oui.lastUpdated != null) ...[
              const SizedBox(width: 8),
              Text(
                'updated ${_formatDate(oui.lastUpdated!)}',
                style: TextStyle(color: t.textDim, fontSize: 10),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _updating ? null : _checkUpdate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updating)
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppTheme.accent,
                    ),
                  )
                else
                  Icon(Icons.refresh, size: 14, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  _updating ? 'Checking...' : 'Check for Update',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!, style: TextStyle(color: t.textSecondary, fontSize: 11)),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }
}

enum _FleetStatus { queued, active, done, failed }

class _FleetItem {
  _FleetItem({required this.id, required this.label, required this.isManager});
  final String id;
  final String label;
  final bool isManager;
  _FleetStatus status = _FleetStatus.queued;
  String detail = 'Queued';
}

class _OtaSection extends ConsumerStatefulWidget {
  const _OtaSection({required this.currentVersion});
  final String currentVersion;

  @override
  ConsumerState<_OtaSection> createState() => _OtaSectionState();
}

class _OtaSectionState extends ConsumerState<_OtaSection> {
  OtaRelease? _availableRelease;
  OtaProgress? _progress;
  StreamSubscription<OtaProgress>? _sub;
  StreamSubscription<({int status, int bytesRead})>? _wifiSub;
  String? _checkStatus;
  bool _wifiConfigured = false;
  int _wifiBytesRead = 0;
  int? _wifiStatus;
  Timer? _wifiPoll;
  OtaRelease? _nodeRelease;
  String? _nodeStatus;
  List<_FleetItem> _fleet = const [];
  bool _fleetRunning = false;
  bool _mgrReconnecting = false;
  bool _autoWifiUpdate = true;
  static const String _autoWifiPrefKey = 'ota_auto_wifi_update';
  String _nodeBoard = 'xiao_s3';
  static const String _nodeBoardPrefKey = 'ota_node_board';
  static const List<String> _nodeBoards = [
    'xiao_s3',
    's3_devkitc',
    'xiao_c5',
    'tdongle_s3',
    'tdongle_c5',
    'stickc',
    'stickc_plus',
    'stickc_plus2',
  ];

  @override
  void initState() {
    super.initState();
    final ota = ref.read(otaServiceProvider);
    _sub = ota.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    _wifiSub = ref.read(bleManagerProvider).wifiOtaUpdates.listen((evt) {
      if (mounted) {
        setState(() {
          _wifiStatus = evt.status;
          _wifiBytesRead = evt.bytesRead;
        });
      }
    });
    _readWifiState();
    _loadAutoWifi();
    _loadNodeBoard();
    // Poll WiFi status every 3s so user sees connection state change
    _wifiPoll = Timer.periodic(const Duration(seconds: 3), (_) => _readWifiState());
  }

  Future<void> _loadAutoWifi() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_autoWifiPrefKey);
    if (v != null && mounted) setState(() => _autoWifiUpdate = v);
  }

  Future<void> _setAutoWifi(bool v) async {
    setState(() => _autoWifiUpdate = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoWifiPrefKey, v);
  }

  Future<void> _loadNodeBoard() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_nodeBoardPrefKey);
    if (v != null && _nodeBoards.contains(v) && mounted) {
      setState(() => _nodeBoard = v);
    }
  }

  Future<void> _setNodeBoard(String v) async {
    setState(() => _nodeBoard = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nodeBoardPrefKey, v);
  }

  String _effectiveNodeBoard() {
    final boards = ref.read(appStateProvider).liveNodeBoards;
    if (boards.contains('')) return _nodeBoard;
    final reported = boards.where((b) => _nodeBoards.contains(b));
    return reported.isNotEmpty ? reported.first : _nodeBoard;
  }

  Future<void> _ensureWifiForUpdate() async {
    return;
  }

  Future<void> _readWifiState() async {
    try {
      final res = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() {
        _wifiConfigured = res.hasCreds;
      });
    } on Exception catch (e) {
      // Older firmware: char absent — leave _wifiConfigured = false
      DebugLog.log('OTA: wifi status read failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wifiSub?.cancel();
    _wifiPoll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checkStatus = 'Checking...';
      _availableRelease = null;
    });
    try {
      final ota = ref.read(otaServiceProvider);
      final ble = ref.read(bleManagerProvider);
      final pair = await ota.fetchLatestPair(
        board: ble.board,
        role: ble.role,
        includeNode: ble.isManagerConnected,
        nodeBoard: _effectiveNodeBoard(),
      );
      if (!mounted) return;
      final primary = pair.primary;
      String status;
      OtaRelease? avail;
      if (pair.error != null) {
        status = pair.error!;
      } else if (primary == null) {
        status = 'No matching firmware in the latest release.';
      } else {
        final cur = OtaService.parseVersion(widget.currentVersion) ?? [0, 0, 0];
        final newer = OtaService.compareVersion(primary.version, cur) > 0;
        avail = newer ? primary : null;
        status = newer
            ? 'Update available: ${primary.tag}'
            : 'Already up to date (${primary.tag})';
      }
      setState(() {
        _availableRelease = avail;
        _nodeRelease = pair.node;
        _checkStatus = status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkStatus = 'Check failed: $e');
    }
  }

  List<Widget> _buildNodeUpdateSection(ResolvedTheme t, bool busy) {
    final ble = ref.read(bleManagerProvider);
    if (!ble.isManagerConnected) return const [];
    final appState = ref.watch(appStateProvider);
    final nodes = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList()
      ..sort();
    final cur = OtaService.parseVersion(widget.currentVersion);
    final nodeNewer = _nodeRelease != null &&
        cur != null &&
        OtaService.compareVersion(_nodeRelease!.version, cur) > 0;

    return [
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Icon(Icons.hub_outlined, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            Text('REMOTE NODES',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_nodeRelease != null)
              Text(
                  nodeNewer
                      ? 'latest ${_nodeRelease!.tag}'
                      : 'latest ${_nodeRelease!.tag} · On latest version',
                  style: TextStyle(
                      color: nodeNewer ? AppTheme.accent : t.textDim,
                      fontSize: 10)),
          ],
        ),
      ),
      if (nodes.any((id) => appState.nodeBoard(id) == null))
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(
          children: [
            Text('Board for nodes on older firmware',
                style: TextStyle(color: t.textSecondary, fontSize: 11)),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _nodeBoard,
              isDense: true,
              dropdownColor: t.surface,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              underline: const SizedBox.shrink(),
              items: [
                for (final b in _nodeBoards)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (busy || _fleetRunning)
                  ? null
                  : (v) {
                      if (v == null || v == _nodeBoard) return;
                      _setNodeBoard(v);
                      _check();
                    },
            ),
          ],
        ),
      ),
      if (nodes.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('No live nodes. Power them on and Check for Update.',
              style: TextStyle(color: t.textDim, fontSize: 11)),
        )
      else if (_nodeRelease == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Tap Check for Update to fetch the latest node firmware.',
              style: TextStyle(color: t.textDim, fontSize: 11)),
        ),
      for (final id in nodes)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            children: [
              Icon(Icons.sensors, size: 14, color: t.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(appState.labelForNode(id),
                    style: TextStyle(color: t.textPrimary, fontSize: 12)),
              ),
              Text(boardDisplayName(appState.nodeBoard(id)),
                  style: TextStyle(color: t.textDim, fontSize: 11)),
              const SizedBox(width: 8),
              Builder(builder: (_) {
                final v = appState.nodeFwVersion(id);
                final outdated = v != null &&
                    _nodeRelease != null &&
                    OtaService.compareVersion(_nodeRelease!.version,
                            OtaService.parseVersion(v) ?? const [0]) >
                        0;
                return Text(
                  v == null ? 'v?' : 'v$v',
                  style: TextStyle(
                    color: outdated ? AppTheme.accent : t.textSecondary,
                    fontSize: 11,
                    fontWeight: outdated ? FontWeight.w700 : FontWeight.w400,
                  ),
                );
              }),
            ],
          ),
        ),
      if (nodes.isNotEmpty && _nodeRelease != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: ElevatedButton.icon(
            onPressed: (busy || _fleetRunning) ? null : _updateNodes,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            icon: const Icon(Icons.wifi, size: 16),
            label: Text(
                'Update ${nodes.length} node${nodes.length == 1 ? '' : 's'} over WiFi'),
          ),
        ),
      if (_nodeStatus != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(_nodeStatus!,
              style: TextStyle(color: t.textSecondary, fontSize: 11)),
        ),
    ];
  }

  Future<void> _installWifi() async {
    final release = _availableRelease;
    if (release == null) return;
    final ota = ref.read(otaServiceProvider);
    await _ensureWifiForUpdate();
    await ota.performWifiUpdate(release);
  }

  Future<bool> _pushWifiFleet(_FleetItem nodesItem) async {
    final ble = ref.read(bleManagerProvider);
    final nodeRelease = _nodeRelease;
    if (nodeRelease == null) return false;
    if (!_wifiConfigured) {
      setState(() {
        nodesItem.status = _FleetStatus.failed;
        nodesItem.detail =
            'Manager has no saved WiFi — set creds in the WIFI NETWORK section first.';
      });
      return false;
    }
    setState(() {
      nodesItem.status = _FleetStatus.active;
      nodesItem.detail = 'Pushing WiFi creds + update to nodes…';
    });
    final done = Completer<bool>();
    final sub = ble.fleetOtaUpdates.listen((e) {
      if (!mounted) return;
      setState(() {
        if (e.phase == 2) {
          nodesItem.status = _FleetStatus.done;
          nodesItem.detail =
              'Pushed — nodes rebooting to self-update over WiFi (~60–90s). '
              'They drop off mesh, then rejoin when done.';
          if (!done.isCompleted) done.complete(true);
        } else if (e.phase == 0x80) {
          nodesItem.status = _FleetStatus.failed;
          nodesItem.detail =
              'Manager has no saved WiFi — set creds in the WIFI NETWORK section first.';
          if (!done.isCompleted) done.complete(false);
        } else if (e.phase == 0x81) {
          nodesItem.status = _FleetStatus.failed;
          nodesItem.detail = 'WiFi creds + URL too long for one mesh packet.';
          if (!done.isCompleted) done.complete(false);
        }
      });
    });
    try {
      await ble.triggerFleetWifiOta(nodeRelease.assetUrl);
      return await done.future
          .timeout(const Duration(seconds: 20), onTimeout: () {
        if (mounted) {
          setState(() {
            nodesItem.status = _FleetStatus.done;
            nodesItem.detail =
                'Update pushed — nodes reboot to self-update over WiFi (~60–90s).';
          });
        }
        return true;
      });
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _updateNodes() async {
    final ble = ref.read(bleManagerProvider);
    final ota = ref.read(otaServiceProvider);
    final managerId = ble.connectedDeviceId;
    if (_nodeRelease == null) {
      setState(() => _nodeStatus = 'Tap "Check for Update" first.');
      return;
    }
    if (managerId == null) {
      setState(() => _nodeStatus = 'Manager not connected.');
      return;
    }
    final appState = ref.read(appStateProvider);
    final nodeIds = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList();
    final nodesItem = _FleetItem(
        id: 'nodes',
        label: nodeIds.isEmpty ? 'Nodes' : 'Nodes (${nodeIds.length})',
        isManager: false);
    setState(() {
      _fleet = [nodesItem];
      _fleetRunning = true;
    });
    ota.markOtaActive(ttl: const Duration(minutes: 3));
    try {
      await _pushWifiFleet(nodesItem);
    } finally {
      ota.clearOtaActive();
      if (mounted) setState(() => _fleetRunning = false);
    }
  }

  Future<void> _updateAll() async {
    final ble = ref.read(bleManagerProvider);
    final ota = ref.read(otaServiceProvider);
    final mgrRelease = _availableRelease;
    final nodeRelease = _nodeRelease;
    final managerId = ble.connectedDeviceId;
    if (managerId == null) {
      setState(() => _checkStatus = 'Manager not connected.');
      return;
    }
    if (mgrRelease == null && nodeRelease == null) {
      setState(() => _checkStatus = 'Tap "Check for Update" first.');
      return;
    }
    final appState = ref.read(appStateProvider);
    final nodeIds = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList();
    final hasNodes = nodeRelease != null;
    final hasMgr = mgrRelease != null;

    final fleet = <_FleetItem>[
      if (hasNodes)
        _FleetItem(
            id: 'nodes',
            label: nodeIds.isEmpty ? 'Nodes' : 'Nodes (${nodeIds.length})',
            isManager: false),
      if (hasMgr)
        _FleetItem(
            id: 'manager',
            label: 'Manager ${appState.labelForNode(appState.nodeId)}',
            isManager: true),
    ];
    setState(() {
      _fleet = fleet;
      _fleetRunning = true;
      _mgrReconnecting = false;
    });
    ota.markOtaActive(ttl: const Duration(minutes: 8));

    try {
      if (hasNodes) {
        await _pushWifiFleet(fleet.first);
        await Future<void>.delayed(const Duration(seconds: 6));
      }

      if (hasMgr) {
        final mgr = fleet.firstWhere((f) => f.isManager);
        setState(() {
          mgr.status = _FleetStatus.active;
          mgr.detail = 'Updating manager…';
        });
        final mok = await ota.performWifiUpdate(mgrRelease);
        if (!mok) {
          setState(() {
            mgr.status = _FleetStatus.failed;
            mgr.detail = 'Manager update failed';
          });
          return;
        }
        setState(() {
          _mgrReconnecting = true;
          mgr.detail = 'Rebooting + reconnecting…';
        });
        await Future<void>.delayed(const Duration(seconds: 5));
        final re = await ble.connectByIdAndReady(managerId);
        setState(() => _mgrReconnecting = false);
        setState(() {
          mgr.status = re ? _FleetStatus.done : _FleetStatus.failed;
          mgr.detail = re
              ? 'Updated ${mgrRelease.tag}'
              : 'Did not reconnect — tap CONNECT';
        });
      }
    } finally {
      ota.clearOtaActive();
      if (mounted) setState(() => _fleetRunning = false);
    }
  }

  Future<void> _flashLocalBin() async {
    const typeGroup = XTypeGroup(
      label: 'firmware',
      extensions: ['bin'],
      uniformTypeIdentifiers: ['public.data'],
      mimeTypes: ['application/octet-stream'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ble = ref.read(bleManagerProvider);
    final name = file.name;
    final board = ble.board;
    final role = ble.role;
    bool mismatch = false;
    String warn = '';
    if (board.isNotEmpty && !name.toLowerCase().contains(board.toLowerCase())) {
      mismatch = true;
      warn = 'File does not include board "$board" in name. Wrong target = bricked device.';
    }
    if (role.isNotEmpty && !name.toLowerCase().contains('-$role-')) {
      mismatch = true;
      warn = warn.isEmpty
          ? 'File does not include role "$role" in name.'
          : '$warn Also role "$role" missing.';
    }
    if (mismatch) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Board mismatch'),
          content: Text('$warn\n\nProceed anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('FLASH ANYWAY', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final ota = ref.read(otaServiceProvider);
    await ota.pushLocalImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final busy = ref.read(otaServiceProvider).isRunning &&
        _progress != null &&
        _progress!.phase != OtaPhase.idle &&
        _progress!.phase != OtaPhase.upToDate &&
        _progress!.phase != OtaPhase.error &&
        _progress!.phase != OtaPhase.rebooting;

    final p = _progress;
    final bleActive = p != null &&
        (p.phase == OtaPhase.downloading ||
            p.phase == OtaPhase.uploading ||
            p.phase == OtaPhase.verifying ||
            p.phase == OtaPhase.rebooting ||
            p.phase == OtaPhase.error);
    OtaStepperModel? stepper;
    if (_wifiStatus != null) {
      stepper = OtaStepperModel.fromWifi(_wifiStatus!, _wifiBytesRead);
    } else if (bleActive) {
      stepper = OtaStepperModel.fromBleProgress(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigActionRow(
          icon: Icons.system_update,
          label: 'Check for Update',
          subtitle: 'Compare against latest GitHub release',
          onTap: busy ? null : _check,
        ),
        if (_checkStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(_checkStatus!,
                style: TextStyle(color: t.textSecondary, fontSize: 11)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(Icons.wifi_tethering,
                  size: 18,
                  color: _autoWifiUpdate ? AppTheme.accent : t.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-connect WiFi for firmware update',
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(
                      _wifiConfigured
                          ? 'Manager joins saved WiFi to download the update'
                          : 'Save WiFi credentials in the WIFI NETWORK section above to use this',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoWifiUpdate,
                onChanged: _setAutoWifi,
                activeThumbColor: AppTheme.accent,
              ),
            ],
          ),
        ),
        if (_availableRelease != null && !busy) ...[
          if (_wifiConfigured) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: ElevatedButton.icon(
                onPressed: _installWifi,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                icon: const Icon(Icons.wifi, size: 16),
                label: Text('Install via WiFi — ${_availableRelease!.tag}'),
              ),
            ),
            if (ref.read(bleManagerProvider).isManagerConnected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: ElevatedButton.icon(
                  onPressed: _fleetRunning ? null : _updateAll,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent),
                  icon: const Icon(Icons.system_update_alt, size: 16),
                  label: const Text('Update All — manager + nodes (WiFi)'),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Set WiFi credentials in the WIFI NETWORK section above to update '
                'over WiFi.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12),
              ),
            ),
        ],
        ..._buildNodeUpdateSection(t, busy),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: busy ? null : _flashLocalBin,
            icon: const Icon(Icons.upload_file, size: 16),
            label: Builder(builder: (ctx) {
              final ble = ref.read(bleManagerProvider);
              final tag = [
                if (ble.role.isNotEmpty) ble.role,
                if (ble.board.isNotEmpty) ble.board,
              ].join('-');
              return Text(tag.isEmpty
                  ? 'Flash local .bin (DFU)'
                  : 'Flash local .bin ($tag)');
            }),
          ),
        ),
        if (_fleet.isNotEmpty)
          ..._buildFleetProgress(t)
        else if (stepper != null)
          OtaProgressStepper(model: stepper),
      ],
    );
  }

  List<Widget> _buildFleetProgress(ResolvedTheme t) {
    final done = _fleet.where((f) => f.status == _FleetStatus.done).length;
    final out = <Widget>[
      const Divider(height: 20),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            Text('FLEET UPDATE',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$done / ${_fleet.length}',
                style: TextStyle(
                    color: _fleetRunning ? AppTheme.accent : AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ];
    for (final f in _fleet) {
      if (f.status == _FleetStatus.active) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Icon(f.isManager ? Icons.router : Icons.sensors,
                  size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(f.label,
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ));
        if (f.isManager) {
          out.add(OtaProgressStepper(
            model: OtaStepperModel.fromBleProgress(
              _progress ?? const OtaProgress(phase: OtaPhase.uploading),
              reconnecting: _mgrReconnecting,
            ),
          ));
        } else {
          out.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    backgroundColor: t.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f.detail,
                    style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ],
            ),
          ));
        }
      } else {
        final Color c;
        final IconData icon;
        switch (f.status) {
          case _FleetStatus.done:
            c = AppTheme.success;
            icon = Icons.check_circle;
            break;
          case _FleetStatus.failed:
            c = AppTheme.error;
            icon = Icons.error;
            break;
          case _FleetStatus.queued:
          case _FleetStatus.active:
            c = t.textDim;
            icon = Icons.radio_button_unchecked;
            break;
        }
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.label,
                    style: TextStyle(color: t.textPrimary, fontSize: 12)),
              ),
              Text(f.detail,
                  style: TextStyle(color: c, fontSize: 10)),
            ],
          ),
        ));
      }
    }
    return out;
  }
}

