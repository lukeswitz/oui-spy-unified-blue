import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
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
    final manufacturer = ref.read(ouiLookupProvider).lookup(detection.macAddress);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showActions(context, ref);
        }
      },
      child: GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context, ref);
      },
      child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Engine color accent bar
            Container(
              width: 3,
              color: engine.color,
            ),
            // Content
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // MAC + name + method + details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: MAC address + manufacturer
                          Row(
                            children: [
                              Text(
                                detection.macAddress.toUpperCase(),
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (manufacturer != null) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    manufacturer,
                                    style: TextStyle(
                                      color: t.textDim,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          // Row 2: Method badge + count + mesh node + device name
                          Row(
                            children: [
                              _MethodBadge(
                                method: detection.method,
                                color: engine.color,
                              ),
                              if (detection.channel > 0) ...[
                                const SizedBox(width: 4),
                                _InfoChip(
                                  icon: Icons.wifi,
                                  label: 'CH${detection.channel}',
                                  color: t.textDim,
                                  bgColor: t.textDim.withValues(alpha: 0.1),
                                ),
                              ],
                              if (detection.count > 1) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: t.textDim.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '\u00d7${detection.count}',
                                    style: TextStyle(
                                      color: t.textDim,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                              if (detection.sourceNodeId.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                _InfoChip(
                                  icon: Icons.hub,
                                  label: detection.sourceNodeId,
                                  color: AppTheme.warning,
                                  bgColor: AppTheme.warning.withValues(alpha: 0.15),
                                ),
                              ],
                              if (detection.deviceName.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    detection.deviceName,
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Row 3: Engine-specific details
                          _buildDetailsRow(t),
                        ],
                      ),
                    ),
                    // RSSI bar
                    _RssiIndicator(rssi: detection.rssi),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _startFoxhunt(context, ref),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.foxhunter.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.gps_fixed,
                          size: 14,
                          color: AppTheme.foxhunter,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: t.textDim,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: hasGps ? () => _zoomOnMap(context, ref) : null,
                          child: Icon(
                            Icons.location_on,
                            size: 10,
                            color: hasGps ? AppTheme.gpsGood : AppTheme.gpsNone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  /// Build engine-specific detail chips row.
  Widget _buildDetailsRow(ResolvedTheme t) {
    final chips = <Widget>[];

    switch (detection.engine) {
      case Engine.flockBle:
      case Engine.flockWifi:
        if (detection.flock != null) {
          if (detection.flock!.isRaven) {
            chips.add(_InfoChip(
              icon: Icons.memory,
              label: 'RAVEN',
              color: AppTheme.warning,
              bgColor: AppTheme.warning.withValues(alpha: 0.12),
            ));
            if (detection.flock!.ravenFirmware != null &&
                detection.flock!.ravenFirmware!.isNotEmpty) {
              chips.add(_InfoChip(
                icon: Icons.info_outline,
                label: detection.flock!.ravenFirmware!,
                color: t.textDim,
                bgColor: t.textDim.withValues(alpha: 0.1),
              ));
            }
          }
        }
        // Show which addr field matched
        chips.add(_AddrBadge(method: detection.method, t: t));

      case Engine.wardrive:
        if (detection.wardrive != null) {
          if (detection.wardrive!.ssid.isNotEmpty) {
            chips.add(_InfoChip(
              icon: Icons.wifi,
              label: detection.wardrive!.ssid,
              color: t.textSecondary,
              bgColor: t.textDim.withValues(alpha: 0.1),
              maxWidth: 120,
            ));
          }
          chips.add(_AuthBadge(authMode: detection.wardrive!.authMode, t: t));
        }

      case Engine.skySpy:
        if (detection.odid != null) {
          if (detection.odid!.uavId != null && detection.odid!.uavId!.isNotEmpty) {
            chips.add(_InfoChip(
              icon: Icons.flight,
              label: detection.odid!.uavId!,
              color: Engine.skySpy.color,
              bgColor: Engine.skySpy.color.withValues(alpha: 0.12),
              maxWidth: 100,
            ));
          }
          if (detection.odid!.altitudeMsl != null) {
            chips.add(_InfoChip(
              icon: Icons.height,
              label: '${detection.odid!.altitudeMsl}m',
              color: t.textDim,
              bgColor: t.textDim.withValues(alpha: 0.1),
            ));
          }
          if (detection.odid!.droneSpeed != null && detection.odid!.droneSpeed! > 0) {
            chips.add(_InfoChip(
              icon: Icons.speed,
              label: '${detection.odid!.droneSpeed}m/s',
              color: t.textDim,
              bgColor: t.textDim.withValues(alpha: 0.1),
            ));
          }
        }

      case Engine.uniPwn:
        if (detection.unipwn != null) {
          chips.add(_InfoChip(
            icon: Icons.smart_toy,
            label: detection.unipwn!.robotType.toUpperCase(),
            color: Engine.uniPwn.color,
            bgColor: Engine.uniPwn.color.withValues(alpha: 0.12),
          ));
          if (detection.unipwn!.exploited) {
            chips.add(_InfoChip(
              icon: Icons.verified,
              label: 'PWNED',
              color: AppTheme.success,
              bgColor: AppTheme.success.withValues(alpha: 0.12),
            ));
          }
        }

      case Engine.detector:
        if (detection.detector != null) {
          if (detection.detector!.filterDescription != null &&
              detection.detector!.filterDescription!.isNotEmpty) {
            chips.add(_InfoChip(
              icon: Icons.filter_alt,
              label: detection.detector!.filterDescription!,
              color: t.textDim,
              bgColor: t.textDim.withValues(alpha: 0.1),
              maxWidth: 120,
            ));
          }
          chips.add(_InfoChip(
            icon: detection.detector!.isFullMac ? Icons.fingerprint : Icons.blur_on,
            label: detection.detector!.isFullMac ? 'FULL MAC' : 'OUI',
            color: t.textDim,
            bgColor: t.textDim.withValues(alpha: 0.1),
          ));
        }

      case Engine.foxhunter:
        break;
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: chips,
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
    final t = AppTheme.of(context);
    final vendor = ref.read(ouiLookupProvider).lookup(detection.macAddress);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
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
            _DetailSummary(detection: detection, t: t, manufacturer: vendor),
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
                    content: const Text('MAC copied'),
                    backgroundColor: t.surface,
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
    );
  }

  String _formatTimeDiff(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

/// Compact info chip with icon + label.
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.maxWidth,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth!) : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge showing which 802.11 address field triggered detection.
class _AddrBadge extends StatelessWidget {
  const _AddrBadge({required this.method, required this.t});
  final String method;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final (label, hint) = switch (method) {
      'oui_addr1' => ('ADDR1', 'dst'),
      'oui_addr2' => ('ADDR2', 'src'),
      'oui_addr3' => ('ADDR3', 'bssid'),
      'wildcard_probe' => ('PROBE', 'empty SSID'),
      'oui_match' => ('OUI', 'ble prefix'),
      'name_match' => ('NAME', 'ble name'),
      'mfg_id' => ('MFG', 'mfg data'),
      'raven_uuid' => ('UUID', 'raven svc'),
      _ => ('', ''),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: t.textDim.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: t.textDim,
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Auth mode badge for wardrive detections.
class _AuthBadge extends StatelessWidget {
  const _AuthBadge({required this.authMode, required this.t});
  final int authMode;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (authMode) {
      0 => ('OPEN', AppTheme.error),
      1 => ('WEP', AppTheme.warning),
      2 => ('WPA', AppTheme.warning),
      3 => ('WPA2', AppTheme.success),
      4 => ('WPA/2', AppTheme.success),
      5 => ('ENT', AppTheme.accent),
      6 => ('WPA3', AppTheme.success),
      _ => ('WPA2', AppTheme.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: authMode == 0
            ? Border.all(color: color.withValues(alpha: 0.4), width: 0.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            authMode == 0 ? Icons.lock_open : Icons.lock,
            size: 8,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail summary shown in bottom sheet.
class _DetailSummary extends StatelessWidget {
  const _DetailSummary({required this.detection, required this.t, this.manufacturer});
  final Detection detection;
  final ResolvedTheme t;
  final String? manufacturer;

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
      rows.add(_detailRow(context, 'Source Node', detection.sourceNodeId));
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
      child: Column(children: rows),
    );
  }

  void _copyValue(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        backgroundColor: t.surface,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _copyValue(context, label, value),
      onSecondaryTapDown: (_) => _copyValue(context, label, value),
      onTap: () => _copyValue(context, label, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(color: t.textDim, fontSize: 10),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Icon(Icons.copy, size: 8, color: t.textDim.withValues(alpha: 0.4)),
          ],
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

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method, required this.color});
  final String method;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RssiIndicator extends StatelessWidget {
  const _RssiIndicator({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    // Normalize RSSI from -100..0 to 0..1
    final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final color = Color.lerp(AppTheme.error, AppTheme.success, normalized)!;

    return SizedBox(
      width: 30,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rssi',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: normalized,
              backgroundColor: t.border,
              color: color,
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}
