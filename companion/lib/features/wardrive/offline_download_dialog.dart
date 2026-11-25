// Copyright (c) 2026 Luke Switzer
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:oui_spy/core/offline/offline_maps.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart' show resolveOfflineSources;

typedef OfflineResolver = Future<({List<OfflineSource> sources, ResolvedVectorStyle? vectorStyle})> Function(
    MapStyle style, String userAgent);

Future<OfflineArea?> showOfflineDownloadDialog(
  BuildContext context, {
  required MapStyle style,
  required LatLngBounds bounds,
  required double zoom,
}) =>
    showDialog<OfflineArea>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfflineDownloadDialog(style: style, bounds: bounds, zoom: zoom),
    );

class OfflineDownloadDialog extends StatefulWidget {
  const OfflineDownloadDialog({
    super.key,
    required this.style,
    required this.bounds,
    required this.zoom,
    this.resolve = resolveOfflineSources,
    this.storeOpener = openOfflineStore,
    this.userAgentProvider = _appUserAgent,
  });

  final MapStyle style;
  final LatLngBounds bounds;
  final double zoom;
  final OfflineResolver resolve;
  final Future<OfflineStore> Function() storeOpener;
  final Future<String> Function() userAgentProvider;

  @override
  State<OfflineDownloadDialog> createState() => _OfflineDownloadDialogState();
}

Future<String> _appUserAgent() async => offlineUserAgent((await PackageInfo.fromPlatform()).version);

class _OfflineDownloadDialogState extends State<OfflineDownloadDialog> {
  OfflinePlan? _plan;
  ResolvedVectorStyle? _vector;
  String? _userAgent;
  String? _error;
  bool _downloading = false;
  int _done = 0;
  final _cancel = OfflineCancel();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final ua = await widget.userAgentProvider();
      final r = await widget.resolve(widget.style, ua);
      final plan = OfflinePlan.build(
        style: widget.style,
        sources: r.sources,
        bounds: widget.bounds,
        zoom: widget.zoom,
      );
      if (!mounted) return;
      setState(() {
        _userAgent = ua;
        _vector = r.vectorStyle;
        _plan = plan;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  String _message(Object e) {
    if (e is OfflineDownloadException) return e.message;
    if (e is DioException) return 'Network error: ${e.message ?? e.type.name}';
    return '$e';
  }

  Future<void> _save() async {
    final plan = _plan!;
    setState(() {
      _downloading = true;
      _done = 0;
      _error = null;
    });
    try {
      final store = await widget.storeOpener();
      final area = await store.download(
        plan,
        userAgent: _userAgent!,
        vectorStyle: _vector,
        cancel: _cancel,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (mounted) Navigator.pop(context, area);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final plan = _plan;
    final refusal = plan?.refusal;
    final count = NumberFormat.decimalPattern();
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(k, style: TextStyle(color: t.textDim, fontSize: 13)),
              const Spacer(),
              Text(v, style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    Widget body;
    if (plan == null) {
      body = _error != null
          ? Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 13))
          : const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Checking map source'),
            ]);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Style', widget.style.label),
          row('Zoom levels', '${plan.minZoom} to ${plan.maxZoom}'),
          row('Tiles', count.format(plan.tileCount)),
          row('Estimated size', 'about ${offlineSizeLabel(plan.estimatedBytes)}'),
          const SizedBox(height: 8),
          Text(
            'Saves the area in view. The download stops if it passes ${offlineSizeLabel(offlineMaxBytes)}.',
            style: TextStyle(color: t.textDim, fontSize: 12),
          ),
          if (refusal != null) ...[
            const SizedBox(height: 8),
            Text(refusal, style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
          if (_downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: plan.tileCount == 0 ? null : _done / plan.tileCount),
            const SizedBox(height: 4),
            Text('${count.format(_done)} of ${count.format(plan.tileCount)} tiles',
                style: TextStyle(color: t.textDim, fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
        ],
      );
    }
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        title: const Text('Save map area'),
        content: body,
        actions: [
          TextButton(
            onPressed: () {
              if (_downloading) {
                _cancel.canceled = true;
              } else {
                Navigator.pop(context);
              }
            },
            child: Text(_downloading ? 'CANCEL DOWNLOAD' : 'CANCEL'),
          ),
          if (plan != null)
            TextButton(
              onPressed: refusal != null || _downloading ? null : _save,
              child: const Text('SAVE'),
            ),
        ],
      ),
    );
  }
}
