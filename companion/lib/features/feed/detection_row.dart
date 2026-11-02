import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/fleet_decode.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/deflock/deflock_provider.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/services/faa_service.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/sdr/sdr433_classify.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_spec_row.dart';

class DetectionRow extends ConsumerWidget {
  const DetectionRow({
    super.key,
    required this.detection,
    this.divider = true,
    this.horizontal = 20,
    this.onActivate,
  });
  final Detection detection;
  final bool divider;
  final double horizontal;
  final void Function(BuildContext, WidgetRef)? onActivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final dim = t.textDim;
    final engine = detection.engine;
    final timeDiff = DateTime.now().difference(detection.appTimestamp);
    final timeStr = _formatTimeDiff(timeDiff);
    final manufacturer = ref.watch(ouiLookupProvider).lookup(detection.macAddress);
    final priv = ref.watch(privacyScreenProvider);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showActions(context, ref);
        }
      },
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showActions(context, ref),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context, ref);
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 10),
        decoration: divider
            ? BoxDecoration(border: Border(bottom: BorderSide(color: t.border)))
            : null,
        child: Builder(builder: (_) {
          final headline = _headline(detection, manufacturer);
          final headlineIsMac = headline == detection.macAddress.toUpperCase();
          final gap = (MediaQuery.sizeOf(context).width * 0.04).clamp(12.0, 32.0);
          final clsStr = detectionAlertClass[detection];
          final sig = clsStr == null ? null : SignatureClass.parse(clsStr);
          final sdrCat =
              detection.engine == Engine.sdr ? _sdrCategory(detection) : null;
          final isWifi = detection.isWifiDetection;
          final clsColor = clsStr != null
              ? alertKindColor(clsStr)
              : engine == Engine.wardrive && !isWifi && sdrCat == null
                  ? AppTheme.themed(AppTheme.flockBle)
                  : engine.color;
          final clsLabel =
              (clsStr == null ? engine.label : alertKindLabel(clsStr)).toUpperCase();
          final icon = sig != null
              ? classIcon(sig)
              : sdrCat != null
                  ? sdrCat.icon
                  : (isWifi ? Icons.wifi : Icons.bluetooth);
          final authMode = detection.wardrive?.authMode ?? 0;
          final dimStyle = TextStyle(color: dim, fontSize: 11.5);
          final monoDim = dimStyle.copyWith(fontFamily: AppTheme.mono);
          final tagStyle = TextStyle(
              color: clsColor,
              fontFamily: AppTheme.mono,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6);
          final rawId = detection.macAddress.toUpperCase();
          final shownId = engine == Engine.sdr && rawId.contains('|')
              ? rawId.substring(rawId.indexOf('|') + 1)
              : rawId;
          final icons = [
            if (engine == Engine.skySpy) Icon(Icons.flight, size: 13, color: clsColor),
            if (OuiLookupService.isLawEnforcement(detection.macAddress))
              Icon(Icons.local_police, size: 13, color: AppTheme.warning),
          ];
          final meta = <TextSpan>[
            if (sdrCat != null) TextSpan(text: sdrCat.label.toUpperCase(), style: tagStyle),
            if (headlineIsMac && clsStr != null) TextSpan(text: clsLabel, style: tagStyle),
            if (detection.odid?.uavId?.isNotEmpty ?? false)
              TextSpan(
                  text: 'UAS ${detection.odid!.uavId}',
                  style: tagStyle.copyWith(letterSpacing: 0, fontWeight: FontWeight.w700)),
            if (isWifi && detection.channel > 0)
              TextSpan(text: 'CH ${detection.channel}', style: monoDim),
            if (!headlineIsMac) TextSpan(text: maskMac(shownId, priv), style: monoDim),
            if (manufacturer != null && manufacturer.isNotEmpty)
              TextSpan(text: manufacturer, style: dimStyle),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 11),
                child: Icon(icon, size: 24, color: clsColor),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  headlineIsMac ? maskMac(headline, priv) : maskName(headline, priv),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: t.textPrimary,
                                        fontFamily: headlineIsMac ? AppTheme.mono : null,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              if (isWifi && authMode > 0) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.lock, size: 12, color: AppTheme.success),
                                const SizedBox(width: 3),
                                Text(_authShort(authMode),
                                    style: TextStyle(
                                        color: AppTheme.success,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: gap),
                        Text('${detection.rssi}',
                            style: TextStyle(
                                color: _rssiColor(detection.rssi),
                                fontFamily: AppTheme.mono,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        for (final i in icons) ...[i, const SizedBox(width: 5)],
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              for (var i = 0; i < meta.length; i++) ...[
                                if (i > 0) TextSpan(text: '  ·  ', style: dimStyle),
                                meta[i],
                              ],
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: gap),
                        Text(timeStr, style: monoDim.copyWith(fontSize: 10.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    if (onActivate != null) {
      onActivate!(context, ref);
      return;
    }
    showDetectionDetails(context, ref, detection);
  }

  String _formatTimeDiff(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat(detection.appTimestamp.year == DateTime.now().year ? 'MMM d' : 'MMM d yy')
        .format(detection.appTimestamp);
  }
}

void detectionZoomOnMap(
    BuildContext context, WidgetRef ref, Detection detection) {
  if (detection.latitude == null || detection.longitude == null) return;
  ref.read(wardriveProvider).requestZoom(
        detection.latitude!,
        detection.longitude!,
        detection: detection,
      );
  context.go('/wardrive');
}

void detectionStartFoxhunt(
    BuildContext context, WidgetRef ref, Detection detection) {
  ref.read(appStateProvider).setFoxhunterTarget(
        detection.macAddress,
        channel: detection.channel,
        fromPhone: detection.sourceNodeId == BleManager.phoneNodeId ||
            detection.sourceNodeId == BleManager.usbWifiNodeId,
      );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
          'Foxhunting ${detection.macAddress.toUpperCase().substring(0, 8)}...'),
      backgroundColor: AppTheme.foxhunter,
    ),
  );
}

Future<void> _wigleLookup(BuildContext ctx, WidgetRef ref, Detection d) async {
  String text;
  try {
    final rec = await ref.read(wigleProvider).lookupNetwork(d.macAddress);
    if (rec == null) {
      text = 'WiGLE has no record of this BSSID. A new AP using an established network name fits an evil twin.';
    } else if (rec.lat == null || rec.lon == null || d.latitude == null || d.longitude == null) {
      text = 'WiGLE has this BSSID${rec.ssid != null ? ' as "${rec.ssid}"' : ''}, last updated ${rec.lastUpdate ?? 'unknown'}. '
          '${d.latitude == null ? 'This sighting has no GPS, so distance cannot be compared.' : 'WiGLE gave no position.'}';
    } else {
      final km = const Distance().as(LengthUnit.Meter, LatLng(rec.lat!, rec.lon!), LatLng(d.latitude!, d.longitude!)) / 1000;
      text = 'WiGLE records this BSSID${rec.ssid != null ? ' as "${rec.ssid}"' : ''} ${km.toStringAsFixed(km < 10 ? 2 : 0)} km from this sighting '
          '(last updated ${rec.lastUpdate ?? 'unknown'}). ${km < 1 ? 'Recorded here: consistent with a legitimate AP.' : 'Recorded elsewhere: the hardware moved, or it is cloning that BSSID.'}';
    }
  } on WigleApiException catch (e) {
    text = e.message;
  } catch (e) {
    text = 'WiGLE lookup failed: $e';
  }
  if (!ctx.mounted) return;
  await showDialog<void>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('WiGLE lookup'),
      content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

Future<void> _ringTracker(BuildContext ctx, WidgetRef ref, String mac) async {
  final ble = ref.read(bleManagerProvider);
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  messenger?.showSnackBar(const SnackBar(content: Text('Board is connecting to the tracker…')));
  final result = ble.ringResults
      .firstWhere((r) => r.mac.isEmpty || r.mac == mac.toUpperCase())
      .timeout(const Duration(seconds: 20), onTimeout: () => (mac: mac, status: 0xFF, protocol: 0xFF));
  if (!await ble.ringTracker(mac)) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not send the ring command')));
    return;
  }
  final r = await result;
  messenger?.showSnackBar(SnackBar(
    content: Text(switch (r.status) {
      0 => 'Sound command sent. Listen for the tracker.',
      1 => 'Board is busy with another ring',
      2 => 'Tracker did not accept a connection (out of range, or not separated from its owner)',
      3 => 'Tracker has no known sound service',
      4 => 'Tracker refused the sound command',
      _ => 'No answer from the board',
    }),
  ));
}

void showDetectionDetails(
    BuildContext context, WidgetRef ref, Detection detection,
    {bool showMapAction = true,
    VoidCallback? onDelete,
    VoidCallback? onShowMap}) {
    final nodeLabel = detection.sourceNodeId.isEmpty
        ? ''
        : ref.read(appStateProvider).labelForNode(detection.sourceNodeId);
    final t = AppTheme.of(context);
    final vendor = ref.read(ouiLookupProvider).lookup(detection.macAddress);
    if (detection.flock != null &&
        detection.latitude != null &&
        detection.longitude != null) {
      ref
          .read(deflockProvider)
          .ensureAround(detection.latitude!, detection.longitude!);
    }
    final priv = ref.read(privacyScreenProvider);
    final rawTitle = detection.deviceName.isNotEmpty
        ? detection.deviceName
        : _headline(detection, vendor);
    final title = rawTitle == detection.macAddress.toUpperCase()
        ? maskMac(rawTitle, priv)
        : maskName(rawTitle, priv);
    final detTier = NotificationService.confidenceLabel(detection.detector?.confidence ?? 0);
    final confidence = detection.flock
            ?.confidence(detection.method)
            .label(detection.method) ??
        (detTier == null ? null : '${detTier.toUpperCase()} CONFIDENCE');
    final canRing = detection.engine == Engine.detector &&
        detection.method == 'tracker' &&
        ref.read(appStateProvider).isConnected;
    final shownMac = maskMac(detection.macAddress.toUpperCase(), priv);
    final macLine = vendor != null && vendor.isNotEmpty
        ? '$shownMac · $vendor'
        : shownMac;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: t.surface,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('detail-header'),
              color: t.fill,
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        key: const Key('detail-engine-chip'),
                        color: t.mark,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        child: Text(
                          detection.isWifiDetection
                              ? methodLabel(detection.method)
                              : detection.engine.label.toUpperCase(),
                          style: Theme.of(ctx)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: t.fill),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: confidence == null
                            ? const SizedBox.shrink()
                            : DEyebrow(confidence, color: t.onFillDim, maxLines: 2),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.close, color: t.onFill),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(ctx).textTheme.displaySmall?.copyWith(
                            color: t.onFill,
                            fontSize: 28,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      macLine,
                      style: TextStyle(
                        color: t.onFillDim,
                        fontSize: 12,
                        fontFamily: AppTheme.mono,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetectionInsights(detection: detection, t: t),
                    _DetailSummary(
                        detection: detection,
                        t: t,
                        manufacturer: vendor,
                        nodeLabel: nodeLabel),
                    if (detection.odid?.uavId != null &&
                        detection.odid!.uavId!.isNotEmpty)
                      _FaaLookupTile(
                        uasId: detection.odid!.uavId!,
                        onResult: (reg) {
                          Navigator.pop(ctx);
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _FaaResultSheet(
                              reg: reg,
                              uasId: detection.odid!.uavId!,
                              t: t,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      detectionStartFoxhunt(context, ref, detection);
                    },
                    child: Row(
                      children: [
                        const Expanded(child: Text('Foxhunt this device')),
                        Icon(Icons.arrow_forward, size: 18, color: t.buttonMark),
                      ],
                    ),
                  ),
                  if (detection.method == 'evil_twin' ||
                      detection.method == 'karma' ||
                      detection.method == 'wifi_ap') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.travel_explore, size: 18),
                      label: const Text('Check this AP on WiGLE'),
                      onPressed: () => _wigleLookup(ctx, ref, detection),
                    ),
                  ],
                  if (canRing) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.volume_up, size: 18),
                      label: const Text('Make it play a sound'),
                      onPressed: () => _ringTracker(ctx, ref, detection.macAddress),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (showMapAction && detection.latitude != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (onShowMap != null) {
                                onShowMap();
                              } else {
                                detectionZoomOnMap(context, ref, detection);
                              }
                            },
                            child: const Text('Map'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: detection.macAddress.toUpperCase()));
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'MAC copied',
                                  style: TextStyle(color: t.textPrimary),
                                ),
                                backgroundColor: t.surfaceLight,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: BorderSide(color: AppTheme.error),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (onDelete != null) {
                              onDelete();
                              return;
                            }
                            ref
                                .read(appStateProvider)
                                .removeDetectionGroup(detection);
                            ref
                                .read(wardriveProvider)
                                .removeDetectionGroup(detection);
                          },
                          child: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
}

/// Detail summary shown in bottom sheet.
class _DetectionInsights extends ConsumerWidget {
  const _DetectionInsights({required this.detection, required this.t});
  final Detection detection;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!detection.isBleDetection && !detection.isWifiDetection) {
      return const SizedBox.shrink();
    }
    final dev = ref.read(deviceRegistryProvider).explain(detection);
    final o = dev.obs;
    final g = dev.guess;

    final adv = <AdvField>[
      for (final m in o.mfgRecords) ...AdvPayloadDecoder.decodeManufacturer(m),
      for (final s in o.serviceData) ...AdvPayloadDecoder.decodeService(s),
    ];
    final decoded = <DecodedField>[
      for (final s in dev.signatures)
        if (s.decode case final d?) ...FleetDecode.decode(d, o),
    ];

    Widget row(String k, String v, {bool mono = false}) =>
        DSpecRow(label: k, value: v, mono: mono);
    Widget section(String label, List<Widget> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 2),
                child: DEyebrow(label)),
            ...rows,
          ],
        );

    final sections = <Widget>[];
    final isFlock = detection.engine == Engine.flockWifi || detection.engine == Engine.flockBle;
    final flockConf = detection.flock?.confidence(detection.method);

    if (isFlock) {
      sections.add(section('WHAT THIS LOOKS LIKE', [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text('Flock Safety device',
              style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        Text('Matched by ${methodLabel(detection.method)}.',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.3)),
        if (flockConf != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DEyebrow(flockConf.label(detection.method), color: AppTheme.error, maxLines: 2),
          ),
      ]));
    } else if (g.headline.isNotEmpty) {
      sections.add(section('WHAT THIS LOOKS LIKE', [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(DeviceExplain.title(g),
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ),
        if (g.because.isNotEmpty)
          Text(g.because,
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.3)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: DEyebrow('${_confWord(g.confidence)} confidence',
              color: _confColor(g.confidence)),
        ),
      ]));
    }

    sections.add(section('IDENTITY', [
      if (dev.vendor != null && dev.vendor!.isNotEmpty) row('Vendor', dev.vendor!),
      row('Address', DeviceExplain.addressExplain(o)),
      if (o.kind == RadioKind.wifi && o.hiddenSsid) row('SSID', 'Hidden'),
    ]));

    if (DeviceExplain.rssiMeasured(o.rssi)) {
      sections.add(section('SIGNAL', [
        row('Strength', DeviceExplain.rssiExplain(o.rssi)),
        if (o.rssiMin != o.rssiMax)
          row('Range this session', '${o.rssiMin} to ${o.rssiMax} dBm'),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Closer to 0 dBm is louder here, not a distance.',
              style: TextStyle(color: t.textDim, fontSize: 11)),
        ),
      ]));
    }

    if (decoded.isNotEmpty) {
      sections.add(section('DECODED', [
        for (final f in decoded)
          row(f.label, f.note.isEmpty ? f.display : '${f.display}\n${f.note}'),
      ]));
    }
    if (adv.isNotEmpty) {
      sections.add(section('ADVERTISEMENT', [for (final f in adv) row(f.label, f.value)]));
    }
    if (o.serviceUuids.isNotEmpty) {
      sections.add(section('SERVICES', [
        for (final u in o.serviceUuids)
          row(u, DeviceExplain.uuidGloss(u) ?? '', mono: true),
      ]));
    }

    sections.add(section('SESSION', [
      row('First seen', _stamp(o.firstSeenMs)),
      row('Last seen', _stamp(o.lastSeenMs)),
      if (detection.count > 1) row('Hits', '${detection.count}'),
      for (final s in dev.signatures) row('Signature', s.name),
    ]));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
  }

  static String _stamp(int ms) =>
      DateFormat('MMM d, HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(ms));
  static String _confWord(Confidence c) => switch (c) {
        Confidence.high => 'HIGH',
        Confidence.medium => 'MEDIUM',
        Confidence.low => 'LOW',
      };
  Color _confColor(Confidence c) => switch (c) {
        Confidence.high => AppTheme.success,
        Confidence.medium => AppTheme.accent,
        Confidence.low => t.textDim,
      };
}

class _DetailSummary extends ConsumerWidget {
  const _DetailSummary({required this.detection, required this.t, this.manufacturer, this.nodeLabel = ''});
  final Detection detection;
  final ResolvedTheme t;
  final String? manufacturer;
  final String nodeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[];

    if (manufacturer != null) {
      rows.add(_detailRow(context, 'Vendor', manufacturer!));
    }
    rows.add(_detailRow(context, 'Engine', detection.engine.label));
    rows.add(_detailRow(context, 'Method', methodLabel(detection.method)));
    final why = detection.detector?.filterDescription?.trim() ?? '';
    if (why.isNotEmpty) {
      rows.add(_detailRow(
        context,
        switch (detection.method) {
          'probe_ssid' => 'Probing for',
          'ble_watchlist' || 'wifi_watchlist' => 'Watchlist',
          _ => 'Matched',
        },
        why,
      ));
    }
    if (!(detection.engine == Engine.sdr && detection.rssi == 0)) {
      rows.add(_detailRow(context, 'RSSI', '${detection.rssi} dBm'));
    }
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
    if (detection.engine == Engine.sdr && detection.ssid.isNotEmpty) {
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(detection.ssid);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } on FormatException {
        // Non-JSON ssid on an SDR row (legacy record): render no extra fields.
      }
      if (payload != null) {
        final freq = (payload['frequency'] as num?)?.toDouble();
        if (freq != null) {
          rows.add(_detailRow(
              context, 'Frequency', '${(freq / 1e6).toStringAsFixed(3)} MHz'));
        }
        const skip = {'frequency', 'model', 'id', 'kind', 'count', 'rssi'};
        for (final e in payload.entries) {
          if (skip.contains(e.key) || e.value == null) continue;
          rows.add(_detailRow(context, sdrFieldLabel(e.key), '${e.value}'));
        }
      }
    } else if (detection.ssid.isNotEmpty) {
      rows.add(_detailRow(context, 'SSID', maskName(detection.ssid, ref.watch(privacyScreenProvider))));
    }
    if (detection.wardrive != null) {
      rows.add(_detailRow(context, 'Security', _authLabel(detection.wardrive!.authMode)));
    }
    if (detection.flock?.isRaven == true) {
      rows.add(_detailRow(context, 'Type', 'Raven (ext battery)'));
    }
    if (detection.flock != null) {
      final fc = detection.flock!.confidence(detection.method);
      rows.add(_detailRow(context, 'Confidence', fc.label(detection.method)));
    }
    final flockSigs = _flockSignalLabels(detection.flock);
    if (flockSigs.isNotEmpty) {
      rows.add(_detailRow(context, 'Signals', flockSigs.join(', ')));
    }
    final lat = detection.latitude;
    final lon = detection.longitude;
    if (detection.flock != null && lat != null && lon != null) {
      final df = ref.watch(deflockProvider);
      final match = df.match(lat, lon);
      final busy = df.loading && match.verdict == AlprMapVerdict.unknown;
      rows.add(_detailRow(context, 'DeFlock',
          busy ? 'Checking the map…' : '${match.label} — ${match.detail}'));
      if (osmContributionAllowed(
          detection.flock!.confidence(detection.method), match.verdict)) {
        rows.add(_detailRow(
            context, 'Add to OSM', DeflockProvider.osmNoteUrl(lat, lon)));
      }
    }
    final odid = detection.odid;
    if (odid != null) {
      if (odid.uavId != null && odid.uavId!.isNotEmpty) {
        rows.add(_detailRow(context, 'UAV ID', odid.uavId!));
      }
      if (odid.operatorId != null && odid.operatorId!.isNotEmpty) {
        rows.add(_detailRow(context, 'Operator ID', odid.operatorId!));
      }
      final hasDronePos = odid.droneLat != null &&
          odid.droneLon != null &&
          !(odid.droneLat == 0 && odid.droneLon == 0);
      if (hasDronePos) {
        rows.add(_detailRow(context, 'Drone Pos',
            '${odid.droneLat!.toStringAsFixed(5)}, ${odid.droneLon!.toStringAsFixed(5)}'));
      } else {
        rows.add(_detailRow(context, 'Drone Pos', 'No GPS fix'));
        rows.add(_detailRow(context, 'Est. Range',
            '${rssiRangeLabel(detection.rssi, isBle: detection.isBleDetection)} (RSSI)'));
      }
      if (odid.altitudeMsl != null) {
        rows.add(_detailRow(context, 'Alt MSL', '${odid.altitudeMsl} m'));
      }
      if (odid.heightAgl != null) {
        rows.add(_detailRow(context, 'Height AGL', '${odid.heightAgl} m'));
      }
      if (odid.droneSpeed != null) {
        rows.add(_detailRow(context, 'Speed', '${odid.droneSpeed} m/s'));
      }
      if (odid.droneHeading != null) {
        rows.add(_detailRow(context, 'Heading', '${odid.droneHeading}°'));
      }
      if (odid.pilotLat != null &&
          odid.pilotLon != null &&
          !(odid.pilotLat == 0 && odid.pilotLon == 0)) {
        rows.add(_detailRow(context, 'Pilot Pos',
            '${odid.pilotLat!.toStringAsFixed(5)}, ${odid.pilotLon!.toStringAsFixed(5)}'));
      }
      if (odid.uaType != null && odid.uaType! > 0) {
        rows.add(_detailRow(context, 'UA Type', _odidUaType(odid.uaType!)));
      }
      if (odid.idType != null && odid.idType! > 0) {
        rows.add(_detailRow(context, 'ID Type', _odidIdType(odid.idType!)));
      }
      if (odid.selfId != null && odid.selfId!.isNotEmpty) {
        final selfIdLabel = (odid.selfIdType != null && odid.selfIdType! > 0)
            ? 'Self-ID (${odid.selfIdType})'
            : 'Self-ID';
        rows.add(_detailRow(context, selfIdLabel, odid.selfId!));
      }
      if (odid.vertSpeed != null) {
        rows.add(_detailRow(context, 'Vert Speed', '${odid.vertSpeed} m/s'));
      }
      if (odid.altitudeBaro != null) {
        rows.add(_detailRow(context, 'Alt Baro', '${odid.altitudeBaro} m'));
      }
      if (odid.operatorAlt != null) {
        rows.add(_detailRow(context, 'Operator Alt', '${odid.operatorAlt} m'));
      }
      if (odid.opLocationType != null) {
        rows.add(_detailRow(context, 'Op Location', _odidOpLocationType(odid.opLocationType!)));
      }
      if (odid.heightType != null) {
        rows.add(_detailRow(context, 'Height Ref', _odidHeightType(odid.heightType!)));
      }
      if (odid.status != null && odid.status! > 0) {
        rows.add(_detailRow(context, 'UA Status', _odidStatus(odid.status!)));
      }
      if (odid.classification != null || odid.categoryEu != null || odid.classEu != null) {
        final cls = odid.classification;
        final isEu = cls == 1;
        if (!isEu && cls != null) {
          rows.add(_detailRow(context, 'Classification', 'Undeclared'));
        }
        if (isEu) {
          if (odid.categoryEu != null) {
            rows.add(_detailRow(context, 'EU Category', _odidCategoryEu(odid.categoryEu!)));
          }
          if (odid.classEu != null) {
            rows.add(_detailRow(context, 'EU Class', _odidClassEu(odid.classEu!)));
          }
        }
      }
      if (odid.horizAcc != null || odid.vertAcc != null || odid.baroAcc != null || odid.speedAcc != null) {
        final parts = <String>[];
        if (odid.horizAcc != null && odid.horizAcc! > 0) parts.add('H:${odid.horizAcc}');
        if (odid.vertAcc != null && odid.vertAcc! > 0) parts.add('V:${odid.vertAcc}');
        if (odid.baroAcc != null && odid.baroAcc! > 0) parts.add('B:${odid.baroAcc}');
        if (odid.speedAcc != null && odid.speedAcc! > 0) parts.add('S:${odid.speedAcc}');
        if (parts.isNotEmpty) {
          rows.add(_detailRow(context, 'Accuracy', parts.join('  ')));
        }
      }
      if (odid.areaCount != null && odid.areaCount! > 0) {
        final area = 'count:${odid.areaCount}'
            '  r:${odid.areaRadius ?? 0}m'
            '  ceil:${odid.areaCeiling ?? 0}m'
            '  floor:${odid.areaFloor ?? 0}m';
        rows.add(_detailRow(context, 'Op Area', area));
      }
      if (odid.locTimestamp != null && odid.locTimestamp! > 0) {
        final secs = odid.locTimestamp! ~/ 10;
        final tenths = odid.locTimestamp! % 10;
        rows.add(_detailRow(context, 'Loc Timestamp', '${secs}s.$tenths after hour'));
      }
    }
    if (detection.latitude != null) {
      rows.add(_detailRow(context, 'Location',
          '${detection.latitude!.toStringAsFixed(5)}, ${detection.longitude!.toStringAsFixed(5)}'));
    }

    return Column(
      children: [
        ...rows,
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'tap any row to copy',
            style: TextStyle(
              color: t.textDim,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  void _copyValue(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied',
          style: TextStyle(color: t.textPrimary),
        ),
        backgroundColor: t.surfaceLight,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return GestureDetector(
      onLongPress: () => _copyValue(context, label, value),
      onSecondaryTapDown: (_) => _copyValue(context, label, value),
      child: Material(
        type: MaterialType.transparency,
        child: DSpecRow(
          label: label,
          value: value,
          mono: _monoLabels.contains(label),
          onTap: () => _copyValue(context, label, value),
        ),
      ),
    );
  }

  static const _monoLabels = {
    'RSSI',
    'Channel',
    'Seen',
    'Source Node',
    'Location',
    'UAV ID',
    'Operator ID',
    'Drone Pos',
    'Pilot Pos',
    'Add to OSM',
  };

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

  static String _odidUaType(int v) => const {
        0: 'None', 1: 'Aeroplane', 2: 'Multirotor', 3: 'Gyroplane',
        4: 'Hybrid Lift', 5: 'Ornithopter', 6: 'Glider', 7: 'Kite',
        8: 'Free Balloon', 9: 'Captive Balloon', 10: 'Airship',
        11: 'Free Fall/Parachute', 12: 'Rocket', 13: 'Tethered Powered',
        14: 'Ground Obstacle', 15: 'Other',
      }[v] ?? 'Unknown ($v)';

  static String _odidIdType(int v) => const {
        0: 'None', 1: 'Serial Number', 2: 'CAA Registration',
        3: 'UTM (UUID)', 4: 'Specific Session ID',
      }[v] ?? 'Unknown ($v)';

  static String _odidOpLocationType(int v) => const {
        0: 'Takeoff', 1: 'Live GNSS', 2: 'Fixed',
      }[v] ?? 'Unknown ($v)';

  static String _odidHeightType(int v) =>
      v == 0 ? 'Above Takeoff' : v == 1 ? 'AGL' : 'Unknown ($v)';

  static String _odidStatus(int v) => const {
        0: 'Undeclared', 1: 'Ground', 2: 'Airborne',
        3: 'Emergency', 4: 'Remote ID System Failure',
      }[v] ?? 'Unknown ($v)';

  static String _odidCategoryEu(int v) => const {
        0: 'Undeclared', 1: 'Open', 2: 'Specific', 3: 'Certified',
      }[v] ?? 'Unknown ($v)';

  static String _odidClassEu(int v) {
    if (v == 0) return 'Undeclared';
    if (v >= 1 && v <= 6) return 'EU C${v - 1}';
    return 'Unknown ($v)';
  }
}

Color _rssiColor(int rssi) {
  final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
  return Color.lerp(AppTheme.error, AppTheme.success, normalized)!;
}

String _authShort(int mode) => switch (mode) {
      0 => 'OPEN',
      1 => 'WEP',
      2 => 'WPA',
      5 => 'WPA2-E',
      6 => 'WPA3',
      _ => 'WPA2',
    };

Sdr433Category? _sdrCategory(Detection d) {
  if (d.ssid.isEmpty) return null;
  Map<String, dynamic>? p;
  try {
    final decoded = jsonDecode(d.ssid);
    if (decoded is Map<String, dynamic>) p = decoded;
  } on FormatException {
    return null;
  }
  if (p == null) return null;
  return classify433(
    (p['model'] as String?) ?? '',
    p.keys,
    devType: (p['kind'] as String?) ?? '',
  );
}

String _headline(Detection d, String? manufacturer) {
  if (d.wardrive != null && d.wardrive!.ssid.isNotEmpty) return d.wardrive!.ssid;
  if (d.deviceName.isNotEmpty) return d.deviceName;
  if (_isPlatformId(d.macAddress)) return 'Unnamed BLE device';
  return d.macAddress.toUpperCase();
}

final _platformIdPattern = RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-');

bool _isPlatformId(String id) => _platformIdPattern.hasMatch(id);

List<String> _flockSignalLabels(FlockExtension? flock) {
  if (flock == null || flock.signals == 0) return const [];
  return [
    if (flock.hasSignal(FlockSignal.oui)) 'OUI',
    if (flock.hasSignal(FlockSignal.name)) 'NAME',
    if (flock.hasSignal(FlockSignal.serial)) 'SERIAL',
    if (flock.hasSignal(FlockSignal.mfg)) 'XUNTONG',
    if (flock.hasSignal(FlockSignal.tn)) 'TN',
    if (flock.hasSignal(FlockSignal.ravenUuid)) 'RAVEN-UUID',
    if (flock.hasSignal(FlockSignal.gatt)) 'FLOCK-GATT',
    if (flock.hasSignal(FlockSignal.dfu)) 'NORDIC-DFU',
  ];
}

String detectorTitle(Detection d) {
  final why = d.detector?.filterDescription?.trim() ?? '';
  return switch (d.method) {
    'probe_ssid' => why.isEmpty ? 'Wi-Fi probe request' : 'Probe request for "$why"',
    'ble_watchlist' || 'wifi_watchlist' => why.isEmpty ? 'Watchlist hit' : why,
    'deauth_storm' => 'Deauth / disassoc attack',
    _ => why.isEmpty ? methodLabel(d.method) : why,
  };
}

String methodLabel(String method) => switch (method) {
  'oui_addr1' => 'ADDR1 (DST)',
  'oui_addr2' => 'ADDR2 (SRC)',
  'oui_addr3' => 'ADDR3 (BSSID)',
  'ssid' => 'SSID',
  'wildcard_probe' => 'PROBE REQ',
  'wildcard_probe_ie_sig' => 'FLOCK IE PROBE',
  'oui_match' => 'BLE OUI',
  'name_match' => 'BLE NAME',
  'mfg_id' => 'MFG DATA',
  'raven_uuid' => 'RAVEN UUID',
  'gatt_uuid' => 'FLOCK GATT',
  'nordic_dfu' => 'NORDIC DFU',
  'tracker' => 'TRACKER',
  'evil_twin' => 'EVIL TWIN',
  'karma' => 'KARMA AP',
  'mesh' => 'MESH RADIO',
  'drone_vendor' => 'DRONE OUI',
  'flipper' => 'FLIPPER',
  'deauth_storm' => 'DEAUTH',
  'probe_ssid' => 'PROBE',
  'pwnagotchi' => 'PWNAGOTCHI',
  'glasses' => 'META GLASSES',
  'axon' => 'AXON',
  'ble_watchlist' => 'WATCHLIST',
  'wifi_watchlist' => 'WATCHLIST',
  'ble_proximity' => 'PROXIMITY',
  'wifi_proximity' => 'PROXIMITY',
  'wifi_ap' => 'WIFI AP',
  'wifi_client' => 'WIFI CLIENT',
  'ble_adv' => 'BLE ADV',
  'unitree_ble' => 'UNITREE',
  'pcap' => 'PCAP',
  _ => method.toUpperCase(),
};

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
            fontSize: 15,
            fontFamily: AppTheme.mono,
            fontWeight: FontWeight.w700,
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
              color: on ? color : t.border,
            );
          }),
        ),
      ],
    );
  }
}

class _FaaLookupTile extends ConsumerStatefulWidget {
  const _FaaLookupTile({
    required this.uasId,
    required this.onResult,
  });

  final String uasId;
  final void Function(FaaRegistration) onResult;

  @override
  ConsumerState<_FaaLookupTile> createState() => _FaaLookupTileState();
}

class _FaaLookupTileState extends ConsumerState<_FaaLookupTile> {
  bool _loading = false;
  String? _error;

  Future<void> _lookup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(faaServiceProvider);
      final reg = await svc.lookup(widget.uasId);
      if (!mounted) return;
      if (reg == null) {
        setState(() => _error = 'Not found in FAA database');
        return;
      }
      widget.onResult(reg);
    } on FaaLookupException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSpecRow(
          label: 'FAA RemoteID Lookup',
          value: _loading ? 'Looking up…' : 'Query ${widget.uasId}',
          mono: true,
          onTap: _loading ? null : _lookup,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!,
                style: TextStyle(color: AppTheme.error, fontSize: 12)),
          ),
      ],
    );
  }
}

class _FaaResultSheet extends StatelessWidget {
  const _FaaResultSheet({
    required this.reg,
    required this.uasId,
    required this.t,
  });

  final FaaRegistration reg;
  final String uasId;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final cacheAge = DateTime.now().difference(reg.cachedAt);
    final cacheLabel = cacheAge.inSeconds < 5
        ? 'live'
        : 'cached ${_formatAge(cacheAge)} ago';

    final rows = <_FaaRow>[];
    if (reg.status.isNotEmpty) rows.add(_FaaRow('Status', reg.status));
    if (reg.displayName.isNotEmpty) rows.add(_FaaRow('Aircraft', reg.displayName));
    if (reg.brand.isNotEmpty && reg.makeName.isNotEmpty && reg.brand != reg.makeName) {
      rows.add(_FaaRow('Make', reg.makeName));
    }
    if (reg.series.isNotEmpty) rows.add(_FaaRow('Series', reg.series));
    if (reg.manufacturerCode.isNotEmpty) rows.add(_FaaRow('Mfr Code', reg.manufacturerCode));
    if (reg.productType.isNotEmpty) rows.add(_FaaRow('Type', reg.productType));
    if (reg.operationRules.isNotEmpty) rows.add(_FaaRow('Rules', reg.operationRules));
    if (reg.complianceCategories.isNotEmpty) rows.add(_FaaRow('Compliance', reg.complianceCategories));
    if (reg.trackingNumber.isNotEmpty) rows.add(_FaaRow('Tracking #', reg.trackingNumber));
    if (reg.updatedAt.isNotEmpty) rows.add(_FaaRow('Updated', _formatDate(reg.updatedAt)));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.policy_outlined, color: AppTheme.skySpy, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FAA REGISTRATION',
                      style: TextStyle(
                        color: AppTheme.skySpy,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Text(cacheLabel,
                      style: TextStyle(
                          color: t.textDim, fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                uasId,
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontFamily: AppTheme.mono),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No registration data found',
                      style: TextStyle(color: t.textDim, fontSize: 13),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.surfaceLight,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Column(
                    children: rows
                        .map((r) => _buildRow(context, r))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _FaaRow r) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: r.value));
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.label} copied',
                style: TextStyle(color: t.textPrimary)),
            backgroundColor: t.surfaceLight,
            duration: const Duration(seconds: 1),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(r.label,
                    style: TextStyle(
                        color: t.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: Text(r.value,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 11,
                        fontFamily: AppTheme.mono)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAge(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(iso));
    } on FormatException {
      return iso;
    }
  }
}

class _FaaRow {
  const _FaaRow(this.label, this.value);
  final String label;
  final String value;
}

String _odidTransportLabel(String method) => switch (method) {
  'odid_ble' => 'BLE',
  'odid_nan' => 'WiFi NAN',
  'odid_beacon' => 'WiFi Beacon',
  _ => method.toUpperCase(),
};

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.method});
  final String method;

  @override
  Widget build(BuildContext context) {
    final label = _odidTransportLabel(method);
    final color = switch (method) {
      'odid_ble' => AppTheme.detector,
      'odid_nan' => Engine.skySpy.color,
      'odid_beacon' => Engine.skySpy.color.withValues(alpha: 0.7),
      _ => Engine.skySpy.color,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: AppTheme.mono,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class DroneDetectionRow extends ConsumerWidget {
  const DroneDetectionRow({super.key, required this.group});
  final DroneGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final d = group.representative;
    final timeDiff = DateTime.now().difference(d.appTimestamp);
    final timeStr = _formatTimeDiffDrone(timeDiff);
    final nodeLabel = d.sourceNodeId.isEmpty
        ? ''
        : ref.watch(appStateProvider).labelForNode(d.sourceNodeId);
    final methodsUnique = <String>[];
    final seenMethods = <String>{};
    for (final m in group.methods) {
      if (seenMethods.add(m)) methodsUnique.add(m);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDroneDetails(context, ref),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showDroneDetails(context, ref);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Engine.skySpy.color, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.flight, size: 14, color: Engine.skySpy.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      group.uavId,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Engine.skySpy.color,
                        fontSize: 14,
                        fontFamily: AppTheme.mono,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (d.sourceNodeId.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hub, size: 11, color: AppTheme.warning),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              nodeLabel.isNotEmpty ? nodeLabel : d.sourceNodeId,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                color: AppTheme.warning,
                                fontSize: 11,
                                fontFamily: AppTheme.mono,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _RssiBlock(rssi: d.rssi),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (int i = 0; i < group.macs.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          group.macs[i].toUpperCase(),
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 10,
                            fontFamily: AppTheme.mono,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _TransportBadge(method: group.methods[i]),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Wrap(
                    spacing: 4,
                    children: methodsUnique.map((m) => _TransportBadge(method: m)).toList(),
                  ),
                  if (d.odid?.altitudeMsl != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${d.odid!.altitudeMsl}m MSL',
                      style: TextStyle(
                        color: t.textDim,
                        fontSize: 10,
                        fontFamily: AppTheme.mono,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(timeStr,
                      style: TextStyle(
                        color: t.textDim,
                        fontSize: 11,
                        fontFamily: AppTheme.mono,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDroneDetails(BuildContext context, WidgetRef ref) {
    showDetectionDetails(context, ref, group.representative);
  }

  String _formatTimeDiffDrone(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

