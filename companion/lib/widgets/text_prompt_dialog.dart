// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// One-field AlertDialog that owns its controller, so it is disposed only after the route is gone.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.initial = '',
    this.message,
    this.labelText,
    this.hintText,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.isValid,
    this.destructiveLabel,
    this.destructiveResult,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? message;
  final String? labelText;
  final String? hintText;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool Function(String text)? isValid;
  final String? destructiveLabel;
  final String? destructiveResult;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => widget.isValid?.call(_ctrl.text) ?? true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            decoration: InputDecoration(labelText: widget.labelText, hintText: widget.hintText),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (_valid) Navigator.pop(context, v);
            },
          ),
        ],
      ),
      actions: [
        if (widget.destructiveLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(context, widget.destructiveResult),
            child: Text(widget.destructiveLabel!, style: TextStyle(color: AppTheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(
          onPressed: _valid ? () => Navigator.pop(context, _ctrl.text) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
