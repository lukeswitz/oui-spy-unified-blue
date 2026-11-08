part of 'device_config.dart';

class _WatchItem {
  const _WatchItem(this.label, this.desc, this.icon,
      {this.bits = 0, this.classes = const {}, this.flock = false, this.drone = false, this.methods});
  final String label;
  final String desc;
  final IconData icon;
  final int bits;
  final Set<SignatureClass> classes;
  final bool flock;
  final bool drone;
  final List<String>? methods;
}

const _watchGroups = <(String, List<_WatchItem>)>[
  ('SURVEILLANCE', [
    _WatchItem('Flock', 'Flock cameras, Raven gunshot sensors, Penguin and Pigvision', Icons.camera_outdoor,
        flock: true),
    _WatchItem('Other cameras', 'Ring, Nest, Arlo, Hikvision and other security cameras, plus Amazon Sidewalk', Icons.videocam,
        bits: sigCamera, classes: {SignatureClass.surveillance, SignatureClass.camera}),
    _WatchItem('Police & public safety', 'Axon body cams and Tasers, police and fleet vehicle routers', Icons.local_police,
        bits: sigAxon, classes: {SignatureClass.lawEnforcement}),
    _WatchItem('Drones', 'Drones and drone controllers, including Remote ID', Icons.flight,
        classes: {SignatureClass.drone}, drone: true),
  ]),
  ('TRACKERS & WEARABLES', [
    _WatchItem('Trackers', 'AirTags and other tags that could be following you', Icons.track_changes,
        bits: sigTracker, classes: {SignatureClass.finder}),
    _WatchItem('Smart glasses', 'Ray-Ban and Oakley Meta camera glasses', Icons.visibility,
        bits: sigGlasses, classes: {SignatureClass.glasses}),
  ]),
  ('HACKING & ATTACKS', [
    _WatchItem('Hacking tools', 'Flipper Zero, Pwnagotchi and other pentest gear', Icons.bug_report,
        bits: sigFlipper | sigPwnagotchi, classes: {SignatureClass.hacking}),
    _WatchItem('Wi-Fi deauth attacks', 'Someone knocking devices off Wi-Fi or flooding an access point with join requests', Icons.wifi_off, bits: sigDeauth),
    _WatchItem('Wi-Fi beacon floods', 'One radio faking a crowd of Wi-Fi networks', Icons.wifi_channel, bits: sigBeaconFlood),
    _WatchItem('Probe requests', 'Phones calling out for saved Wi-Fi names. Noisy in busy areas', Icons.wifi_find,
        bits: sigProbe, methods: ['probe_ssid']),
    _WatchItem('Rogue access points', 'Evil twins (a network name from a second radio of another vendor) and KARMA APs (one radio answering as many networks). Shares the probe switch', Icons.wifi_tethering_error,
        bits: sigProbe, methods: ['evil_twin', 'karma']),
    _WatchItem('Mesh radios', 'Meshtastic and MeshCore nodes', Icons.hub, bits: sigMesh),
  ]),
];

const _moreGroups = <(String, List<SignatureClass>)>[
  ('PERSONAL', [
    SignatureClass.wearable,
    SignatureClass.health,
    SignatureClass.audio,
    SignatureClass.phone,
  ]),
  ('HOME', [
    SignatureClass.home,
    SignatureClass.thermostat,
    SignatureClass.lock,
  ]),
  ('VEHICLES & INFRASTRUCTURE', [
    SignatureClass.vehicle,
    SignatureClass.isp,
    SignatureClass.mesh,
    SignatureClass.beacon,
    SignatureClass.signage,
    SignatureClass.other,
  ]),
];

IconData _classIcon(SignatureClass c) => classIcon(c);

void _pushPage(BuildContext context, String title, Widget body) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (ctx) => Scaffold(
      backgroundColor: AppTheme.of(ctx).background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: SizedBox(width: double.infinity, child: body)),
    ),
  ));
}

class _DetectionSettingsTab extends ConsumerStatefulWidget {
  const _DetectionSettingsTab({this.footer = const []});
  final List<Widget> footer;

  @override
  ConsumerState<_DetectionSettingsTab> createState() => _DetectionSettingsTabState();
}

class _DetectionSettingsTabState extends ConsumerState<_DetectionSettingsTab> {
  Future<void> _setPhoneScan(bool on) async {
    ref.read(phoneBleSourceProvider).setActive(on);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    final sigMask = ref.watch(detectorSigMaskProvider);
    final notif = ref.watch(notificationServiceProvider);
    final ignore = ref.watch(ignoreListProvider);
    final phoneScan = ref.watch(phoneBleSourceProvider).active;
    final targets = watchlist.entries.length;
    final ignoring = ignore.entries.where((e) => e.enabled).length;
    final moreClasses = [for (final (_, cs) in _moreGroups) ...cs];
    final moreOn = moreClasses.where(notif.classAlerts.contains).length;

    bool isOn(_WatchItem w) =>
        (sigMask & w.bits) != 0 ||
        w.classes.any(notif.classAlerts.contains) ||
        (w.flock && notif.flockEnabled) ||
        (w.drone && notif.droneEnabled);

    void setOn(_WatchItem w, bool v) {
      final sig = ref.read(detectorSigMaskProvider.notifier);
      for (final b in [sigTracker, sigFlipper, sigDeauth, sigProbe, sigPwnagotchi, sigGlasses, sigAxon, sigCamera, sigMesh, sigBeaconFlood]) {
        if (w.bits & b != 0) sig.setBit(b, v);
      }
      for (final c in w.classes) {
        notif.setClassAlert(c, v);
      }
      if (w.flock) notif.setFlockEnabled(v);
      if (w.drone) notif.setDroneEnabled(v);
    }

    List<String> muteKeys(_WatchItem w) => [
          for (final c in w.classes) c.name,
          if (w.flock) 'flock',
          if (w.drone) 'drone',
          if (w.methods case final ms?)
            for (final m in ms) 'det:$m'
          else
            for (final e in detectorMethodsByBit.entries)
              if (w.bits & e.key != 0)
                for (final m in e.value) 'det:$m',
        ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text('Choose what OUI-APEX watches for.',
                    style: TextStyle(color: t.textDim, fontSize: 12, height: 1.3)),
              ),
            ),
            IconButton(
              icon: Icon(Icons.info_outline, color: t.textSecondary),
              tooltip: 'About detection & alerts',
              onPressed: () => showInfoSheet(context, t, 'Detection & alerts', const [
                'A switch turns a type on. A find gives a notification and a pin on the map.',
                'Tap the bell on a row to log that type without notifying.',
              ]),
            ),
          ],
        ),
        for (final (title, items) in _watchGroups) ...[
          ConfigSectionHeader(label: title, topPadding: 6),
          for (final w in items) ...[
            ConfigToggleRow(
              icon: w.icon,
              label: w.label,
              subtitle: w.desc,
              color: AppTheme.detector,
              value: isOn(w),
              onChanged: (v) => setOn(w, v),
              notify: !notif.isMuted(muteKeys(w)),
              onNotify: (v) => notif.setMuted(muteKeys(w), !v),
            ),
            if (w.flock && isOn(w))
              ConfigToggleRow(
                icon: Icons.fingerprint,
                label: 'OUI-only matches (phone/USB)',
                subtitle: 'Flag as Suspected. More false positives.',
                color: AppTheme.error,
                value: notif.flockOuiOnly,
                onChanged: notif.setFlockOuiOnly,
              ),
          ],
          const SizedBox(height: 12),
        ],
        _InfoHeader(
          label: 'Privacy screen',
          lines: const [
            'Shows only the first two MAC bytes and the first three characters of names and SSIDs in detection lists, detail sheets, map lists and Devices.',
            'Display only. The database, exports and uploads keep full values, and Copy copies the real value.',
          ],
        ),
        ConfigToggleRow(
          icon: Icons.visibility_off,
          label: 'Mask identifiers on screen',
          subtitle: 'Hides most of each MAC, name and SSID',
          color: AppTheme.detector,
          value: ref.watch(privacyScreenProvider),
          onChanged: (v) => ref.read(privacyScreenProvider.notifier).set(v),
        ),
        const SizedBox(height: 12),
        _InfoHeader(
          label: 'Alert threshold',
          lines: const [
            'Board signatures report how strong the evidence is.',
            'Suspected: one weak signal, such as a vendor OUI or a tracker seen for seconds.',
            'High: one specific signal. Verified: two independent signals.',
            'Hits below the threshold are still logged. Suspected hits arrive silently.',
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('All')),
              ButtonSegment(value: NotificationService.confHigh, label: Text('High+')),
              ButtonSegment(value: NotificationService.confVerified, label: Text('Verified')),
            ],
            selected: {notif.minDetectorConfidence <= NotificationService.confSuspected ? 0 : notif.minDetectorConfidence},
            showSelectedIcon: false,
            onSelectionChanged: (s) => notif.setMinDetectorConfidence(s.first),
          ),
        ),
        const SizedBox(height: 12),
        ConfigActionRow(
          icon: Icons.tune,
          label: 'More device types',
          subtitle: moreOn == 0 ? 'Phones, home gear, vehicles, routers and more' : '$moreOn on',
          color: AppTheme.detector,
          onTap: () => _pushPage(context, 'More device types', const _MoreTypesPage()),
        ),
        const SizedBox(height: 20),
        ConfigSectionHeader(label: 'Your lists'),
        ConfigActionRow(
          icon: Icons.manage_search,
          label: 'Search all captures',
          subtitle: 'Counts, GPS coverage and a search over every stored session and import, on this phone only',
          color: AppTheme.detector,
          onTap: () => context.push('/analysis'),
        ),
        ConfigActionRow(
          icon: Icons.list_alt,
          label: 'Watchlist',
          subtitle: targets == 0
              ? 'Specific devices to alert on · add or import'
              : '$targets device${targets == 1 ? '' : 's'} · add or import',
          color: AppTheme.detector,
          onTap: () => _pushPage(context, 'Watchlist', const SingleChildScrollView(child: WatchlistPanel())),
        ),
        ConfigActionRow(
          icon: Icons.shield_outlined,
          label: 'Ignore list',
          subtitle: ignoring == 0
              ? 'Devices to never log or alert on'
              : '$ignoring ignored · never logged or alerted',
          color: AppTheme.accent,
          onTap: () => _pushPage(context, 'Ignore list', const SingleChildScrollView(child: _IgnoreListTab())),
        ),
        const SizedBox(height: 20),
        ConfigSectionHeader(label: 'This phone'),
        ConfigToggleRow(
          icon: Icons.bluetooth_searching,
          label: 'Also scan with this phone',
          subtitle: "Uses this phone's Bluetooth to find nearby devices too, in addition to your OUI-SPY board",
          color: AppTheme.detector,
          value: phoneScan,
          onChanged: _setPhoneScan,
        ),
        const SizedBox(height: 20),
        ...widget.footer,
      ],
    );
  }
}

class _InfoHeader extends StatelessWidget {
  const _InfoHeader({required this.label, required this.lines});
  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      children: [
        Expanded(child: ConfigSectionHeader(label: label)),
        IconButton(
          icon: Icon(Icons.info_outline, size: 18, color: t.textSecondary),
          tooltip: 'About $label',
          visualDensity: VisualDensity.compact,
          onPressed: () => showInfoSheet(context, t, label, lines),
        ),
      ],
    );
  }
}

class _MoreTypesPage extends ConsumerWidget {
  const _MoreTypesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notif = ref.watch(notificationServiceProvider);
    final t = AppTheme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Text(
            'Everyday devices. Most people leave these off.',
            style: TextStyle(color: t.textDim, fontSize: 12),
          ),
        ),
        for (final (title, classes) in _moreGroups) ...[
          ConfigSectionHeader(label: title, topPadding: 8),
          for (final c in classes)
            ConfigToggleRow(
              icon: _classIcon(c),
              label: c.label,
              color: AppTheme.detector,
              value: notif.classAlerts.contains(c),
              onChanged: (v) => notif.setClassAlert(c, v),
              notify: !notif.mutedAlerts.contains(c.name),
              onNotify: (v) => notif.setMuted([c.name], !v),
            ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}
