import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

Future<void> showSuggestionsSheet(BuildContext context) =>
    showCommandSheet<void>(context: context, builder: (_) => const SuggestionsSheet());

class SuggestionsSheet extends ConsumerStatefulWidget {
  const SuggestionsSheet({super.key});

  @override
  ConsumerState<SuggestionsSheet> createState() => _SuggestionsSheetState();
}

class _SuggestionsSheetState extends ConsumerState<SuggestionsSheet> {
  late final List<Suggestion> _groups = SignatureSuggest.of(ref.read(deviceRegistryProvider).devices);

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final masked = ref.watch(privacyScreenProvider);
    final wl = ref.watch(watchlistProvider);
    final have = {for (final e in wl.entries) watchlistKey(e)};
    final macRules = wl.enabledEntries.where((e) => e.isOui || e.isFullMac).length;
    final uuidRules = wl.enabledEntries.where((e) => e.isServiceUuid).length;
    final small = (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(color: t.textDim);
    return CommandSheet(
      title: 'SUGGESTED RULES',
      trailing: IconButton(
        icon: Icon(Icons.info_outline, size: barIconSize(context), color: t.textDim),
        tooltip: 'About suggested rules',
        visualDensity: VisualDensity.compact,
        onPressed: () => showInfoSheet(context, t, 'Suggested rules', const [
          'Groups of 3 or more unclassified radios that share a name, a Bluetooth service, a vendor prefix or a Bluetooth company ID.',
          'WATCH adds a watchlist rule. The node alerts when its Detector engine hears a match.',
          "Name and company groups have no WATCH button. The node's watchlist matches only vendor prefixes, MAC addresses and services.",
          'Edit or remove rules in Settings → Detection & alerts → Watchlist.',
        ]),
      ),
      child: _groups.isEmpty
          ? Text(
              'No group of 3 or more unclassified radios shares a name, service, vendor prefix or company yet.',
              style: small,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (macRules > 50 || uuidRules > 50)
                  Padding(
                    padding: EdgeInsets.only(bottom: barGap(context)),
                    child: Text(
                      'The node keeps 50 vendor prefix or MAC rules and 50 service rules. It ignores the rest.',
                      style: small.copyWith(color: AppTheme.warning),
                    ),
                  ),
                for (final g in _groups)
                  _GroupTile(
                    group: g,
                    masked: masked,
                    onWatchlist: g.rule != null && have.contains(watchlistKey(g.rule!)),
                    onWatch: () => ref.read(watchlistProvider).add(g.rule!),
                  ),
              ],
            ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.masked, required this.onWatchlist, required this.onWatch});

  final Suggestion group;
  final bool masked;
  final bool onWatchlist;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    final small = (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(color: t.textDim);
    final names = {for (final d in group.devices) if (d.obs.name.trim().isNotEmpty) maskName(d.obs.name.trim(), masked)};
    final examples = (names.isNotEmpty
            ? names
            : {for (final d in group.devices) if (d.obs.mac.isNotEmpty) maskMac(d.obs.mac, masked)})
        .take(3)
        .join(', ');
    return Padding(
      padding: EdgeInsets.only(bottom: gap * 1.5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${group.devices.length} radios · ${group.label(masked: masked)}',
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
                ),
                if (examples.isNotEmpty) Text('e.g. $examples', style: small),
                if (group.also.isNotEmpty)
                  Text('Also share: ${group.also.map((a) => a.label(masked: masked)).join(' · ')}', style: small),
              ],
            ),
          ),
          if (group.rule != null)
            onWatchlist
                ? Text('ON WATCHLIST', style: barLabelStyle(context, t.textDim))
                : TextButton(onPressed: onWatch, child: const Text('WATCH')),
        ],
      ),
    );
  }
}
