import 'package:flutter/material.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

Future<void> showNodeRenameDialog(BuildContext context, AppState appState, String nodeId,
    {bool allowForget = false}) async {
  final id = AppState.canonicalNodeId(nodeId);
  if (id.isEmpty) return;
  final current = appState.nodeLabels[id] ?? '';
  final controller = TextEditingController(text: current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Rename ${appState.labelForNode(id)}'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(
          hintText: 'Custom label (blank = reset)',
          helperText: 'Node $id',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        if (allowForget && id != 'LOCAL' && id != appState.nodeId)
          TextButton(
            onPressed: () => Navigator.pop(ctx, '__forget__'),
            child: Text('FORGET', style: TextStyle(color: AppTheme.error)),
          ),
        if (appState.nodeLabels.containsKey(id))
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('CLEAR'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('SAVE'),
        ),
      ],
    ),
  );
  if (result == null) return;
  if (result == '__forget__') {
    appState.forgetNode(id);
    return;
  }
  appState.setNodeLabel(id, result.trim());
}
