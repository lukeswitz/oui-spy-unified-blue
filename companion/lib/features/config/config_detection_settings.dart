part of 'device_config.dart';

class _WatchItem {
  const _WatchItem(this.label, this.desc, this.icon,
      {this.bits = 0, this.classes = const {}, this.flock = false, this.drone = false});
  final String label;
  final String desc;
  final IconData icon;
  final int bits;
  final Set<SignatureClass> classes;
  final bool flock;
  final bool drone;
}

const _watchGroups = <(String, List<_WatchItem>)>[
  ('SURVEILLANCE', [
    _WatchItem('Surveillance cameras', 'Flock, Arlo and other camera networks', Icons.videocam,
        classes: {SignatureClass.surveillance, SignatureClass.camera}, flock: true),
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
    _WatchItem('Wi-Fi deauth attacks', 'Someone knocking devices off Wi-Fi', Icons.wifi_off, bits: sigDeauth),
    _WatchItem('Probe requests', 'Phones calling out for saved Wi-Fi names. Noisy in busy areas', Icons.wifi_find,
        bits: sigProbe),
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

IconData _classIcon(SignatureClass c) => switch (c) {
      SignatureClass.finder => Icons.track_changes,
      SignatureClass.beacon => Icons.cell_tower,
      SignatureClass.signage => Icons.tv,
      SignatureClass.wearable || SignatureClass.bodyworn => Icons.watch,
      SignatureClass.surveillance => Icons.videocam,
      SignatureClass.drone => Icons.flight,
      SignatureClass.hacking => Icons.bug_report,
      SignatureClass.lawEnforcement => Icons.local_police,
      SignatureClass.vehicle => Icons.directions_car,
      SignatureClass.glasses => Icons.visibility,
      SignatureClass.audio => Icons.headphones,
      SignatureClass.camera => Icons.photo_camera,
      SignatureClass.thermostat => Icons.thermostat,
      SignatureClass.lock => Icons.lock,
      SignatureClass.health => Icons.favorite,
      SignatureClass.home => Icons.home,
      SignatureClass.isp => Icons.router,
      SignatureClass.mesh => Icons.hub,
      SignatureClass.phone => Icons.smartphone,
      SignatureClass.other => Icons.devices_other,
    };

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
    final p = await SharedPreferences.getInstance();
    await p.setBool(DeviceRegistry.phoneScanPref, on);
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
        (w.bits == 0 || (sigMask & w.bits) == w.bits) &&
        w.classes.every(notif.classAlerts.contains) &&
        (!w.flock || notif.flockEnabled) &&
        (!w.drone || notif.droneEnabled);

    void setOn(_WatchItem w, bool v) {
      final sig = ref.read(detectorSigMaskProvider.notifier);
      for (final b in [sigTracker, sigFlipper, sigDeauth, sigProbe, sigPwnagotchi, sigGlasses, sigAxon]) {
        if (w.bits & b != 0) sig.setBit(b, v);
      }
      for (final c in w.classes) {
        notif.setClassAlert(c, v);
      }
      if (w.flock) notif.setFlockEnabled(v);
      if (w.drone) notif.setDroneEnabled(v);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 2, right: 2),
          child: Text(
            'Choose what OUI-SPY watches for. When it finds one you get a notification and a pin on the map.',
            style: TextStyle(color: t.textDim, fontSize: 12, height: 1.3),
          ),
        ),
        for (final (title, items) in _watchGroups) ...[
          ConfigSectionHeader(label: title, topPadding: 6),
          for (final w in items)
            ConfigToggleRow(
              icon: w.icon,
              label: w.label,
              subtitle: w.desc,
              color: AppTheme.detector,
              value: isOn(w),
              onChanged: (v) => setOn(w, v),
            ),
          const SizedBox(height: 12),
        ],
        ConfigActionRow(
          icon: Icons.tune,
          label: 'More device types',
          subtitle: moreOn == 0 ? 'Phones, home gear, vehicles, routers and more' : '$moreOn on',
          color: AppTheme.detector,
          onTap: () => _pushPage(context, 'More device types', const _MoreTypesPage()),
        ),
        const SizedBox(height: 20),
        const ConfigSectionHeader(label: 'YOUR LISTS'),
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
        const ConfigSectionHeader(label: 'THIS PHONE'),
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
            ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}
