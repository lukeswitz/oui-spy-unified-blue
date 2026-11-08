import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/trusted_networks.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

Future<void> trustNetwork(WidgetRef ref, String ssid) async {
  final oui = ref.read(ouiLookupProvider);
  String vendor(String mac) {
    final own = oui.lookup(mac);
    if (own != null) return own;
    final u = MacUtil.wifiOui24Universal(mac);
    return u == null ? '' : oui.lookup(u + hexOnly(mac).substring(6)) ?? '';
  }

  final seed = await ref.read(databaseProvider).trustedSeed(ssid);
  await ref.read(trustedNetworksProvider).trust(
        ssid,
        [
          for (final s in seed)
            TrustedSighting(MacUtil.normalize(s.mac), vendor(s.mac), s.auth < 0 ? null : s.auth, s.lat, s.lon),
        ],
        DateTime.now().millisecondsSinceEpoch,
      );
}

class TrustedNetworksScreen extends ConsumerWidget {
  const TrustedNetworksScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final reg = ref.read(deviceRegistryProvider);
    final trusted = ref.read(trustedNetworksProvider);
    final nearby = {
      for (final d in reg.devices.toList()..sort((a, b) => b.obs.rssi.compareTo(a.obs.rssi)))
        if (d.obs.isAp && d.obs.name.trim().isNotEmpty && !trusted.isTrusted(d.obs.name)) d.obs.name,
    }.take(8).toList();
    final ctrl = TextEditingController();
    final ssid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trust a network'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: nearby.isEmpty,
              decoration: const InputDecoration(labelText: 'Network name (SSID)'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            if (nearby.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Nearby'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final n in nearby) ActionChip(label: Text(n), onPressed: () => Navigator.pop(ctx, n))],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('TRUST')),
        ],
      ),
    );
    ctrl.dispose();
    if (ssid == null || ssid.isEmpty) return;
    await trustNetwork(ref, ssid);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final nets = ref.watch(trustedNetworksProvider).networks;
    final masked = ref.watch(privacyScreenProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Trusted networks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About trusted networks',
            onPressed: () => showInfoSheet(context, t, 'Trusted networks', const [
              'Add the Wi-Fi names you use. For the first day OUI-APEX learns their access points, makers, security and places.',
              'After that it warns when the name shows up with weaker security, from another maker, or far from where you use it.',
              'The phone never joins the network or asks for its password.',
              'A warning is not proof. Check the network yourself.',
            ]),
          ),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Trust a network', onPressed: () => _add(context, ref)),
        ],
      ),
      body: SafeArea(
        child: nets.isEmpty
            ? CommandEmptyState(
                icon: Icons.verified_user_outlined,
                title: 'No trusted networks',
                message: 'Add your home or work Wi-Fi to get a warning when a lookalike shows up.',
                action: ElevatedButton(onPressed: () => _add(context, ref), child: const Text('TRUST A NETWORK')),
              )
            : ListView.separated(
                itemCount: nets.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = nets[i];
                  final left = ((TrustedNetworks.learnMs - (now - n.addedMs)) / 3600000).ceil();
                  return ListTile(
                    leading: Icon(Icons.wifi_lock, color: t.textSecondary),
                    title: Text(maskName(n.ssid, masked)),
                    subtitle: Text(
                      '${n.aps.length} access point${n.aps.length == 1 ? '' : 's'} · '
                      '${n.learning(now) ? 'learning, $left h left' : 'watching'}',
                      style: TextStyle(color: t.textDim, fontSize: 12),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'relearn'
                          ? trustNetwork(ref, n.ssid)
                          : ref.read(trustedNetworksProvider).forget(n.ssid),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'relearn', child: Text('Learn again')),
                        PopupMenuItem(value: 'forget', child: Text('Remove')),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
