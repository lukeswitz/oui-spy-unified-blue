// Copyright (c) 2026 Luke Switzer
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble_sniff.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';

/// Live advert table, filter and phone-side pcap recording for the BLE Sniff engine.
class BleSniffState extends ChangeNotifier {
  BleSniffState(this._ble) {
    _dataSub = _ble.pcapData.listen(_onBytes);
    _statsSub = _ble.bleSniffStats.listen((_) => _markDirty());
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _loadFilter();
  }

  static const maxRows = 300;
  static const _prefsFilter = 'blesniff_filter';

  final BleManager _ble;
  late final StreamSubscription<Uint8List> _dataSub;
  late final StreamSubscription<PcapStats> _statsSub;
  late final Timer _timer;
  final _splitter = SniffRecordSplitter();
  final _rows = <SniffAdvert>[];

  bool _dirty = false;
  bool _filterChanged = false;
  int _filter = sniffFtDefault;
  int _received = 0;
  int _lastSecond = 0;
  int _perSecond = 0;
  int _tickCount = 0;
  bool _paused = false;

  IOSink? _sink;
  File? _file;
  SniffPcapWriter? _writer;
  int _recordedBytes = 0;
  int _recordedFrames = 0;
  File? _lastSaved;

  /// Newest first.
  List<SniffAdvert> get rows => List.unmodifiable(_rows.reversed);
  int get filter => _filter;
  int get received => _received;
  int get perSecond => _perSecond;
  bool get paused => _paused;
  bool get recording => _sink != null;
  int get recordedBytes => _recordedBytes;
  int get recordedFrames => _recordedFrames;
  File? get lastSaved => _lastSaved;

  Future<void> _loadFilter() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_filterChanged) return;
      _filter = p.getInt(_prefsFilter) ?? sniffFtDefault;
      _markDirty();
    } catch (e) {
      DebugLog.log('BLESNIFF: filter load failed: $e');
    }
  }

  Future<void> setFilter(int mask, {String? targetNodeId}) async {
    final m = (mask & 0x7F) == 0 ? sniffFtDefault : (mask & 0x7F);
    _filterChanged = true;
    _filter = m;
    _markDirty();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefsFilter, m);
    } catch (e) {
      DebugLog.log('BLESNIFF: filter save failed: $e');
    }
    await pushFilter(targetNodeId: targetNodeId);
  }

  Future<void> pushFilter({String? targetNodeId}) => _ble.sendEngineConfig(
        Engine.bleSniff,
        Uint8List.fromList([
          if (targetNodeId != null) ...BleProtocol.targetEnvelope(targetNodeId),
          sniffCfgFilter,
          _filter,
        ]),
      );

  void togglePause() {
    _paused = !_paused;
    _markDirty();
  }

  void clear() {
    _rows.clear();
    _received = 0;
    _perSecond = 0;
    _lastSecond = 0;
    _markDirty();
  }

  void _markDirty() => _dirty = true;

  void _tick() {
    _tickCount++;
    if (_tickCount % 4 == 0) {
      _perSecond = _received - _lastSecond;
      _lastSecond = _received;
      _dirty = true;
    }
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
  }

  void _onBytes(Uint8List bytes) {
    final now = DateTime.now();
    for (final r in _splitter.add(bytes)) {
      final adv = decodeSniffFrame(r.frame, now);
      if (adv == null) continue;
      _received++;
      if (!_paused) {
        _rows.add(adv);
        if (_rows.length > maxRows) _rows.removeRange(0, _rows.length - maxRows);
      }
      final sink = _sink;
      final writer = _writer;
      if (sink != null && writer != null) {
        final rec = writer.record(r);
        sink.add(rec);
        _recordedBytes += rec.length;
        _recordedFrames++;
      }
    }
    _dirty = true;
  }

  Future<Directory> _pcapDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/pcaps');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> startRecording() async {
    if (_sink != null) return;
    final dir = await _pcapDir();
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now().toLocal());
    final file = File('${dir.path}/oui_spy_ble_sniff_$ts.pcap');
    final writer = SniffPcapWriter(startEpochUs: DateTime.now().microsecondsSinceEpoch);
    final sink = file.openWrite(mode: FileMode.writeOnly);
    final header = writer.header();
    sink.add(header);
    _file = file;
    _writer = writer;
    _recordedBytes = header.length;
    _recordedFrames = 0;
    _sink = sink;
    _markDirty();
  }

  Future<File?> stopRecording() async {
    final sink = _sink;
    final file = _file;
    if (sink == null) return null;
    _sink = null;
    _writer = null;
    _file = null;
    try {
      await sink.flush();
      await sink.close();
    } catch (e) {
      DebugLog.log('BLESNIFF: pcap close failed: $e');
    }
    _lastSaved = file;
    _markDirty();
    return file;
  }

  @override
  void dispose() {
    _timer.cancel();
    _dataSub.cancel();
    _statsSub.cancel();
    stopRecording();
    super.dispose();
  }
}

final bleSniffProvider = ChangeNotifierProvider<BleSniffState>((ref) {
  return BleSniffState(ref.watch(bleManagerProvider));
});
