// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:oui_spy/core/detector_rules.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Asks for one rule a node can match and returns it; null when canceled. Phone-only kinds are not offered.
Future<WatchlistEntry?> showRulePicker(BuildContext context, {String title = 'Add a rule'}) =>
    showDialog<WatchlistEntry>(context: context, builder: (_) => _RulePicker(title: title));

class _RulePicker extends StatefulWidget {
  const _RulePicker({required this.title});
  final String title;

  @override
  State<_RulePicker> createState() => _RulePickerState();
}

class _RulePickerState extends State<_RulePicker> {
  final idController = TextEditingController();
  var type = WatchlistMatchType.oui;
  String? error;

  @override
  void dispose() {
    idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      scrollable: true,
      title: Text(widget.title, style: TextStyle(color: t.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<WatchlistMatchType>(
            initialValue: type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Match'),
            items: [
              for (final m in WatchlistMatchType.values)
                if (m.isNodeRule) DropdownMenuItem(value: m, child: Text(m.title)),
            ],
            onChanged: (m) => setState(() {
              type = m ?? type;
              error = null;
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: idController,
            style: TextStyle(color: t.textPrimary, fontFamily: AppTheme.mono),
            decoration: InputDecoration(
              hintText: ruleHint(type),
              labelText: ruleLabel(type),
              helperText: ruleHelp(type),
              helperMaxLines: 3,
              errorText: error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(
          onPressed: () {
            final id = normalizeWatchlistId(idController.text, type);
            if (id == null) {
              setState(() => error = 'Not a valid ${type.title.toLowerCase()}');
              return;
            }
            Navigator.pop(context, WatchlistEntry(identifier: id, matchType: type));
          },
          child: const Text('ADD'),
        ),
      ],
    );
  }
}
