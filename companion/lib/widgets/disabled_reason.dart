// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// The one-line reason shown under a control that is visible but disabled.
class DisabledReason extends StatelessWidget {
  const DisabledReason(this.reason, {super.key, this.padding = const EdgeInsets.only(top: 4)});

  final String reason;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 13, color: t.textDim),
          const SizedBox(width: 5),
          Expanded(
            child: Text(reason, style: TextStyle(color: t.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
