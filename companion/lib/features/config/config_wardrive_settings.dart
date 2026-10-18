part of 'device_config.dart';

class _ScanTimingSliders extends ConsumerWidget {
  const _ScanTimingSliders();

  static const _steps = [50, 100, 110, 150, 200, 250, 300, 350, 400, 500, 800, 1000, 1500, 2000, 3000, 5000];

  int _prevStep(int current) {
    for (int i = _steps.length - 1; i >= 0; i--) {
      if (_steps[i] < current) return _steps[i];
    }
    return _steps.first;
  }

  int _nextStep(int current) {
    for (final s in _steps) {
      if (s > current) return s;
    }
    return _steps.last;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);

    return Column(
      children: [
        _TimingRow(
          icon: Icons.wifi, label: 'Ch 1/6/11 dwell',
          value: wd.wifiScanInterval,
          onDown: () => ref.read(wardriveProvider).wifiScanInterval = _prevStep(wd.wifiScanInterval),
          onUp: () => ref.read(wardriveProvider).wifiScanInterval = _nextStep(wd.wifiScanInterval),
        ),
        _TimingRow(
          icon: Icons.wifi, label: 'Other ch dwell',
          value: wd.wifiDwellPerCh,
          onDown: () => ref.read(wardriveProvider).wifiDwellPerCh = _prevStep(wd.wifiDwellPerCh),
          onUp: () => ref.read(wardriveProvider).wifiDwellPerCh = _nextStep(wd.wifiDwellPerCh),
        ),
        _TimingRow(
          icon: Icons.bluetooth, label: 'BLE duration',
          value: wd.bleScanDuration,
          onDown: () => ref.read(wardriveProvider).bleScanDuration = _prevStep(wd.bleScanDuration),
          onUp: () => ref.read(wardriveProvider).bleScanDuration = _nextStep(wd.bleScanDuration),
        ),
        _TimingRow(
          icon: Icons.bluetooth, label: 'BLE interval',
          value: wd.bleScanInterval,
          onDown: () => ref.read(wardriveProvider).bleScanInterval = _prevStep(wd.bleScanInterval),
          onUp: () => ref.read(wardriveProvider).bleScanInterval = _nextStep(wd.bleScanInterval),
        ),
      ],
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
    this.suffix = 'ms',
  });
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(
              color: t.textSecondary, fontSize: 12,
            )),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDown,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.remove, size: 16, color: AppTheme.accent),
            ),
          ),
          Container(
            width: 64,
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: TextStyle(
                color: AppTheme.accent, fontSize: 12,
                fontFamily: 'monospace', fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUp,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.add, size: 16, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRangeSlider extends ConsumerWidget {
  const _ChannelRangeSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);

    return Column(
      children: [
        _TimingRow(
          icon: Icons.cell_tower,
          label: 'Start CH',
          value: wd.channelStart,
          suffix: '',
          onDown: () => ref.read(wardriveProvider).channelStart = wd.channelStart - 1,
          onUp: () => ref.read(wardriveProvider).channelStart = wd.channelStart + 1,
        ),
        _TimingRow(
          icon: Icons.cell_tower,
          label: 'End CH',
          value: wd.channelEnd,
          suffix: '',
          onDown: () => ref.read(wardriveProvider).channelEnd = wd.channelEnd - 1,
          onUp: () => ref.read(wardriveProvider).channelEnd = wd.channelEnd + 1,
        ),
        if (ref.watch(bleManagerProvider).isC5)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(Icons.cell_tower, size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text('2.4 GHz scan')),
                ToggleButtons(
                  borderRadius: BorderRadius.circular(6),
                  constraints:
                      const BoxConstraints(minHeight: 32, minWidth: 60),
                  isSelected: [wd.wardrive24Mode == 0, wd.wardrive24Mode == 1],
                  onPressed: (i) =>
                      ref.read(wardriveProvider).wardrive24Mode = i,
                  children: const [Text('All'), Text('1·6·11')],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WifiBandSelector extends ConsumerWidget {
  const _WifiBandSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<WifiBand>(
        segments: const [
          ButtonSegment(value: WifiBand.band24, label: Text('2.4 GHz')),
          ButtonSegment(value: WifiBand.band5, label: Text('5 GHz')),
          ButtonSegment(value: WifiBand.both, label: Text('Both')),
        ],
        selected: {wd.wifiBand},
        showSelectedIcon: false,
        onSelectionChanged: (s) =>
            ref.read(wardriveProvider).wifiBand = s.first,
      ),
    );
  }
}

class _AutoConnectToggle extends ConsumerStatefulWidget {
  const _AutoConnectToggle();

  @override
  ConsumerState<_AutoConnectToggle> createState() => _AutoConnectToggleState();
}

class _AutoConnectToggleState extends ConsumerState<_AutoConnectToggle> {
  late bool _value =
      ref.read(sharedPreferencesProvider).getBool('autoConnectEnabled') ?? false;

  Future<void> _set(bool v) async {
    setState(() => _value = v);
    await ref.read(sharedPreferencesProvider).setBool('autoConnectEnabled', v);
  }

  @override
  Widget build(BuildContext context) {
    return ConfigToggleRow(
      icon: _value ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
      label: 'Auto-connect on launch',
      subtitle: _value
          ? 'Reconnects to the last OUI-SPY device at startup'
          : 'Connect manually from the home screen',
      color: AppTheme.accent,
      value: _value,
      onChanged: _set,
    );
  }
}

class _WardriveRssiRow extends ConsumerWidget {
  const _WardriveRssiRow({required this.isBle});
  final bool isBle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    final value = isBle ? wd.bleRssiRelogDb : wd.wifiRssiRelogDb;
    final min = isBle ? 10 : 10;
    final max = isBle ? 50 : 60;

    return _TimingRow(
      icon: isBle ? Icons.bluetooth : Icons.wifi,
      label: isBle ? 'BLE re-log' : 'WiFi re-log',
      value: value,
      suffix: 'dB',
      onDown: () {
        final next = (value - 5).clamp(min, max);
        if (isBle) {
          ref.read(wardriveProvider).bleRssiRelogDb = next;
        } else {
          ref.read(wardriveProvider).wifiRssiRelogDb = next;
        }
      },
      onUp: () {
        final next = (value + 5).clamp(min, max);
        if (isBle) {
          ref.read(wardriveProvider).bleRssiRelogDb = next;
        } else {
          ref.read(wardriveProvider).wifiRssiRelogDb = next;
        }
      },
    );
  }
}

class _WigleSection extends ConsumerStatefulWidget {
  const _WigleSection();

  @override
  ConsumerState<_WigleSection> createState() => _WigleSectionState();
}

class _WigleSectionState extends ConsumerState<_WigleSection> {
  final _nameController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final wigle = ref.watch(wigleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.language, size: 16, color: AppTheme.warning),
            const SizedBox(width: 6),
            Text(
              'WIGLE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: t.textDim,
                  ),
            ),
            const Spacer(),
            if (wigle.isLoggedIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 10, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('LINKED', style: TextStyle(
                      color: AppTheme.success, fontSize: 8,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5,
                    )),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (wigle.isLoggedIn) ...[
          _WigleStatsCard(stats: wigle.stats),
          if (wigle.rateLimited) ...[
            const SizedBox(height: 8),
            Text(WigleApi.rateLimitMessage,
                style: TextStyle(color: AppTheme.error, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(wigleProvider).refreshStats(),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('REFRESH', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout, size: 14),
                  label: const Text('UNLINK', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.key, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Text('API Credentials', style: TextStyle(
                      color: t.textPrimary, fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Get your API Name and Token from wigle.net/account',
                  style: TextStyle(color: t.textDim, fontSize: 10),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API Name',
                    labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                    prefixIcon: Icon(Icons.person_outline, size: 16, color: t.textDim),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API Token',
                    labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 16, color: t.textDim),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility,
                        size: 16, color: t.textDim,
                      ),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _testing || wigle.isLoading ? null : _testAndLogin,
                    icon: _testing || wigle.isLoading
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.rocket_launch, size: 16),
                    label: Text(
                      _testing || wigle.isLoading ? 'TESTING...' : 'TEST & LINK',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                if (wigle.error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 14, color: AppTheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            wigle.error!,
                            style: TextStyle(color: AppTheme.error, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _testAndLogin() async {
    final name = _nameController.text.trim();
    final token = _tokenController.text.trim();
    if (name.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both API Name and Token')),
      );
      return;
    }

    setState(() => _testing = true);
    final success = await ref.read(wigleProvider).login(name, token);
    if (mounted) {
      setState(() => _testing = false);
      if (success) {
        final stats = ref.read(wigleProvider).stats;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.success,
            content: Text('Linked as ${stats?.userName ?? name} (rank #${stats?.rank ?? '?'})'),
          ),
        );
      }
    }
  }

  void _confirmLogout(BuildContext context) {
    final t = AppTheme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Unlink WiGLE?', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'This removes stored credentials. You can re-link anytime.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(wigleProvider).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('UNLINK'),
          ),
        ],
      ),
    );
  }
}

class _WigleStatsCard extends StatelessWidget {
  const _WigleStatsCard({this.stats});
  final WigleUserStats? stats;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final s = stats;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accent)),
            const SizedBox(width: 8),
            Text('Loading stats...', style: TextStyle(color: t.textDim, fontSize: 11)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, size: 20, color: AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.userName,
                  style: TextStyle(
                    color: t.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events, size: 12, color: AppTheme.accent),
                    const SizedBox(width: 4),
                    Text('#${s.rank}', style: TextStyle(
                      color: AppTheme.accent, fontSize: 12,
                      fontWeight: FontWeight.w700, fontFamily: 'monospace',
                    )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WigleStat(
                icon: Icons.wifi, label: 'WiFi',
                value: _formatCount(s.discoveredWiFi),
                color: AppTheme.accent,
              ),
              _WigleStat(
                icon: Icons.bluetooth, label: 'BT',
                value: _formatCount(s.discoveredBt),
                color: AppTheme.themed(const Color(0xFF4A9EFF)),
              ),
              _WigleStat(
                icon: Icons.cell_tower, label: 'Cell',
                value: _formatCount(s.discoveredCell),
                color: AppTheme.success,
              ),
              _WigleStat(
                icon: Icons.trending_up, label: 'Month',
                value: '#${s.monthRank}',
                color: AppTheme.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _WigleStat extends StatelessWidget {
  const _WigleStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
            color: t.textPrimary, fontSize: 11,
            fontWeight: FontWeight.w700, fontFamily: 'monospace',
          )),
          Text(label, style: TextStyle(
            color: t.textDim, fontSize: 8,
            fontWeight: FontWeight.w600, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }
}

class _WdgwarsSection extends ConsumerStatefulWidget {
  const _WdgwarsSection();

  @override
  ConsumerState<_WdgwarsSection> createState() => _WdgwarsSectionState();
}

class _WdgwarsSectionState extends ConsumerState<_WdgwarsSection> {
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _testing = false;
  int? _flockCams;

  @override
  void initState() {
    super.initState();
    _loadFlockCams();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadFlockCams() async {
    final n = await ref.read(databaseProvider).flockMacCountAll();
    if (mounted) setState(() => _flockCams = n);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final w = ref.watch(wdgwarsProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.wdgwars.withValues(alpha: 0.07),
            AppTheme.wdgwarsAlt.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.wdgwars.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_esports, size: 16, color: AppTheme.wdgwars),
              const SizedBox(width: 6),
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [AppTheme.wdgwars, AppTheme.wdgwarsAlt],
                ).createShader(r),
                child: const Text(
                  'WDGWARS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const Spacer(),
              if (w.isLoggedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.wdgwars.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.wdgwars.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 10, color: AppTheme.wdgwars),
                      SizedBox(width: 4),
                      Text('LINKED', style: TextStyle(
                        color: AppTheme.wdgwars, fontSize: 8,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5,
                      )),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (w.isLoggedIn) ...[
            _WdgwarsStatsCard(stats: w.stats, flockCams: _flockCams),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(wdgwarsProvider).refreshStats();
                      _loadFlockCams();
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('REFRESH', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.wdgwarsAlt,
                      side: BorderSide(color: AppTheme.wdgwarsAlt.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogout(context),
                    icon: const Icon(Icons.logout, size: 14),
                    label: const Text('UNLINK', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.key, size: 14, color: AppTheme.wdgwars),
                const SizedBox(width: 6),
                Text('API Key', style: TextStyle(
                  color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w600,
                )),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Register at wdgwars.pl and generate a 64-char API key in your profile.',
              style: TextStyle(color: t.textDim, fontSize: 10),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              obscureText: _obscureKey,
              style: TextStyle(color: t.textPrimary, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'X-API-Key',
                labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 16, color: AppTheme.wdgwars),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                    size: 16, color: t.textDim,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppTheme.wdgwars),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testing || w.isLoading ? null : _testAndLogin,
                icon: _testing || w.isLoading
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch, size: 16),
                label: Text(
                  _testing || w.isLoading ? 'TESTING...' : 'TEST & LINK',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.wdgwars,
                  foregroundColor: const Color(0xFF0D1117),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            if (w.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 14, color: AppTheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w.error!,
                        style: TextStyle(color: AppTheme.error, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _testAndLogin() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your WDGWars API key')),
      );
      return;
    }
    setState(() => _testing = true);
    final success = await ref.read(wdgwarsProvider).login(key);
    if (mounted) {
      setState(() => _testing = false);
      if (success) {
        final stats = ref.read(wdgwarsProvider).stats;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.wdgwars,
            content: Text('Linked as ${stats?.username ?? 'player'} '
                '(${stats?.total ?? 0} devices)',
                style: const TextStyle(color: Color(0xFF0D1117))),
          ),
        );
      }
    }
  }

  void _confirmLogout(BuildContext context) {
    final t = AppTheme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Unlink WDGWars?', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'This removes stored credentials. You can re-link anytime.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(wdgwarsProvider).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('UNLINK'),
          ),
        ],
      ),
    );
  }
}

class _WdgwarsStatsCard extends StatelessWidget {
  const _WdgwarsStatsCard({this.stats, this.flockCams});
  final WdgwarsUserStats? stats;
  final int? flockCams;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final s = stats;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.background.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.wdgwars.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.wdgwars)),
            const SizedBox(width: 8),
            Text('Loading stats...', style: TextStyle(color: t.textDim, fontSize: 11)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.wdgwars.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, size: 20, color: AppTheme.wdgwars),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.username,
                  style: TextStyle(
                    color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (s.rank != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.wdgwars.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.wdgwars.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events, size: 12, color: AppTheme.wdgwars),
                      const SizedBox(width: 4),
                      Text('#${s.rank}', style: TextStyle(
                        color: AppTheme.wdgwars, fontSize: 12,
                        fontWeight: FontWeight.w700, fontFamily: 'monospace',
                      )),
                    ],
                  ),
                ),
                if (s.gang.isNotEmpty) const SizedBox(width: 6),
              ],
              if (s.gang.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.wdgwarsAlt.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.wdgwarsAlt.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups, size: 12, color: AppTheme.wdgwarsAlt),
                      const SizedBox(width: 4),
                      Text(
                        s.gangRole.isEmpty
                            ? s.gang
                            : '${s.gang} · ${s.gangRole.toUpperCase()}',
                        style: TextStyle(
                          color: AppTheme.wdgwarsAlt,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WigleStat(
                icon: Icons.wifi, label: 'WiFi',
                value: _fmt(s.wifi), color: AppTheme.wdgwars,
              ),
              _WigleStat(
                icon: Icons.bluetooth, label: 'BLE',
                value: _fmt(s.ble), color: AppTheme.wdgwarsAlt,
              ),
              _WigleStat(
                icon: Icons.flight, label: 'Air',
                value: _fmt(s.aircraft), color: AppTheme.themed(const Color(0xFFc4b5fd)),
              ),
              _WigleStat(
                icon: Icons.hub, label: 'Mesh',
                value: _fmt(s.mesh), color: AppTheme.success,
              ),
              _WigleStat(
                icon: Icons.military_tech, label: 'Badges',
                value: '${s.badges.length}', color: AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _WigleStat(
                icon: Icons.today, label: 'Today',
                value: _fmt(s.recentToday), color: AppTheme.wdgwarsAlt,
              ),
              _WigleStat(
                icon: Icons.date_range, label: '7 Days',
                value: _fmt(s.recent7d), color: AppTheme.wdgwars,
              ),
              _WigleStat(
                icon: Icons.shield, label: 'Reinforced',
                value: _fmt(s.reinforced), color: AppTheme.themed(const Color(0xFFc4b5fd)),
              ),
              _WigleStat(
                icon: Icons.toll, label: 'Credits',
                value: _fmt(s.credits), color: AppTheme.warning,
              ),
              _WigleStat(
                icon: Icons.lock_open, label: 'Cracked',
                value: _fmt(s.cracked), color: AppTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.wdgwars.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(_fmt(s.total), style: TextStyle(
                        color: AppTheme.wdgwars, fontSize: 18,
                        fontWeight: FontWeight.w700, fontFamily: 'monospace',
                      )),
                      Text('TOTAL DEVICES', style: TextStyle(
                        color: t.textDim, fontSize: 8,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                      )),
                    ],
                  ),
                ),
              ),
              if (flockCams != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.flockWifi.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(_fmt(flockCams!), style: TextStyle(
                          color: AppTheme.flockWifi, fontSize: 18,
                          fontWeight: FontWeight.w700, fontFamily: 'monospace',
                        )),
                        Text('FLOCK CAMS (LOCAL)', style: TextStyle(
                          color: t.textDim, fontSize: 8,
                          fontWeight: FontWeight.w600, letterSpacing: 1,
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (s.dailyCap > 0) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final used = (s.dailyUsed / s.dailyCap).clamp(0.0, 1.0);
              final low = s.dailyRemaining < s.dailyCap * 0.1;
              final barColor = low ? AppTheme.warning : AppTheme.wdgwars;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, size: 11, color: barColor),
                      const SizedBox(width: 4),
                      Text('DAILY NEW-AP QUOTA', style: TextStyle(
                        color: t.textDim, fontSize: 8,
                        fontWeight: FontWeight.w600, letterSpacing: 1,
                      )),
                      const Spacer(),
                      Text('${_fmt(s.dailyRemaining)} / ${_fmt(s.dailyCap)} left',
                          style: TextStyle(
                            color: barColor, fontSize: 9,
                            fontWeight: FontWeight.w700, fontFamily: 'monospace',
                          )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: used,
                      minHeight: 4,
                      backgroundColor: t.border,
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                ],
              );
            }),
          ],
          Builder(builder: (_) {
            final meta = <String>[
              if (s.country.isNotEmpty) s.country,
              if (s.joined.isNotEmpty) 'joined ${s.joined}',
              if (s.notes > 0) '${s.notes} notes',
              if (s.bountiesCompleted > 0) '${s.bountiesCompleted} bounties',
              if (s.creditsLifetime > 0) '${_fmt(s.creditsLifetime)} earned',
            ];
            if (meta.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                meta.join('  ·  '),
                style: TextStyle(color: t.textDim, fontSize: 9, letterSpacing: 0.5),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmt(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

