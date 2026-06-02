import 'package:flutter/material.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/theme/app_theme.dart';

enum OtaStepKind { fetch, transfer, verify, reboot, online }

class OtaStepperModel {
  const OtaStepperModel({
    required this.activeIndex,
    this.fraction = -1,
    this.failed = false,
    this.failedIndex = -1,
    this.complete = false,
    this.detail = '',
    this.transferIsWifi = false,
  });

  final int activeIndex;
  final double fraction;
  final bool failed;
  final int failedIndex;
  final bool complete;
  final String detail;
  final bool transferIsWifi;

  static const List<OtaStepKind> steps = [
    OtaStepKind.fetch,
    OtaStepKind.transfer,
    OtaStepKind.verify,
    OtaStepKind.reboot,
    OtaStepKind.online,
  ];

  factory OtaStepperModel.fromBleProgress(
    OtaProgress p, {
    bool reconnecting = false,
    bool confirmed = false,
  }) {
    if (confirmed) {
      return const OtaStepperModel(
          activeIndex: 4, complete: true, detail: 'Updated and confirmed');
    }
    switch (p.phase) {
      case OtaPhase.downloading:
        return OtaStepperModel(
          activeIndex: 0,
          fraction: p.bytesTotal > 0 ? p.fraction : -1,
          detail: p.bytesTotal > 0
              ? '${_kb(p.bytesSent)} / ${_kb(p.bytesTotal)} from GitHub'
              : 'Fetching firmware…',
        );
      case OtaPhase.uploading:
        return OtaStepperModel(
          activeIndex: 1,
          fraction: p.bytesTotal > 0 ? p.fraction : -1,
          detail: p.message.isNotEmpty ? p.message : 'Sending over BLE…',
        );
      case OtaPhase.verifying:
        return const OtaStepperModel(
            activeIndex: 2, detail: 'Verifying image (CRC)…');
      case OtaPhase.rebooting:
        return OtaStepperModel(
          activeIndex: reconnecting ? 4 : 3,
          detail: reconnecting
              ? 'Waiting for device to reconnect…'
              : 'Applied — device rebooting…',
        );
      case OtaPhase.error:
        return OtaStepperModel(
          activeIndex: -1,
          failed: true,
          failedIndex: _failIndexFor(p),
          detail: p.error ?? 'Update failed',
        );
      case OtaPhase.idle:
      case OtaPhase.checking:
      case OtaPhase.upToDate:
        return const OtaStepperModel(activeIndex: -1);
    }
  }

  factory OtaStepperModel.fromWifi(
    int status,
    int bytesRead, {
    int totalBytes = 0,
    bool reconnecting = false,
    bool confirmed = false,
  }) {
    if (confirmed) {
      return const OtaStepperModel(
          activeIndex: 4,
          complete: true,
          detail: 'Updated and confirmed',
          transferIsWifi: true);
    }
    switch (status) {
      case 1: // CONNECTING
        return const OtaStepperModel(
            activeIndex: 0, detail: 'Device joining WiFi…', transferIsWifi: true);
      case 2: // CONNECTED
        return const OtaStepperModel(
            activeIndex: 0,
            detail: 'WiFi joined — starting download…',
            transferIsWifi: true);
      case 3: // DOWNLOADING
        return OtaStepperModel(
          activeIndex: 1,
          fraction: totalBytes > 0 ? (bytesRead / totalBytes).clamp(0, 1) : -1,
          detail: totalBytes > 0
              ? '${_kb(bytesRead)} / ${_kb(totalBytes)} over WiFi'
              : '${_kb(bytesRead)} downloaded',
          transferIsWifi: true,
        );
      case 4: // REBOOTING
        return OtaStepperModel(
            activeIndex: reconnecting ? 4 : 3,
            detail: reconnecting
                ? 'Waiting for device to reconnect…'
                : 'Flashed — device rebooting…',
            transferIsWifi: true);
      default:
        if (status >= 0x80) {
          return OtaStepperModel(
              activeIndex: -1,
              failed: true,
              failedIndex: status == 0x81 ? 0 : 1,
              detail: _wifiErr(status),
              transferIsWifi: true);
        }
        return const OtaStepperModel(activeIndex: -1, transferIsWifi: true);
    }
  }

  static int _failIndexFor(OtaProgress p) {
    final e = (p.error ?? '').toLowerCase();
    if (e.contains('download') || e.contains('github') || e.contains('network')) {
      return 0;
    }
    if (e.contains('reject') || e.contains('crc') || e.contains('magic')) return 2;
    return 1;
  }

  static String _wifiErr(int s) {
    switch (s) {
      case 0x80:
        return 'No WiFi credentials on device';
      case 0x81:
        return 'WiFi join failed (wrong password / out of range)';
      case 0x82:
        return 'Download failed (HTTP/HTTPS)';
      case 0x83:
        return 'Image validation failed';
      case 0x84:
        return 'Flash write failed';
      default:
        return 'Update error 0x${s.toRadixString(16)}';
    }
  }

  static String _kb(int b) => '${(b / 1024).toStringAsFixed(0)}KB';
}

class OtaProgressStepper extends StatefulWidget {
  const OtaProgressStepper({super.key, required this.model});
  final OtaStepperModel model;

  @override
  State<OtaProgressStepper> createState() => _OtaProgressStepperState();
}

class _OtaProgressStepperState extends State<OtaProgressStepper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  IconData _iconFor(OtaStepKind k, bool wifi) {
    switch (k) {
      case OtaStepKind.fetch:
        return Icons.cloud_download_outlined;
      case OtaStepKind.transfer:
        return wifi ? Icons.wifi : Icons.bluetooth;
      case OtaStepKind.verify:
        return Icons.verified_outlined;
      case OtaStepKind.reboot:
        return Icons.restart_alt;
      case OtaStepKind.online:
        return Icons.check_circle_outline;
    }
  }

  String _labelFor(OtaStepKind k, bool wifi) {
    switch (k) {
      case OtaStepKind.fetch:
        return 'Fetch';
      case OtaStepKind.transfer:
        return wifi ? 'Download' : 'Send';
      case OtaStepKind.verify:
        return 'Verify';
      case OtaStepKind.reboot:
        return 'Reboot';
      case OtaStepKind.online:
        return 'Online';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final m = widget.model;
    final steps = OtaStepperModel.steps;
    final hasBar = m.activeIndex >= 0 && m.fraction >= 0 && !m.complete;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                _stepNode(t, i, steps[i], m),
                if (i < steps.length - 1) _connector(t, i, m),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (hasBar)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: m.fraction,
                minHeight: 5,
                backgroundColor: t.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            )
          else if (m.activeIndex >= 0 && !m.complete)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 5,
                backgroundColor: t.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
          if (m.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.detail,
                      style: TextStyle(
                        color: m.failed
                            ? AppTheme.error
                            : (m.complete
                                ? AppTheme.success
                                : t.textSecondary),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (hasBar)
                    Text(
                      '${(m.fraction * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepNode(
      ResolvedTheme t, int i, OtaStepKind kind, OtaStepperModel m) {
    final bool done = m.complete || (m.activeIndex >= 0 && i < m.activeIndex);
    final bool active = !m.complete && i == m.activeIndex && !m.failed;
    final bool failed = m.failed && i == m.failedIndex;

    Color ring;
    Color fill;
    Color fg;
    IconData icon = _iconFor(kind, m.transferIsWifi);
    if (failed) {
      ring = AppTheme.error;
      fill = AppTheme.error.withValues(alpha: 0.18);
      fg = AppTheme.error;
      icon = Icons.error_outline;
    } else if (done) {
      ring = AppTheme.success;
      fill = AppTheme.success.withValues(alpha: 0.18);
      fg = AppTheme.success;
      icon = Icons.check;
    } else if (active) {
      ring = AppTheme.accent;
      fill = AppTheme.accent.withValues(alpha: 0.18);
      fg = AppTheme.accent;
    } else {
      ring = t.border;
      fill = Colors.transparent;
      fg = t.textDim;
    }

    final circle = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
      child: Icon(icon, size: 15, color: fg),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        active
            ? AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final glow = 0.25 + 0.45 * _pulse.value;
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: glow),
                          blurRadius: 4 + 8 * _pulse.value,
                          spreadRadius: 1 + 2 * _pulse.value,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: circle,
              )
            : circle,
        const SizedBox(height: 4),
        Text(
          _labelFor(kind, m.transferIsWifi),
          style: TextStyle(
            color: failed
                ? AppTheme.error
                : (done
                    ? AppTheme.success
                    : (active ? AppTheme.accent : t.textDim)),
            fontSize: 9,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _connector(ResolvedTheme t, int i, OtaStepperModel m) {
    final bool filled = m.complete || (m.activeIndex >= 0 && i < m.activeIndex);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          height: 2,
          color: filled ? AppTheme.success : t.border,
        ),
      ),
    );
  }
}
