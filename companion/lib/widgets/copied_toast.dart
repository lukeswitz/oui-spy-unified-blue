// Copyright (c) 2026 Luke Switzer
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oui_spy/theme/app_theme.dart';

OverlayEntry? _current;
Timer? _timer;

void copyWithToast(BuildContext context, String label, String value) {
  Clipboard.setData(ClipboardData(text: value));
  HapticFeedback.lightImpact();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final t = AppTheme.of(context);
  _timer?.cancel();
  _current?.remove();
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(ctx).viewPadding.bottom + 96,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: t.surfaceLight,
            borderRadius: BorderRadius.circular(kMinInteractiveDimension),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text('$label copied', style: TextStyle(color: t.textPrimary, fontSize: 14)),
            ),
          ),
        ),
      ),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 1400), () {
    if (_current == entry) {
      entry.remove();
      _current = null;
    }
  });
}
