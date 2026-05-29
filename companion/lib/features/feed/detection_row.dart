import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DetectionRow extends ConsumerWidget {
  const DetectionRow({super.key, required this.detection});
  final Detection detection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final engine = detection.engine;
    final hasGps = detection.latitude != null;
    final timeDiff = DateTime.now().difference(detection.appTimestamp);
    final timeStr = _formatTimeDiff(timeDiff);
    final manufacturer = ref.watch(ouiLookupProvider).lookup(detection.macAddress);
    final nodeLabel = detection.sourceNodeId.isEmpty
        ? ''
        : ref.watch(appStateProvider).labelForNode(detection.sourceNodeId);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showActions(context, ref);
        }
      },
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context, ref);
      },
      child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: engine.color, width: 3),
          ),
        ),
        child: Builder(builder: (_) {
          final headline = _headline(detection, manufacturer);
          final headlineIsMac = headline == detection.macAddress.toUpperCase();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: headline,
                          style: TextStyle(
                            color: detection.isBleDetection
                                ? const Color(0xFF4FA8FF)
                                : t.textPrimary,
                            fontSize: 15,
                            fontFamily: headlineIsMac ? 'monospace' : null,
                            fontWeight: FontWeight.w700,
                            letterSpacing: headlineIsMac ? 0.5 : 0,
                            height: 1.1,
                          ),
                        ),
                        if (manufacturer != null && manufacturer.isNotEmpty) ...[
                          TextSpan(
                            text: '  ·  ',
                            style: TextStyle(
                              color: t.textDim.withValues(alpha: 0.55),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: manufacturer,
                            style: TextStyle(
                              color: t.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ]),
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RssiBlock(rssi: detection.rssi),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _DetailLine(
                        detection: detection,
                        engine: engine,
                        manufacturer: manufacturer,
                        showMac: !headlineIsMac,
                        t: t,
                        nodeLabel: nodeLabel,
                      ),
                    ),
                  ),
                  if (detection.isWifiDetection &&
                      (detection.wardrive?.authMode ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    _AuthPill(authMode: detection.wardrive!.authMode),
                  ],
                  const SizedBox(width: 8),
                  Text(timeStr,
                      style: TextStyle(
                        color: t.textDim,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: Icons.gps_fixed,
                    color: AppTheme.foxhunter,
                    tooltip: 'Foxhunt',
                    onTap: () => _startFoxhunt(context, ref),
                  ),
                  _ActionIcon(
                    icon: Icons.location_on,
                    color: hasGps ? AppTheme.gpsGood : AppTheme.gpsNone,
                    tooltip: hasGps ? 'Show on map' : 'No GPS fix',
                    onTap: hasGps ? () => _zoomOnMap(context, ref) : null,
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    ),
    ),
    );
  }

  void _zoomOnMap(BuildContext context, WidgetRef ref) {
    if (detection.latitude == null || detection.longitude == null) return;
    ref.read(wardriveProvider).requestZoom(
      detection.latitude!,
      detection.longitude!,
    );
    context.go('/wardrive');
  }

  void _startFoxhunt(BuildContext context, WidgetRef ref) {
    ref.read(appStateProvider).setFoxhunterTarget(
      detection.macAddress,
      channel: detection.channel,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Foxhunting ${detection.macAddress.toUpperCase().substring(0, 8)}...'),
        backgroundColor: AppTheme.foxhunter,
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final nodeLabel = detection.sourceNodeId.isEmpty
        ? ''
        : ref.read(appStateProvider).labelForNode(detection.sourceNodeId);
    final t = AppTheme.of(context);
    final vendor = ref.read(ouiLookupProvider).lookup(detection.macAddress);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detection.macAddress.toUpperCase(),
              style: TextStyle(
                color: t.textPrimary, fontSize: 14,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              ),
            ),
            if (vendor != null)
              Text(vendor,
                  style: TextStyle(color: t.textSecondary, fontSize: 12)),
            if (detection.deviceName.isNotEmpty)
              Text(detection.deviceName,
                  style: TextStyle(color: t.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            // Detail summary in bottom sheet
            _DetailSummary(detection: detection, t: t, manufacturer: vendor, nodeLabel: nodeLabel),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.gps_fixed, color: AppTheme.foxhunter),
              title: const Text('Foxhunt This Device',
                  style: TextStyle(color: AppTheme.foxhunter)),
              subtitle: Text('Track by RSSI proximity',
                  style: TextStyle(color: t.textDim, fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _startFoxhunt(context, ref);
              },
            ),
            if (detection.latitude != null)
              ListTile(
                leading: const Icon(Icons.map, color: AppTheme.gpsGood),
                title: const Text('Show on Map',
                    style: TextStyle(color: AppTheme.gpsGood)),
                subtitle: Text('Zoom to detection location',
                    style: TextStyle(color: t.textDim, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _zoomOnMap(context, ref);
                },
              ),
            ListTile(
              leading: Icon(Icons.copy, color: t.textSecondary),
              title: Text('Copy MAC', style: TextStyle(color: t.textPrimary)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: detection.macAddress.toUpperCase()));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'MAC copied',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: t.surfaceLight,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.error),
              title: const Text('Delete Detection',
                  style: TextStyle(color: AppTheme.error)),
              subtitle: Text('Remove from feed',
                  style: TextStyle(color: t.textDim, fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(appStateProvider).removeDetection(detection.id);
              },
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  String _formatTimeDiff(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

/// Compact info chip with icon + label.
/// Detail summary shown in bottom sheet.
class _DetailSummary extends StatelessWidget {
  const _DetailSummary({required this.detection, required this.t, this.manufacturer, this.nodeLabel = ''});
  final Detection detection;
  final ResolvedTheme t;
  final String? manufacturer;
  final String nodeLabel;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (manufacturer != null) {
      rows.add(_detailRow(context, 'Vendor', manufacturer!));
    }
    rows.add(_detailRow(context, 'Engine', detection.engine.label));
    rows.add(_detailRow(context, 'Method', detection.method));
    rows.add(_detailRow(context, 'RSSI', '${detection.rssi} dBm'));
    if (detection.channel > 0) {
      rows.add(_detailRow(context, 'Channel', '${detection.channel}'));
    }
    rows.add(_detailRow(context, 'Seen', '\u00d7${detection.count}'));
    if (detection.sourceNodeId.isNotEmpty) {
      final lbl = nodeLabel.isNotEmpty && nodeLabel != detection.sourceNodeId
          ? '$nodeLabel  (${detection.sourceNodeId})'
          : detection.sourceNodeId;
      rows.add(_detailRow(context, 'Source Node', lbl));
    }
    if (detection.ssid.isNotEmpty) {
      rows.add(_detailRow(context, 'SSID', detection.ssid));
    }
    if (detection.wardrive != null) {
      rows.add(_detailRow(context, 'Security', _authLabel(detection.wardrive!.authMode)));
    }
    if (detection.flock?.isRaven == true) {
      rows.add(_detailRow(context, 'Type', 'Raven (ext battery)'));
    }
    if (detection.odid?.uavId != null) {
      rows.add(_detailRow(context, 'UAV ID', detection.odid!.uavId!));
    }
    if (detection.latitude != null) {
      rows.add(_detailRow(context, 'Location',
          '${detection.latitude!.toStringAsFixed(5)}, ${detection.longitude!.toStringAsFixed(5)}'));
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        children: [
          ...rows,
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'tap any row to copy',
              style: TextStyle(
                color: t.textDim,
                fontSize: 9,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyValue(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: t.surfaceLight,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        splashColor: t.textDim.withValues(alpha: 0.08),
        highlightColor: t.textDim.withValues(alpha: 0.05),
        onTap: () => _copyValue(context, label, value),
        onLongPress: () => _copyValue(context, label, value),
        onSecondaryTapDown: (_) => _copyValue(context, label, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 85,
                child: Text(
                  label,
                  style: TextStyle(
                    color: t.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _authLabel(int mode) {
    return switch (mode) {
      0 => 'Open (no encryption)',
      1 => 'WEP',
      2 => 'WPA-PSK',
      3 => 'WPA2-PSK',
      4 => 'WPA/WPA2-PSK',
      5 => 'WPA2-Enterprise',
      6 => 'WPA3-SAE',
      _ => 'WPA2-PSK',
    };
  }
}

Color _rssiColor(int rssi) {
  final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
  return Color.lerp(AppTheme.error, AppTheme.success, normalized)!;
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled ? color : color.withValues(alpha: 0.3);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 19, color: fg),
          ),
        ),
      ),
    );
  }
}

String _headline(Detection d, String? manufacturer) {
  if (d.wardrive != null && d.wardrive!.ssid.isNotEmpty) return d.wardrive!.ssid;
  if (d.deviceName.isNotEmpty) return d.deviceName;
  return d.macAddress.toUpperCase();
}

class _RssiBlock extends StatelessWidget {
  const _RssiBlock({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final color = _rssiColor(rssi);
    final norm = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final activeBars = (norm * 5).round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$rssi',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (i) {
            final on = i < activeBars;
            return Container(
              width: 2.5,
              height: 3.0 + i * 1.8,
              margin: const EdgeInsets.only(right: 1.2),
              decoration: BoxDecoration(
                color: on ? color : t.border,
                borderRadius: BorderRadius.circular(0.5),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.detection,
    required this.engine,
    required this.manufacturer,
    required this.showMac,
    required this.t,
    this.nodeLabel = '',
  });
  final Detection detection;
  final Engine engine;
  final String? manufacturer;
  final bool showMac;
  final ResolvedTheme t;
  final String nodeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = <Widget>[];
    if (showMac) {
      tokens.add(Text(
        detection.macAddress.toUpperCase(),
        style: TextStyle(
          color: t.textSecondary,
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ));
      tokens.add(_pipe());
    }
    tokens.add(Icon(
      detection.isWifiDetection ? Icons.wifi : Icons.bluetooth,
      size: 13,
      color: engine.color,
    ));
    if (detection.channel > 0) {
      tokens.add(const SizedBox(width: 5));
      tokens.add(_mono('${detection.channel}'));
    }
    if (detection.count > 1) {
      tokens.add(_pipe());
      tokens.add(_mono('x${detection.count}'));
    }
    if (detection.flock?.isRaven == true) {
      tokens.add(_pipe());
      tokens.add(Icon(Icons.memory, size: 12, color: AppTheme.warning));
      tokens.add(const SizedBox(width: 3));
      tokens.add(Text('RAVEN',
          style: TextStyle(
              color: AppTheme.warning,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800)));
      final fw = detection.flock?.ravenFirmware;
      if (fw != null && fw.isNotEmpty) {
        tokens.add(_pipe());
        tokens.add(_mono(fw));
      }
    }
    if (detection.unipwn != null) {
      tokens.add(_pipe());
      tokens.add(Icon(Icons.smart_toy, size: 12, color: Engine.uniPwn.color));
      tokens.add(const SizedBox(width: 3));
      tokens.add(Text(detection.unipwn!.robotType.toUpperCase(),
          style: TextStyle(
              color: Engine.uniPwn.color,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800)));
      if (detection.unipwn!.exploited) {
        tokens.add(_pipe());
        tokens.add(Icon(Icons.verified, size: 12, color: AppTheme.success));
        tokens.add(const SizedBox(width: 3));
        tokens.add(Text('PWNED',
            style: TextStyle(
                color: AppTheme.success,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800)));
      }
    }
    if (detection.odid?.uavId != null && detection.odid!.uavId!.isNotEmpty) {
      tokens.add(_pipe());
      tokens.add(Icon(Icons.flight, size: 12, color: Engine.skySpy.color));
      tokens.add(const SizedBox(width: 3));
      tokens.add(Text(detection.odid!.uavId!,
          style: TextStyle(
              color: Engine.skySpy.color,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700)));
      if (detection.odid!.altitudeMsl != null) {
        tokens.add(_pipe());
        tokens.add(_mono('${detection.odid!.altitudeMsl}m'));
      }
    }
    if (detection.detector != null) {
      final d = detection.detector!;
      if (d.filterDescription != null && d.filterDescription!.isNotEmpty) {
        tokens.add(_pipe());
        tokens.add(Text(d.filterDescription!,
            style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700)));
      }
      tokens.add(_pipe());
      tokens.add(_mono(d.isFullMac ? 'FULL' : 'OUI'));
    }
    if (detection.sourceNodeId.isNotEmpty) {
      tokens.add(_pipe());
      tokens.add(Icon(Icons.hub, size: 12, color: AppTheme.warning));
      tokens.add(const SizedBox(width: 3));
      tokens.add(Text(
          nodeLabel.isNotEmpty ? nodeLabel : detection.sourceNodeId,
          style: TextStyle(
              color: AppTheme.warning,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700)));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: tokens);
  }

  Widget _mono(String s) => Text(s,
      style: TextStyle(
        color: t.textDim,
        fontSize: 11,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ));

  Widget _pipe() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text('•',
            style: TextStyle(
              color: t.textDim.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            )),
      );

}

(String, Color) _authMeta(int mode) => switch (mode) {
      0 => ('OPEN', AppTheme.error),
      1 => ('WEP', AppTheme.warning),
      2 => ('WPA', AppTheme.warning),
      3 => ('WPA2', AppTheme.success),
      4 => ('WPA/2', AppTheme.success),
      5 => ('ENT', AppTheme.accent),
      6 => ('WPA3', AppTheme.success),
      _ => ('WPA2', AppTheme.success),
    };

class _AuthPill extends StatelessWidget {
  const _AuthPill({required this.authMode});
  final int authMode;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _authMeta(authMode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(authMode == 0 ? Icons.lock_open : Icons.lock,
              size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }
}

