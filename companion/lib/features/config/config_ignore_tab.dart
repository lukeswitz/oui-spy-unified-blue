part of 'device_config.dart';

class _IgnoreListTab extends ConsumerWidget {
  const _IgnoreListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final allowlist = ref.watch(ignoreListProvider);
    final entries = allowlist.entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header + add button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'IGNORE LIST',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: t.textDim,
                    ),
              ),
              const Spacer(),
              Text(
                '${entries.where((e) => e.enabled).length} active',
                style: TextStyle(
                  color: t.textDim, fontSize: 10,
                  fontFamily: AppTheme.mono,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showAddDialog(context, ref),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.add, size: 18, color: AppTheme.accent),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            'Matching devices are silently excluded from the feed, '
            'CSV exports, database logging, and alerts.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const Divider(height: 1),
        // Entry list
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 36, color: t.textDim),
                      const SizedBox(height: 12),
                      Text('NO ENTRIES', style: TextStyle(
                        color: t.textDim, fontSize: 12,
                        fontWeight: FontWeight.w700, letterSpacing: 2,
                      )),
                      const SizedBox(height: 6),
                      Text(
                        'Tap + to add SSIDs, MACs, or OUIs\nthat should never be logged.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textDim, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _IgnoreEntryTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final valueController = TextEditingController();
    final labelController = TextEditingController();
    IgnoreType selectedType = IgnoreType.ssid;
    IgnoreScope selectedScope = IgnoreScope.both;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hintText = switch (selectedType) {
            IgnoreType.ssid => 'MyHomeNetwork',
            IgnoreType.mac => 'AA:BB:CC:DD:EE:FF',
            IgnoreType.oui => 'AA:BB:CC',
          };

          return AlertDialog(
            backgroundColor: t.surface,
            title: Text('Add to Ignore List', style: TextStyle(color: t.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selector
                  Text('MATCH TYPE', style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 6),
                  Row(
                    children: IgnoreType.values.map((type) {
                      final isSelected = selectedType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedType = type),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: type != IgnoreType.oui ? 6 : 0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : t.border,
                              ),
                            ),
                            child: Center(
                              child: Text(type.label, style: TextStyle(
                                color: isSelected ? AppTheme.accent : t.textSecondary,
                                fontSize: 11, fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              )),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Value field
                  TextField(
                    controller: valueController,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontFamily: selectedType == IgnoreType.ssid
                          ? null
                          : AppTheme.mono,
                      fontSize: 14,
                    ),
                    textCapitalization: selectedType == IgnoreType.ssid
                        ? TextCapitalization.none
                        : TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: hintText,
                      labelText: selectedType.label,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Label field
                  TextField(
                    controller: labelController,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Home Router',
                      labelText: 'Label (optional)',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Scope selector
                  Text('APPLIES TO', style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 6),
                  Row(
                    children: IgnoreScope.values.map((scope) {
                      final isSelected = selectedScope == scope;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedScope = scope),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: scope != IgnoreScope.ble ? 6 : 0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : t.border,
                              ),
                            ),
                            child: Center(
                              child: Text(scope.label, style: TextStyle(
                                color: isSelected ? AppTheme.accent : t.textSecondary,
                                fontSize: 10, fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  final raw = valueController.text.trim();
                  if (raw.isEmpty) return;
                  final normalized = IgnoreEntry.normalize(selectedType, raw);
                  ref.read(ignoreListProvider).add(IgnoreEntry(
                    type: selectedType,
                    value: normalized,
                    scope: selectedScope,
                    label: labelController.text.trim(),
                  ));
                  Navigator.pop(ctx);
                },
                child: const Text('ADD'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IgnoreEntryTile extends ConsumerWidget {
  const _IgnoreEntryTile({required this.entry});
  final IgnoreEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final isEnabled = entry.enabled;

    final IconData typeIcon = switch (entry.type) {
      IgnoreType.ssid => Icons.wifi,
      IgnoreType.mac => Icons.fingerprint,
      IgnoreType.oui => Icons.radar,
    };

    final Color scopeColor = switch (entry.scope) {
      IgnoreScope.wifi => AppTheme.wardrive,
      IgnoreScope.ble => AppTheme.detector,
      IgnoreScope.both => AppTheme.accent,
    };

    return Dismissible(
      key: ValueKey('${entry.type.name}:${entry.value}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.15),
        ),
        child: Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
      ),
      onDismissed: (_) => ref.read(ignoreListProvider).remove(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(
            color: isEnabled ? t.border : t.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: (isEnabled ? AppTheme.accent : t.textDim).withValues(alpha: 0.1),
              ),
              child: Icon(
                typeIcon,
                size: 16,
                color: isEnabled ? AppTheme.accent : t.textDim,
              ),
            ),
            const SizedBox(width: 10),
            // Value + label + scope
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.type == IgnoreType.ssid
                        ? entry.value
                        : entry.value.toUpperCase(),
                    style: TextStyle(
                      color: isEnabled ? t.textPrimary : t.textDim,
                      fontSize: 13,
                      fontFamily: entry.type == IgnoreType.ssid
                          ? null
                          : AppTheme.mono,
                      fontWeight: FontWeight.w600,
                      letterSpacing: entry.type == IgnoreType.ssid
                          ? 0
                          : 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isEnabled ? AppTheme.accent : t.textDim)
                              .withValues(alpha: 0.1),
                        ),
                        child: Text(
                          entry.type.label,
                          style: TextStyle(
                            color: isEnabled ? AppTheme.accent : t.textDim,
                            fontSize: 8, fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Scope badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isEnabled ? scopeColor : t.textDim)
                              .withValues(alpha: 0.1),
                        ),
                        child: Text(
                          entry.scope.label,
                          style: TextStyle(
                            color: isEnabled ? scopeColor : t.textDim,
                            fontSize: 8, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (entry.label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.label,
                            style: TextStyle(color: t.textDim, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Toggle switch
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: isEnabled,
                onChanged: (v) =>
                    ref.read(ignoreListProvider).toggleEnabled(entry, enabled: v),
                activeTrackColor: AppTheme.accent.withValues(alpha: 0.3),
                activeThumbColor: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


