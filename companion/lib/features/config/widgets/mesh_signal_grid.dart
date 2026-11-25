// Copyright (c) 2026 Luke Switzer
import 'package:flutter/material.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/mesh_node_info.dart';
import 'package:oui_spy/theme/app_theme.dart';

Color signalColor(SignalLevel l, ResolvedTheme t) => switch (l) {
      SignalLevel.strong => AppTheme.success,
      SignalLevel.good => Color.lerp(AppTheme.success, AppTheme.warning, 0.45)!,
      SignalLevel.weak => AppTheme.warning,
      SignalLevel.poor => AppTheme.error,
      SignalLevel.heard => t.textDim,
    };

/// Rows hear columns: each cell is how strongly the row's node hears the column's node.
class MeshSignalGrid extends StatelessWidget {
  const MeshSignalGrid({super.key, required this.rows, required this.label});
  final List<MeshSignalRow> rows;
  final String Function(String id) label;

  static const double _cellW = 54;
  static const double _cellH = 34;
  static const double _headW = 74;

  String _short(String id) {
    final l = label(id);
    return l.length > 8 ? l.substring(0, 8) : l;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final ids = signalGridIds(rows);
    if (ids.isEmpty) return const SizedBox.shrink();
    final reporting = {for (final r in rows) r.id};

    Widget head(String text, {double w = _cellW, TextAlign align = TextAlign.center}) => SizedBox(
          width: w,
          height: _cellH,
          child: Align(
            alignment: align == TextAlign.start ? Alignment.centerLeft : Alignment.center,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        );

    Widget cell(String row, String col) {
      if (row == col) {
        return SizedBox(width: _cellW, height: _cellH, child: Center(child: Text('·', style: TextStyle(color: t.textDim))));
      }
      if (!reporting.contains(row)) {
        return SizedBox(width: _cellW, height: _cellH, child: Center(child: Text('n/a', style: TextStyle(color: t.textDim, fontSize: 10))));
      }
      final c = signalCell(rows, row, col);
      if (c == null) {
        return SizedBox(width: _cellW, height: _cellH, child: Center(child: Text('—', style: TextStyle(color: t.textDim))));
      }
      final level = signalLevel(c.rssi);
      final color = signalColor(level, t);
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          width: _cellW - 4,
          height: _cellH - 4,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            border: Border.all(color: color.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(c.rssi == null ? 'heard' : '${c.rssi}',
              style: TextStyle(color: t.textPrimary, fontSize: c.rssi == null ? 10 : 12, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: [
              Row(children: [
                head('hears', w: _headW, align: TextAlign.start),
                for (final id in ids) head(_short(id)),
              ]),
              for (final row in ids)
                Row(children: [
                  head(_short(row), w: _headW, align: TextAlign.start),
                  for (final col in ids) cell(row, col),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final (l, range) in const [
              (SignalLevel.strong, '-60 dBm and up'),
              (SignalLevel.good, '-61 to -70'),
              (SignalLevel.weak, '-71 to -80'),
              (SignalLevel.poor, 'below -80'),
              (SignalLevel.heard, 'heard, strength not measured'),
            ])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: signalColor(l, t), borderRadius: BorderRadius.circular(AppRadius.chip / 2)),
                ),
                const SizedBox(width: 5),
                Text('${signalLevelName(l)} $range', style: TextStyle(color: t.textDim, fontSize: 11)),
              ]),
          ],
        ),
      ],
    );
  }
}
