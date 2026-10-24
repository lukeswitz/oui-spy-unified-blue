part of 'device_config.dart';

class _WifiStatusPanel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_WifiStatusPanel> createState() => _WifiStatusPanelState();
}

class _WifiStatusPanelState extends ConsumerState<_WifiStatusPanel> {
  bool _hasCreds = false;
  bool _connected = false;
  bool _enabled = false;
  String _ssid = '';
  String _ip = '';
  int _rssi = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() {
        _hasCreds = r.hasCreds;
        _connected = r.connected;
        _enabled = r.enabled;
        _ssid = r.ssid;
        _ip = r.ip;
        _rssi = r.rssi;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _hasCreds = false;
        _connected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final Color color;
    final IconData icon;
    final String title;
    final String? subtitle;
    bool connecting = false;
    if (_connected) {
      color = AppTheme.success;
      icon = Icons.wifi;
      title = 'Connected: $_ssid';
      subtitle = '$_ip · ${_rssi}dBm';
    } else if (_enabled && _hasCreds) {
      color = AppTheme.accent;
      icon = Icons.wifi_find;
      connecting = true;
      title = 'Connecting to $_ssid…';
      subtitle = 'Joining network — up to 20s';
    } else if (_hasCreds) {
      color = AppTheme.warning;
      icon = Icons.wifi_off;
      title = 'Saved: $_ssid (STA off)';
      subtitle = 'Enable WiFi STA below to connect';
    } else {
      color = t.textDim;
      icon = Icons.signal_wifi_off;
      title = 'No WiFi credentials saved';
      subtitle = null;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          connecting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiEnableToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_WifiEnableToggle> createState() => _WifiEnableToggleState();
}

class _WifiEnableToggleState extends ConsumerState<_WifiEnableToggle> {
  bool _enabled = false;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() => _enabled = r.enabled);
    } on Exception catch (e) {
      DebugLog.log('WiFi refresh failed: $e');
    }
  }

  Future<void> _toggle(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(bleManagerProvider).setWifiStaEnabled(v);
      if (mounted) setState(() => _enabled = v);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.power_settings_new,
              color: _enabled ? AppTheme.success : t.textDim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WiFi STA',
                    style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  _enabled
                      ? 'Connects automatically using saved credentials'
                      : 'Off — node will not join WiFi until you enable it',
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: _busy ? null : _toggle,
            activeThumbColor: AppTheme.success,
          ),
        ],
      ),
    );
  }
}




class _ConfigAuthPill extends StatelessWidget {
  const _ConfigAuthPill({required this.authMode});
  final int authMode;

  @override
  Widget build(BuildContext context) {
    final (label, color) = wifiAuthMeta(authMode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(authMode == 0 ? Icons.lock_open : Icons.lock, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(
            color: color, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }
}

class _MeshModeTile extends StatelessWidget {
  const _MeshModeTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final color = selected ? AppTheme.success : t.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.success.withValues(alpha: 0.08)
                : t.surface,
            border: Border.all(
              color: selected
                  ? AppTheme.success.withValues(alpha: 0.5)
                  : t.border,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeRenameRow extends ConsumerStatefulWidget {
  const _NodeRenameRow({
    required this.sourceId,
    required this.detectionCount,
  });
  final String sourceId;
  final int detectionCount;

  @override
  ConsumerState<_NodeRenameRow> createState() => _NodeRenameRowState();
}

class _NodeRenameRowState extends ConsumerState<_NodeRenameRow> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    _ctrl = TextEditingController(
      text: appState.labelForNode(widget.sourceId),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final appState = ref.read(appStateProvider);
    appState.setNodeLabel(widget.sourceId, _ctrl.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final appState = ref.watch(appStateProvider);
    final display = appState.labelForNode(widget.sourceId);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, size: 14, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.sourceId,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: const UnderlineInputBorder(),
                    ),
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        display,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        widget.sourceId == display
                            ? '${widget.detectionCount} dets'
                            : '${widget.sourceId}  ·  ${widget.detectionCount} dets',
                        style: TextStyle(
                          color: t.textDim,
                          fontSize: 10,
                          fontFamily: AppTheme.mono,
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(
              _editing ? Icons.check : Icons.edit,
              size: 16,
              color: _editing ? AppTheme.success : t.textDim,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              if (_editing) {
                _save();
              } else {
                setState(() => _editing = true);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  static const String appVersion = '0.7.0';

  @override
  Widget build(BuildContext context) {
    return ConfigInfoRow(
      icon: Icons.info_outline,
      label: 'Version',
      value: appVersion,
    );
  }
}
