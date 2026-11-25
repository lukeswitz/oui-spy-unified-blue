// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ota/firmware_image.dart';
import 'package:oui_spy/core/ota/mesh_firmware.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

String leftLabel(Duration d) {
  if (d.inSeconds < 10) return 'a few seconds left';
  if (d.inSeconds < 90) return '${d.inSeconds} s left';
  return '${(d.inSeconds / 60).ceil()} min left';
}

String boardLabel(String? board) => switch (board) {
      'xiao_s3' => 'XIAO ESP32-S3',
      's3_devkitc' => 'ESP32-S3 DevKitC',
      'xiao_c5' => 'XIAO ESP32-C5',
      'tdongle_s3' => 'LilyGO T-Dongle-S3',
      'tdongle_c5' => 'LilyGO T-Dongle-C5',
      'stickc' => 'M5StickC',
      'stickc_plus' => 'M5StickC PLUS',
      'stickc_plus2' => 'M5StickC PLUS2',
      null || '' => 'board unknown',
      final b => b,
    };

class MeshFirmwareScreen extends ConsumerStatefulWidget {
  const MeshFirmwareScreen({super.key});

  @override
  ConsumerState<MeshFirmwareScreen> createState() => _MeshFirmwareScreenState();
}

class _MeshFirmwareScreenState extends ConsumerState<MeshFirmwareScreen> {
  final _url = TextEditingController();
  bool _loading = false;
  bool _armed = false;
  Timer? _armTimer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(meshFirmwareProvider).busy) setState(() {});
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _armTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: 'firmware',
      extensions: ['bin'],
      uniformTypeIdentifiers: ['public.data'],
      mimeTypes: ['application/octet-stream'],
    );
    final f = await openFile(acceptedTypeGroups: const [group]);
    if (f == null) return;
    setState(() => _loading = true);
    final bytes = await f.readAsBytes();
    await ref.read(meshFirmwareProvider).load(f.name, bytes);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUrl() async {
    final u = _url.text.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) {
      _toast('Enter an http(s) link to a firmware .bin');
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await Dio().get<List<int>>(u,
          options: Options(responseType: ResponseType.bytes, followRedirects: true));
      final name = Uri.parse(u).pathSegments.isEmpty ? 'firmware.bin' : Uri.parse(u).pathSegments.last;
      await ref.read(meshFirmwareProvider).load(name, Uint8List.fromList(r.data ?? const []));
    } on DioException catch (e) {
      _toast('Could not download it (${e.response?.statusCode ?? e.type.name})');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));

  void _disarm() {
    _armTimer?.cancel();
    _armed = false;
  }

  void _update(List<String> ids) {
    if (!_armed) {
      setState(() => _armed = true);
      _armTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(_disarm);
      });
      return;
    }
    setState(_disarm);
    unawaited(ref.read(meshFirmwareProvider).start(ids));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final fw = ref.watch(meshFirmwareProvider);
    final app = ref.watch(appStateProvider);
    final ble = ref.read(bleManagerProvider);
    final nodes = app.liveKnownNodes.where((n) => n.isNotEmpty && n != app.nodeId && !app.isManagerNode(n)).toList()
      ..sort();
    final img = fw.image;
    final fits = <String, NodeFitResult>{
      if (img != null)
        for (final id in nodes) id: nodeFit(img, board: app.nodeBoard(id), fwVersion: app.nodeFwVersion(id)),
    };
    final ids = [for (final id in nodes) if (fw.picked.contains(id) && (fits[id]?.canSend ?? false)) id];

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('FIRMWARE OVER THE MESH')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'The image is saved once on the manager on this phone\'s link, then sent over the mesh to one node at a time. '
              'Each node checks it, restarts into it and rejoins. Check the image first; the manager and each node verify '
              'the OUI-SPY signature before installing.',
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
          ),
          if (!ble.isManagerConnected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Connect a manager over Bluetooth or USB: it sends the firmware to the nodes.',
                  style: TextStyle(color: AppTheme.warning, fontSize: 13)),
            ),
          const ConfigSectionHeader(label: 'Image'),
          ConfigActionRow(
            icon: Icons.upload_file,
            label: 'A .bin file',
            subtitle: 'A node firmware on this phone',
            onTap: fw.busy || _loading ? null : _pickFile,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    enabled: !fw.busy && !_loading,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'https://.../oui-spy-node-xiao_s3-v0.7.0.bin',
                      hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: fw.busy || _loading ? null : _loadUrl,
                  icon: const Icon(Icons.download),
                  tooltip: 'Download',
                ),
              ],
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
          if (fw.imageError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Not usable: ${fw.imageError}', style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          if (img != null) ..._imageRows(img),
          const SizedBox(height: 12),
          const ConfigSectionHeader(label: 'Nodes'),
          if (nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No node heard on the mesh yet.', style: TextStyle(color: t.textDim, fontSize: 13)),
            ),
          for (final id in nodes) _nodeRow(t, fw, app, id, fits[id]),
          const SizedBox(height: 12),
          if (fw.step == MeshFwStep.staging) _stagingBlock(t, fw),
          if (fw.runError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(fw.runError!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          if (fw.busy)
            OutlinedButton.icon(
              onPressed: () => unawaited(fw.stop()),
              icon: const Icon(Icons.stop),
              label: const Text('STOP'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: BorderSide(color: AppTheme.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: img == null || ids.isEmpty || !ble.isManagerConnected ? null : () => _update(ids),
              icon: const Icon(Icons.system_update_alt),
              label: Text(img == null
                  ? 'Load an image first'
                  : ids.isEmpty
                      ? 'Pick a node'
                      : _armed
                          ? 'Tap again to update ${ids.length} node${ids.length == 1 ? '' : 's'}'
                          : 'Update ${ids.length} selected'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          if (fw.step == MeshFwStep.finished && fw.runs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_summary(fw), style: TextStyle(color: t.textSecondary, fontSize: 12)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _summary(MeshFirmwareController fw) {
    final bad = fw.runs.where((r) => r.state != NodeRunState.done && r.state != NodeRunState.unconfirmed).length;
    return bad == 0 ? 'Firmware: all selected nodes updated' : 'Firmware: $bad node${bad == 1 ? '' : 's'} need attention';
  }

  List<Widget> _imageRows(FirmwareImage img) => [
        ConfigInfoRow(icon: Icons.insert_drive_file_outlined, label: 'File', value: img.name.isEmpty ? '-' : img.name),
        ConfigInfoRow(icon: Icons.memory, label: 'Chip', value: '${img.chip} (id ${img.chipId})'),
        ConfigInfoRow(
          icon: Icons.sell_outlined,
          label: 'Build',
          value: [
            if (img.projectName.isNotEmpty) img.projectName,
            if (img.versionLabel.isNotEmpty) img.versionLabel,
            if (img.board != null) img.board!,
          ].join('  ·  '),
        ),
        ConfigInfoRow(icon: Icons.straighten, label: 'Size', value: '${(img.size / 1024).toStringAsFixed(0)} KB'),
        ConfigInfoRow(
          icon: Icons.verified_outlined,
          label: 'Signature',
          value: img.signed ? 'OUI-SPY signed' : 'not signed',
          color: img.signed ? AppTheme.success : AppTheme.error,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText('SHA-256  ${img.sha256Hex}',
              style: TextStyle(color: AppTheme.of(context).textSecondary, fontSize: 11, fontFamily: AppTheme.mono)),
        ),
      ];

  Widget _stagingBlock(ResolvedTheme t, MeshFirmwareController fw) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STEP 1 OF 2  ·  UPLOAD TO THE MANAGER',
                style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2, fontFamily: AppTheme.mono)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: fw.stageFraction == 0 ? null : fw.stageFraction, minHeight: 5),
            const SizedBox(height: 4),
            Text(fw.stageNote, style: TextStyle(color: t.textSecondary, fontSize: 11)),
          ],
        ),
      );

  Widget _nodeRow(ResolvedTheme t, MeshFirmwareController fw, AppState app, String id, NodeFitResult? fit) {
    final run = fw.runs.where((r) => r.id == id).firstOrNull;
    final version = app.nodeFwVersion(id);
    final selectable = !fw.busy && (fit?.canSend ?? true);
    final color = switch (fit?.fit) {
      NodeFit.current => AppTheme.success,
      NodeFit.older => AppTheme.accent,
      NodeFit.otherBoard => AppTheme.error,
      _ => t.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: fw.picked.contains(id),
                onChanged: selectable ? (_) => setState(() {
                      _disarm();
                      fw.toggle(id);
                    }) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.labelForNode(id), style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                      '${boardLabel(app.nodeBoard(id))}  ·  ${version == null ? 'build unknown' : 'v$version'}',
                      style: TextStyle(color: t.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (fit != null)
                Text(fit.fit.label.toUpperCase(),
                    style: TextStyle(color: color, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
            ],
          ),
          if (fit != null && fit.fit != NodeFit.older && fit.fit != NodeFit.current)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(fit.why, style: TextStyle(color: t.textDim, fontSize: 11)),
            ),
          if (run != null) Padding(padding: const EdgeInsets.only(left: 48, top: 4), child: _runLine(t, fw, run, app)),
        ],
      ),
    );
  }

  Widget _runLine(ResolvedTheme t, MeshFirmwareController fw, NodeRun r, AppState app) {
    final size = fw.image?.size ?? 0;
    switch (r.state) {
      case NodeRunState.waiting:
        return Text(fw.step == MeshFwStep.staging ? 'WAITING FOR THE MANAGER TO HAVE THE IMAGE' : 'WAITING ITS TURN: the manager sends to one node at a time',
            style: TextStyle(color: t.textDim, fontSize: 11));
      case NodeRunState.sending:
        final rate = r.kbps(size, fw.now);
        final left = r.timeLeft(size, fw.now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STEP 2 OF 2  ·  SENDING OVER THE MESH', style: TextStyle(color: AppTheme.accent, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: r.total == 0 || r.recv == 0 ? null : r.fraction, minHeight: 5),
            const SizedBox(height: 4),
            Text(
              [
                r.recv == 0 ? 'Offering it the image' : '${(r.fraction * 100).round()}%',
                if (rate != null) '${rate.toStringAsFixed(1)} kbps',
                if (left != null) leftLabel(left),
              ].join('  ·  '),
              style: TextStyle(color: t.textSecondary, fontSize: 11),
            ),
          ],
        );
      case NodeRunState.done:
      case NodeRunState.unconfirmed:
        final now = app.nodeFwVersion(r.id);
        final want = fw.image?.nameVersion ?? fw.image?.descVersion;
        final confirmed = now != null && parseImageVersion(want)?.join('.') == parseImageVersion(now)?.join('.');
        return Text(
          r.state == NodeRunState.unconfirmed
              ? 'SENT  ·  the node restarted before it confirmed; read its status to check its build'
              : confirmed
                  ? 'DONE  ·  runs v$now'
                  : 'DONE  ·  restarting into the new build',
          style: TextStyle(color: AppTheme.success, fontSize: 11),
        );
      case NodeRunState.failed:
        return Text('FAILED  ·  ${r.reason}', style: TextStyle(color: AppTheme.error, fontSize: 11));
      case NodeRunState.stopped:
        return Text('STOPPED', style: TextStyle(color: AppTheme.warning, fontSize: 11));
    }
  }
}
